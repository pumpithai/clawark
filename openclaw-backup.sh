#!/bin/bash
# OpenClaw Backup Script
# Usage: ./backup.sh [--restore] [--exclude=FOLDER] [--include-only=FOLDER]

set -e

HOME_DIR="${HOME:-$HOME}"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME_DIR/.openclaw}"
BACKUP_DIR="${BACKUP_DIR:-$OPENCLAW_DIR/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_TYPE="manual"
BACKUP_NAME="openclaw_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

EXCLUDE_DIRS=()
INCLUDE_ONLY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --exclude=*)
            EXCLUDE_DIRS+=("${1#*=}")
            shift
            ;;
        --include-only=*)
            INCLUDE_ONLY="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

is_excluded() {
    local dir="$1"
    for excluded in "${EXCLUDE_DIRS[@]}"; do
        if [[ "$dir" == "$excluded" ]] || [[ "$dir" == "$excluded/"* ]]; then
            return 0
        fi
    done
    return 1
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create backup directory
mkdir -p "$BACKUP_DIR"

backup() {
    log_info "Starting backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    local rsync_opts="-a --exclude='.git' --exclude='node_modules'"
    
    if [ -n "$INCLUDE_ONLY" ]; then
        log_info "Including only: $INCLUDE_ONLY"
        rsync_opts="$rsync_opts --include='$INCLUDE_ONLY' --include='*/' --exclude='*'"
    elif [ ${#EXCLUDE_DIRS[@]} -gt 0 ]; then
        log_info "Excluding: ${EXCLUDE_DIRS[*]}"
        for dir in "${EXCLUDE_DIRS[@]}"; do
            rsync_opts="$rsync_opts --exclude='$dir' --exclude='$dir/*'"
        done
    fi
    
    mkdir -p "$BACKUP_PATH"
    
    log_info "Backing up .openclaw..."
    eval "rsync $rsync_opts '$OPENCLAW_DIR/' '$BACKUP_PATH/'"
    
    mkdir -p "$BACKUP_PATH/openclaw-backup"
    cp -f "$0" "$BACKUP_PATH/openclaw-backup/"
    
    log_info "Creating archive..."
    cd "$BACKUP_DIR"
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
    rm -rf "$BACKUP_PATH"
    
    echo "{\"type\":\"$BACKUP_TYPE\",\"excluded\":$(printf '%s\n' "${EXCLUDE_DIRS[@]}" | jq -R . | jq -s .),\"created\":\"$(date -Iseconds)\"}" > "${BACKUP_DIR}/${BACKUP_NAME}.json"
    
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -5
    
    log_info "Backup complete: ${BACKUP_NAME}.tar.gz"
    echo "$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
}

restore() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        log_warn "Available backups:"
        ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || log_error "No backups found"
        echo ""
        echo "Usage: $0 --restore /path/to/backup.tar.gz"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    log_warn "This will overwrite current .openclaw data!"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Restore cancelled"
        exit 0
    fi
    
    local temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir"
    
    local extracted_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    
    log_info "Restoring .openclaw..."
    rsync -a --delete "$extracted_dir/" "$OPENCLAW_DIR/"
    
    rm -rf "$temp_dir"
    
    log_info "Restore complete!"
}

list_backups() {
    log_info "Available backups:"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || log_error "No backups found"
}

case "${1:-}" in
    --restore|-r)
        restore "$2"
        ;;
    --list|-l)
        list_backups
        ;;
    --auto|-a)
        BACKUP_TYPE="auto"
        BACKUP_NAME="openclaw_${BACKUP_TYPE}_backup_${TIMESTAMP}"
        BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
        backup
        ;;
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --restore <file>     Restore from backup file"
        echo "  --list              List available backups"
        echo "  --auto              Automatic backup (cron)"
        echo "  --exclude=<dir>     Exclude directory from backup (can use multiple)"
        echo "  --include-only=<dir> Only backup specific directory"
        echo "  --help              Show this help"
        echo ""
        echo "Examples:"
        echo "  $0                                    Backup all"
        echo "  $0 --exclude=workspace               Backup without workspace"
        echo "  $0 --exclude=media --exclude=cache   Backup without media and cache"
        echo "  $0 --include-only=skills             Backup only skills folder"
        ;;
    *)
        backup
        ;;
esac
