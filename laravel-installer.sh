#!/usr/bin/env bash

# Laravel Auto-Installer — by Faiz
# Optimized for Mac, Linux, and WSL
# One script. One command. Laravel ready in minutes.

set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 0. VARIABLES & COLORS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ANSI Colors
RED='\033[31m'
GREEN='\033[32m'
L_GREEN='\033[92m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
L_CYAN='\033[96m'
GREY='\033[90m'
RESET='\033[0m'
BOLD='\033[1m'

# Defaults (can be overridden by environment variables)
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
DB_NAME="${DB_NAME:-laravel_db}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
LARAVEL_VERSION="${LARAVEL_VERSION:-latest}"
USE_DOCKER="${USE_DOCKER:-n}"
INSTALL_FRONTEND="${INSTALL_FRONTEND:-n}"
FRONTEND_TYPE="${FRONTEND_TYPE:-None}"
GENERATE_CRUD="${GENERATE_CRUD:-n}"
MODE="interactive"
LOG_FILE="logs/install.log"
INSTALL_PATH="${INSTALL_PATH:-}"

# Status Tracking for Summary
S_LARAVEL="SKIP"
S_SANCTUM="SKIP"
S_TELESCOPE="SKIP"
S_SPATIE="SKIP"
S_DOCKER="SKIP"
S_UUID="None"
S_API="None"
GENERATED_MODELS_DATA=()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. UI HELPERS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log_ok() { printf "${GREEN}[ OK ]${RESET} %s\n" "$1"; }
log_fail() { printf "${RED}[ FAIL ]${RESET} %s\n" "$1"; }
log_skip() { printf "${YELLOW}[ SKIP ]${RESET} %s\n" "$1"; }
log_info() { printf "${CYAN}[ INFO ]${RESET} %s\n" "$1"; }

prompt_with_default() {
    local prompt=$1
    local default=$2
    local input=""

    read -r -p "$prompt [$default]: " input
    printf "%s" "${input:-$default}"
}

prompt_secret_with_default() {
    local prompt=$1
    local default=$2
    local input=""
    local hint=""

    [ -n "$default" ] && hint="keep current"
    read -r -s -p "$prompt [$hint]: " input
    printf "\n" >&2
    printf "%s" "${input:-$default}"
}

prompt_yes_no() {
    local prompt=$1
    local default=${2:-n}
    local input=""
    local label="[y/n]"

    [[ "$default" =~ ^[Yy]$ ]] && label="[Y/n]"
    [[ "$default" =~ ^[Nn]$ ]] && label="[y/N]"

    read -r -p "$prompt $label: " input
    input=${input:-$default}
    [[ "$input" =~ ^[Yy]$ ]]
}

run_with_spinner() {
    "$@" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    spinner "$pid"
    wait "$pid"
}

set_status() {
    local key=$1
    local value=$2
    key=$(printf "%s" "$key" | tr '[:lower:]' '[:upper:]')
    printf -v "S_${key}" "%s" "$value"
}

escape_sed_replacement() {
    printf "%s" "$1" | sed -e 's/[\/&|\\]/\\&/g'
}

set_env_value() {
    local key=$1
    local value=$2
    local escaped
    escaped=$(escape_sed_replacement "$value")
    # Handle optional # and space at start of line
    if grep -qE "^#? ?${key}=" .env; then
        if [[ "$OS_TYPE" == "Mac" ]]; then
            sed -i '' -E "s|^#? ?${key}=.*|${key}=${escaped}|g" .env
        else
            sed -i -E "s|^#? ?${key}=.*|${key}=${escaped}|g" .env
        fi
    else
        printf "%s=%s\n" "$key" "$value" >> .env
    fi

    # De-duplicate: If multiple identical keys exist, keep only the last one
    # This is a bit complex for sed, so we'll rely on the global replace above
    # which should have standardized all existing ones to the same value.
    
    find . -name "*.env''" -delete 2>/dev/null || true
}

ensure_api_routes_file() {
    mkdir -p routes
    if [ ! -f "routes/api.php" ]; then
        cat > routes/api.php <<'EOF'
<?php

use Illuminate\Support\Facades\Route;

EOF
    fi
}

valid_model_name() {
    [[ "$1" =~ ^[A-Z][A-Za-z0-9]*$ ]]
}

valid_table_name() {
    [[ "$1" =~ ^[a-z][a-z0-9_]*$ ]]
}

valid_field_name() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

valid_field_type() {
    case "$1" in
        string|text|integer|bigInteger|bigint|boolean|date|dateTime|datetime|timestamp|decimal|float|uuid|foreign) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_field_type() {
    case "$1" in
        bigint) printf "bigInteger" ;;
        datetime) printf "dateTime" ;;
        *) printf "%s" "$1" ;;
    esac
}

trim() {
    local value=$1
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf "%s" "$value"
}

validate_crud_input() {
    local model_name=$1
    local table_name=$2
    local fields=$3
    local entries=()
    local raw_field=""

    CRUD_VALIDATION_ERROR=""

    if ! valid_model_name "$model_name"; then
        CRUD_VALIDATION_ERROR="Model harus diawali huruf besar dan hanya berisi huruf/angka. Contoh: Product"
        return 1
    fi

    if ! valid_table_name "$table_name"; then
        CRUD_VALIDATION_ERROR="Nama table harus huruf kecil/angka/underscore. Contoh: products"
        return 1
    fi

    if [ -z "$(trim "$fields")" ]; then
        CRUD_VALIDATION_ERROR="Fields tidak boleh kosong. Contoh: name:string,price:integer"
        return 1
    fi

    IFS=',' read -ra entries <<< "$fields"
    for raw_field in "${entries[@]}"; do
        raw_field=$(trim "$raw_field")
        if [ -z "$raw_field" ]; then
            CRUD_VALIDATION_ERROR="Ada field kosong. Hapus koma berlebih di input fields."
            return 1
        fi

        IFS=':' read -ra FIELD <<< "$raw_field"
        local field_name
        local field_type
        local field_ref

        field_name=$(trim "${FIELD[0]:-}")
        field_type=$(trim "${FIELD[1]:-string}")
        field_ref=$(trim "${FIELD[2]:-}")

        if ! valid_field_name "$field_name"; then
            CRUD_VALIDATION_ERROR="Nama field '$field_name' tidak valid. Contoh: name atau user_id"
            return 1
        fi

        if ! valid_field_type "$field_type"; then
            CRUD_VALIDATION_ERROR="Tipe '$field_type' tidak didukung. Gunakan string, text, integer, bigint, boolean, date, datetime, decimal, float, uuid, atau foreign."
            return 1
        fi

        if [ "$field_type" == "foreign" ] && ! valid_table_name "$field_ref"; then
            CRUD_VALIDATION_ERROR="Field foreign '$field_name' harus punya referensi table valid. Contoh: user_id:foreign:users"
            return 1
        fi
    done
}

spinner() {
    local pid=$1
    local width=30
    local progress=0
    while [ "$(ps -p $pid -o state= 2>/dev/null)" ]; do
        local filled=$((progress % (width + 1)))
        local empty=$((width - filled))
        printf "\r ${CYAN}⚡ Loading${RESET} ["
        printf "${L_GREEN}"
        for ((j=0; j<filled; j++)); do printf "█"; done
        printf "${GREY}"
        for ((j=0; j<empty; j++)); do printf "░"; done
        printf "${RESET}] "
        sleep 0.1
        progress=$((progress + 1))
    done
    printf "\r\033[K" # Clear the line
}

progress_bar() {
    local task=$1
    local width=40
    printf "${CYAN}🛰️  $task${RESET}\n"
    for ((i=0; i<=100; i++)); do
        local filled=$((i * width / 100))
        local empty=$((width - filled))
        printf "\r ${L_CYAN}➤${RESET} ["
        printf "${L_GREEN}"
        for ((j=0; j<filled; j++)); do printf "█"; done
        printf "${GREY}"
        for ((j=0; j<empty; j++)); do printf "░"; done
        printf "${RESET}] ${BOLD}%d%%${RESET}" "$i"
        sleep 0.01
    done
    printf "\n"
}

show_banner() {
    clear 2>/dev/null || true
    printf "${L_GREEN}"
    printf "███████╗ █████╗ ██╗███████╗\n"
    printf "██╔════╝██╔══██╗██║╚══███╔╝\n"
    printf "█████╗  ███████║██║  ███╔╝ \n"
    printf "██╔══╝  ██╔══██║██║ ███╔╝  \n"
    printf "██║     ██║  ██║██║███████╗\n"
    printf "╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝\n"
    printf "${L_CYAN}  // Laravel Auto-Installer — by Faiz${RESET}\n"
    printf "${GREY}  Satu script. Satu perintah. Laravel siap dalam hitungan menit.${RESET}\n"
    printf "${GREY}  Sanctum · UUID · OTP · CRUD Generator · API Helper · Response Helper${RESET}\n"
    printf "  ══════════════════════════════════════════════════════════${RESET}\n"
}

show_help() {
    echo "Usage: ./laravel-installer.sh [options]"
    echo ""
    echo "Options:"
    echo "  --quick            Install with best default settings without questions"
    echo "  --no-interaction   Read configuration from environment variables"
    echo "  --update           Update the installer script"
    echo "  --help             Show this help message"
    echo ""
    echo "Environment Variables (for --no-interaction):"
echo "  INSTALL_PATH       Target folder. Example: my-api"
    echo "  LARAVEL_VERSION    latest, 10.*, 11.*, 12.*, or another Composer constraint"
    echo "  DB_NAME, DB_USER, DB_PASS, DB_HOST, DB_PORT"
    echo "  USE_DOCKER         y or n"
    echo "  GENERATE_CRUD      y or n"
    echo "  CRUD_MODEL, CRUD_TABLE, CRUD_FIELDS"
    echo ""
    echo "Examples:"
    echo "  ./laravel-installer.sh"
    echo "  ./laravel-installer.sh --quick"
    echo "  INSTALL_PATH=my-api DB_NAME=my_api ./laravel-installer.sh --no-interaction"
    echo "  GENERATE_CRUD=y CRUD_MODEL=Product CRUD_TABLE=products CRUD_FIELDS=name:string,price:integer ./laravel-installer.sh --no-interaction"
    exit 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1.5. MAIN MENU
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

show_main_menu() {
    if [[ "$MODE" == "quick" || "$MODE" == "no-interaction" ]]; then
        return
    fi

    printf "\n${BOLD}Apa yang ingin Anda lakukan?${RESET}\n"
    printf "[1] Install Laravel Baru (Full Setup)\n"
    printf "[2] Generate CRUD Baru (di Project Existing)\n"
    read -r -p "Pilihan [1]: " main_opt
    main_opt=${main_opt:-1}

    if [ "$main_opt" == "2" ]; then
        if [ ! -f "artisan" ]; then
            log_info "Mencari project Laravel di subfolder..."
            
            # Find subdirectories with artisan file (max depth 2 for performance)
            local projects=()
            while IFS= read -r project; do
                projects+=("$project")
            done < <(find . -maxdepth 2 -name artisan 2>/dev/null | sed 's/\/artisan//' | sed 's/^\.\///')
            
            if [ ${#projects[@]} -eq 0 ]; then
                log_fail "Error: Tidak ada project Laravel ditemukan di folder ini atau subfolder."
                exit 1
            fi
            
            printf "\n${BOLD}Ditemukan beberapa project, pilih salah satu:${RESET}\n"
            for i in "${!projects[@]}"; do
                printf "[%d] %s\n" "$((i+1))" "${projects[$i]}"
            done
            printf "[q] Batal\n"
            
            read -r -p "Pilihan: " proj_opt
            if [[ "$proj_opt" == "q" ]]; then exit 0; fi

            if ! [[ "$proj_opt" =~ ^[0-9]+$ ]] || [ "$proj_opt" -lt 1 ] || [ "$proj_opt" -gt "${#projects[@]}" ]; then
                log_fail "Pilihan tidak valid."
                exit 1
            fi
            
            local selected_proj=${projects[$((proj_opt-1))]:-""}
            if [ -z "$selected_proj" ]; then
                log_fail "Pilihan tidak valid."
                exit 1
            fi
            
            cd "$selected_proj"
            log_ok "Berpindah ke project: $selected_proj"
        fi
        
        # Setup helpers if missing
        if [ ! -f "app/Traits/HasUuid.php" ]; then
            printf "\n"
            if prompt_yes_no "API Helpers & UUID Trait belum ada. Install sekarang?" "y"; then
                setup_uuid_and_helpers
            fi
        fi

        run_crud_generator
        log_ok "Proses CRUD Selesai."
        exit 0
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. VALIDATION & ENVIRONMENT CHECK
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

check_dependencies() {
    mkdir -p logs
    touch "$LOG_FILE"
    
    log_info "Checking dependencies..."
    
    local deps=("php" "composer" "git")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_fail "$dep is not installed. Please install it first."
            case "$dep" in
                php) echo "Install PHP: brew install php (Mac) or sudo apt install php (Ubuntu)";;
                composer) echo "Install Composer: https://getcomposer.org/download/";;
                git) echo "Install Git: brew install git (Mac) or sudo apt install git (Ubuntu)";;
            esac
            exit 1
        fi
    done

    # Check PHP version
    PHP_VER=$(php -r "echo PHP_VERSION_ID;")
    if [ "$PHP_VER" -lt 80100 ]; then
        log_fail "PHP version must be 8.1 or higher. Current version: $(php -v | head -n 1)"
        exit 1
    fi
    
    log_ok "All core dependencies satisfied."
}

show_environment_info() {
    local php_version=$(php -v | head -n 1 | awk '{print $2}')
    local recommendation=""
    
    # Recommendation logic based on PHP version
    if [[ "$php_version" == 8.1* ]]; then
        recommendation="Laravel 10.x"
    elif [[ "$php_version" == 8.2* ]]; then
        recommendation="Laravel 11.x"
    elif [[ "$php_version" == 8.3* || "$php_version" == 8.4* ]]; then
        recommendation="Laravel 12.x"
    else
        recommendation="Laravel 12.x"
    fi

    printf "\n${CYAN}📊 INFORMASI SISTEM:${RESET}\n"
    printf "OS (jenis sistem operasi)                   : $OS_TYPE\n" 
    printf "PHP Version (yang terinstall)               : $php_version\n"
    printf "Rekomendasi Laravel (versi yang disarankan) : ${L_GREEN}$recommendation${RESET}\n"
    printf "══════════════════════════════════════════════════════════\n"
}

detect_os() {
    OS_TYPE="Unknown"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="Mac"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /proc/version ] && grep -q Microsoft /proc/version; then
            OS_TYPE="WSL"
        else
            OS_TYPE="Linux"
        fi
    fi
    log_info "Environment detected: $OS_TYPE"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. EXECUTION MODES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

handle_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                MODE="quick"
                shift
                ;;
            --no-interaction)
                MODE="no-interaction"
                shift
                ;;
            --help)
                show_help
                ;;
            --update)
                log_info "Updating script..."
                # In real scenario, curl from github
                # curl -sSL https://raw.githubusercontent.com/user/repo/main/laravel-installer.sh -o laravel-installer.sh
                log_ok "Script updated (simulation)."
                exit 0
                ;;
            *)
                log_fail "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. LARAVEL VERSION SELECTION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

select_version() {
    if [[ "$MODE" == "quick" || "$MODE" == "no-interaction" ]]; then
        LARAVEL_VERSION=${LARAVEL_VERSION:-latest}
        return
    fi

    echo -e "\n${BOLD}Select Laravel Version:${RESET}"
    echo "[1] Laravel 10.x"
    echo "[2] Laravel 11.x"
    echo "[3] Laravel 12.x (latest)"
    echo "[4] Custom Composer constraint"
    read -r -p "Option [3]: " ver_opt
    ver_opt=${ver_opt:-3}

    case $ver_opt in
        1) LARAVEL_VERSION="10.*" ;;
        2) LARAVEL_VERSION="11.*" ;;
        3) LARAVEL_VERSION="latest" ;;
        4) read -r -p "Constraint (example: 12.*): " LARAVEL_VERSION
           LARAVEL_VERSION=${LARAVEL_VERSION:-latest}
           ;;
        *) LARAVEL_VERSION="latest" ;;
    esac
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4.5. PROJECT DIRECTORY SELECTION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

select_project_dir() {
    if [[ "$MODE" == "quick" || "$MODE" == "no-interaction" ]]; then
        INSTALL_PATH=${INSTALL_PATH:-laravel-app}
        return 0
    fi

    printf "\n${BOLD}Project Configuration:${RESET}\n"
    printf "${GREY}(Ketik 'back' untuk kembali ke versi)${RESET}\n"
    read -r -p "Enter Project Name (folder name) [laravel-app]: " folder_name
    
    if [[ "$folder_name" == "back" ]]; then return 1; fi
    
    INSTALL_PATH=${folder_name:-laravel-app}
    return 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. CORE INSTALLATION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_laravel() {
    if [ -f "artisan" ]; then
        log_skip "Laravel project already exists in this folder."
        S_LARAVEL="SKIP"
        return
    fi

    INSTALL_PATH=${INSTALL_PATH:-laravel-app}
    log_info "Installing Laravel ($LARAVEL_VERSION) into '$INSTALL_PATH'..."
    
    if [ "$LARAVEL_VERSION" == "latest" ]; then
        if ! run_with_spinner composer create-project laravel/laravel "$INSTALL_PATH"; then
            log_fail "Laravel installation failed. Check $LOG_FILE"
            exit 1
        fi
    else
        if ! run_with_spinner composer create-project laravel/laravel "$INSTALL_PATH" "$LARAVEL_VERSION"; then
            log_fail "Laravel installation failed. Check $LOG_FILE"
            exit 1
        fi
    fi

    # Move into the directory if it's not current
    if [ "$INSTALL_PATH" != "." ]; then
        cd "$INSTALL_PATH"
        # Move logs to the new folder for consistency
        mkdir -p logs
        cp ../logs/install.log logs/install.log 2>/dev/null || true
    fi

    # Install API support for Laravel 11+
    if [ -f "artisan" ]; then
        log_info "Enabling API support (artisan install:api)..."
        run_with_spinner php artisan install:api --no-interaction || log_skip "artisan install:api skipped or unavailable."
    fi

    if [ -f "artisan" ]; then
        log_ok "Laravel installed successfully."
        S_LARAVEL="OK"
    else
        log_fail "Laravel installation failed. Check $LOG_FILE"
        exit 1
    fi
}

setup_env() {
    if [ ! -f ".env" ]; then
        if [ ! -f ".env.example" ]; then
            log_fail ".env.example not found. Pastikan command dijalankan di root project Laravel."
            exit 1
        fi
        log_info "Setting up .env file..."
        cp .env.example .env
        php artisan key:generate >> "$LOG_FILE" 2>&1
        log_ok ".env initialized."
    else
        log_skip ".env already exists."
    fi

    if [[ "$MODE" == "quick" ]]; then
        update_env_db
        return
    fi

    if [[ "$MODE" != "no-interaction" ]]; then
        echo -e "\n${BOLD}Database Configuration:${RESET}"
        DB_NAME=$(prompt_with_default "DB Name" "$DB_NAME")
        DB_USER=$(prompt_with_default "DB User" "$DB_USER")
        DB_PASS=$(prompt_secret_with_default "DB Pass" "$DB_PASS")
        DB_HOST=$(prompt_with_default "DB Host" "$DB_HOST")
        DB_PORT=$(prompt_with_default "DB Port" "$DB_PORT")
    fi

    update_env_db
}

update_env_db() {
    set_env_value "DB_CONNECTION" "mysql"
    set_env_value "DB_DATABASE" "$DB_NAME"
    set_env_value "DB_USERNAME" "$DB_USER"
    set_env_value "DB_PASSWORD" "$DB_PASS"
    set_env_value "DB_HOST" "$DB_HOST"
    set_env_value "DB_PORT" "$DB_PORT"
    
    # The new env updater avoids creating sed backup files, so existing files are left untouched.
    
    # Add API Base URL
    set_env_value "API_BASE_URL" '${APP_URL}/api'
    
    log_ok ".env updated with database credentials and API_BASE_URL."
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. DOCKER SETUP
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_docker() {
    if [[ "$MODE" == "quick" ]]; then
        return
    fi

    local should_install="$USE_DOCKER"

    if [[ "$MODE" == "no-interaction" ]]; then
        [[ "$should_install" =~ ^[Yy]$ ]] || return
    elif prompt_yes_no "Generate Docker Configuration (Dockerfile & Compose)?" "n"; then
        should_install="y"
    else
        should_install="n"
    fi

    [[ "$should_install" =~ ^[Yy]$ ]] || return

    log_info "Generating custom Docker configuration..."
    
    # 1. Create Dockerfile
    cat > Dockerfile <<EOF
FROM php:8.4-fpm

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    git \\
    curl \\
    libpng-dev \\
    libonig-dev \\
    libxml2-dev \\
    zip \\
    unzip

# Clear cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd

# Get latest Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www

# Copy existing application directory contents
COPY . /var/www

# Copy existing application directory permissions
COPY --chown=www-data:www-data . /var/www

# Change current user to www
USER www-data

EXPOSE 9000
CMD ["php-fpm"]
EOF

    # 2. Create docker-compose.yml
    cat > docker-compose.yml <<EOF
version: '3.8'
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    image: laravel-app
    container_name: laravel_app
    restart: unless-stopped
    working_dir: /var/www
    volumes:
      - ./:/var/www
    networks:
      - laravel-network

  db:
    image: mysql:8.0
    container_name: laravel_db_container
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: \${DB_DATABASE}
      MYSQL_ROOT_PASSWORD: \${DB_PASSWORD}
      MYSQL_PASSWORD: \${DB_PASSWORD}
      MYSQL_USER: \${DB_USERNAME}
    ports:
      - "33060:3306"
    volumes:
      - dbdata:/var/lib/mysql
    networks:
      - laravel-network

  nginx:
    image: nginx:alpine
    container_name: laravel_nginx
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./:/var/www
      - ./docker/nginx/conf.d/:/etc/nginx/conf.d/
    networks:
      - laravel-network

networks:
  laravel-network:
    driver: bridge

volumes:
  dbdata:
    driver: local
EOF

    # 3. Create Nginx config
    mkdir -p docker/nginx/conf.d
    cat > docker/nginx/conf.d/app.conf <<EOF
server {
    listen 80;
    index index.php index.html;
    error_log  /var/log/nginx/error.log;
    access_log /var/log/nginx/access.log;
    root /var/www/public;
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass app:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
        gzip_static on;
    }
}
EOF

    # Update .env to use 'db' as host for internal docker communication
    # set_env_value "DB_HOST" "db"
    
    log_ok "Docker configuration (Dockerfile, Compose, Nginx) ready."
    S_DOCKER="Custom"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. MANDATORY PACKAGES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

install_package() {
    local name=$1
    local status_key=$2
    shift 2
    
    log_info "Installing $name..."
    
    if run_with_spinner "$@"; then
        log_ok "$name installed."
        set_status "$status_key" "OK"
    else
        log_fail "$name installation failed."
        set_status "$status_key" "FAIL"
    fi
}

install_mandatory_packages() {
    # Sanctum (usually default in 10+, but ensuring)
    install_package "Sanctum" "Sanctum" composer require laravel/sanctum
    
    # Telescope
    install_package "Telescope (dev)" "Telescope" bash -c "composer require laravel/telescope --dev && php artisan telescope:install"
    
    # Spatie Permission
    install_package "Spatie Permission" "Spatie" composer require spatie/laravel-permission
    log_ok "Mandatory packages installed."
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. UUID & API HELPERS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_uuid_and_helpers() {
    log_info "Setting up UUID Trait and API Helpers..."

    # Create Traits directory
    # We will use Laravel's built-in HasUuids trait for better compatibility
    log_info "Using Laravel's built-in HasUuids trait..."
    mkdir -p app/Traits

    # API Response Helper
    mkdir -p app/Helpers
    # Response Helper
    mkdir -p app/Helpers
    cat > app/Helpers/ResponseHelper.php <<EOF
<?php

namespace App\Helpers;

class ResponseHelper
{
    public static function success(\$data = null, \$message = 'Success', \$code = 200)
    {
        return response()->json([
            'status' => 'success',
            'message' => \$message,
            'data' => \$data
        ], \$code);
    }

    public static function error(\$message = 'Error', \$code = 400, \$errors = null)
    {
        return response()->json([
            'status' => 'error',
            'message' => \$message,
            'errors' => \$errors
        ], \$code);
    }
}
EOF

    # API Request Helper (Client Wrapper)
    cat > app/Helpers/ApiRequest.php <<EOF
<?php

namespace App\Helpers;

use Illuminate\Support\Facades\Http;

class ApiRequest
{
    public static function get(\$url, \$params = [], \$token = null)
    {
        return self::send('get', \$url, \$params, \$token);
    }

    public static function post(\$url, \$data = [], \$token = null)
    {
        return self::send('post', \$url, \$data, \$token);
    }

    public static function put(\$url, \$data = [], \$token = null)
    {
        return self::send('put', \$url, \$data, \$token);
    }

    public static function delete(\$url, \$data = [], \$token = null)
    {
        return self::send('delete', \$url, \$data, \$token);
    }

    protected static function send(\$method, \$url, \$data = [], \$token = null)
    {
        \$baseUrl = env('API_BASE_URL', 'http://localhost:8000/api');
        \$fullUrl = rtrim(\$baseUrl, '/') . '/' . ltrim(\$url, '/');

        \$request = Http::withHeaders([
            'Accept' => 'application/json',
            'Content-Type' => 'application/json',
        ]);

        if (\$token) {
            \$request = \$request->withToken(\$token);
        }

        return \$request->\$method(\$fullUrl, \$data);
    }
}
EOF

    # Base API Controller
    cat > app/Http/Controllers/BaseApiController.php <<EOF
<?php

namespace App\Http\Controllers;

use App\Helpers\ResponseHelper;
use Illuminate\Routing\Controller as BaseController;

class BaseApiController extends BaseController
{
    protected function success(\$data = null, \$message = 'Success', \$code = 200)
    {
        return ResponseHelper::success(\$data, \$message, \$code);
    }

    protected function error(\$message = 'Error', \$code = 400, \$errors = null)
    {
        return ResponseHelper::error(\$message, \$code, \$errors);
    }
}
EOF

    # Update User Model to use HasUuids
    if [[ "$OS_TYPE" == "Mac" ]]; then
        sed -i '' "s/use HasFactory, Notifiable;/use HasFactory, Notifiable, HasUuids;/" app/Models/User.php
        sed -i '' "/namespace App\\\\Models;/a \\
use Illuminate\\\\Database\\\\Eloquent\\\\Concerns\\\\HasUuids;" app/Models/User.php
    else
        sed -i "s/use HasFactory, Notifiable;/use HasFactory, Notifiable, HasUuids;/" app/Models/User.php
        sed -i "/namespace App\\\\Models;/a use Illuminate\\\\Database\\\\Eloquent\\\\Concerns\\\\HasUuids;" app/Models/User.php
    fi

    # Convert ALL migrations to UUID (excluding personal_access_tokens to keep Sanctum compatible)
    log_info "Converting all migrations to UUID & Adding SoftDeletes..."
    if [[ "$OS_TYPE" == "Mac" ]]; then
        find database/migrations -name "*.php" ! -name "*personal_access_tokens*" -exec sed -i '' "s/.*\$table->id();/            \$table->uuid('id')->primary();/g" {} +
        find database/migrations -name "*.php" -exec sed -i '' "s/foreignId(/foreignUuid(/g" {} +
        find database/migrations -name "*.php" -exec sed -i '' "s/morphs(/uuidMorphs(/g" {} +
        # Add SoftDeletes to all migrations
        find database/migrations -name "*.php" -exec sed -i '' "s/.*\$table->timestamps();/            \$table->timestamps();\n            \$table->softDeletes();/g" {} +
    else
        find database/migrations -name "*.php" ! -name "*personal_access_tokens*" -exec sed -i "s/.*\$table->id();/            \$table->uuid('id')->primary();/g" {} +
        find database/migrations -name "*.php" -exec sed -i "s/foreignId(/foreignUuid(/g" {} +
        find database/migrations -name "*.php" -exec sed -i "s/morphs(/uuidMorphs(/g" {} +
        find database/migrations -name "*.php" -exec sed -i "s/.*\$table->timestamps();/            \$table->timestamps();\n            \$table->softDeletes();/g" {} +
    fi
    
    log_ok "UUID and API Helpers ready."
    S_UUID="OK"
    S_API="OK"
    
    setup_api_auth
}

setup_api_auth() {
    log_info "Setting up API Authentication (Sanctum)..."

    mkdir -p app/Http/Controllers/Api
    cat > app/Http/Controllers/Api/AuthController.php <<EOF
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\BaseApiController;
use App\Models\User;
use App\Models\OtpCode;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;

class AuthController extends BaseApiController
{
    public function register(Request \$request)
    {
        \$validator = Validator::make(\$request->all(), [
            'name' => 'required|string|max:255',
            'email' => 'required|string|email|max:255|unique:users',
            'password' => 'required|string|min:8|confirmed',
        ]);

        if (\$validator->fails()) {
            return \$this->error('Validation Error', 422, \$validator->errors());
        }

        \$user = User::create([
            'name' => \$request->name,
            'email' => \$request->email,
            'password' => Hash::make(\$request->password),
        ]);

        \$token = \$user->createToken('auth_token')->plainTextToken;

        return \$this->success([
            'user' => \$user,
            'token' => \$token
        ], 'User registered successfully');
    }

    public function login(Request \$request)
    {
        \$validator = Validator::make(\$request->all(), [
            'email' => 'required|email',
            'password' => 'required',
        ]);

        if (\$validator->fails()) {
            return \$this->error('Validation Error', 422, \$validator->errors());
        }

        \$user = User::where('email', \$request->email)->first();

        if (!\$user || !Hash::check(\$request->password, \$user->password)) {
            return \$this->error('Invalid credentials', 401);
        }

        \$token = \$user->createToken('auth_token')->plainTextToken;

        return \$this->success([
            'user' => \$user,
            'token' => \$token
        ], 'Login successful');
    }

    public function logout(Request \$request)
    {
        \$request->user()->currentAccessToken()->delete();
        return \$this->success(null, 'Logged out successfully');
    }

    public function sendOTP(Request \$request)
    {
        \$validator = Validator::make(\$request->all(), [
            'email' => 'required|email|exists:users,email',
        ]);

        if (\$validator->fails()) {
            return \$this->error('Validation Error', 422, \$validator->errors());
        }

        \$email = \$request->email;
        \$otp = str_pad(random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        
        // Save OTP to Database
        OtpCode::updateOrCreate(
            ['email' => \$email],
            [
                'otp' => \$otp,
                'token' => null,
                'expires_at' => now()->addMinutes(5),
                'is_used' => false
            ]
        );

        // Mail::to(\$email)->send(new \App\Mail\SendOTPMail(\$otp));
        
        return \$this->success([
            'email' => \$email,
            'otp_preview' => \$otp 
        ], 'OTP has been sent to your email. Valid for 5 minutes.');
    }

    public function verifyOTP(Request \$request)
    {
        \$validator = Validator::make(\$request->all(), [
            'email' => 'required|email|exists:users,email',
            'otp' => 'required|string|min:6|max:6',
        ]);

        if (\$validator->fails()) {
            return \$this->error('Validation Error', 422, \$validator->errors());
        }

        \$otpRecord = OtpCode::where('email', \$request->email)
            ->where('otp', \$request->otp)
            ->where('is_used', false)
            ->where('expires_at', '>', now())
            ->first();

        if (\$otpRecord) {
            \$resetToken = Str::random(64);
            \$otpRecord->update([
                'token' => \$resetToken,
                'is_used' => true
            ]);

            return \$this->success([
                'reset_token' => \$resetToken
            ], 'OTP verified successfully. You can now reset your password.');
        }

        return \$this->error('Invalid or expired OTP', 400);
    }

    public function resetPassword(Request \$request)
    {
        \$validator = Validator::make(\$request->all(), [
            'email' => 'required|email|exists:users,email',
            'reset_token' => 'required|string',
            'password' => 'required|string|min:8|confirmed',
        ]);

        if (\$validator->fails()) {
            return \$this->error('Validation Error', 422, \$validator->errors());
        }

        \$otpRecord = OtpCode::where('email', \$request->email)
            ->where('token', \$request->reset_token)
            ->where('is_used' , true)
            ->where('updated_at', '>', now()->addMinutes(-10))
            ->first();

        if (!\$otpRecord) {
            return \$this->error('Invalid or expired reset token', 400);
        }

        \$user = User::where('email', \$request->email)->first();
        \$user->update([
            'password' => Hash::make(\$request->password)
        ]);

        \$otpRecord->delete();

        return \$this->success(null, 'Password has been reset successfully');
    }
}
EOF

    # 4. Create OtpCode Model
    cat > app/Models/OtpCode.php <<EOF
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class OtpCode extends Model
{
    use HasUuids;

    protected \$fillable = [
        'email',
        'otp',
        'token',
        'expires_at',
        'is_used'
    ];

    protected \$casts = [
        'expires_at' => 'datetime',
        'is_used' => 'boolean'
    ];
}
EOF

    # 5. Create otp_codes Migration
    local otp_migration="database/migrations/\$(date +%Y_%m_%d_%H%M%S)_create_otp_codes_table.php"
    cat > "\$otp_migration" <<EOF
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('otp_codes', function (Blueprint \$table) {
            \$table->uuid('id')->primary();
            \$table->string('email')->index();
            \$table->string('otp');
            \$table->string('token')->nullable();
            \$table->timestamp('expires_at');
            \$table->boolean('is_used')->default(false);
            \$table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('otp_codes');
    }
};
EOF

    # 6. Ensure User model has HasApiTokens for Sanctum
    if ! grep -q "HasApiTokens" app/Models/User.php; then
        if [[ "$OS_TYPE" == "Mac" ]]; then
            sed -i '' "s/use HasFactory, Notifiable, HasUuids;/use HasApiTokens, HasFactory, Notifiable, HasUuids;/" app/Models/User.php
            sed -i '' "/namespace App\\\\Models;/a \\
use Laravel\\\\Sanctum\\\\HasApiTokens;" app/Models/User.php
        else
            sed -i "s/use HasFactory, Notifiable, HasUuids;/use HasApiTokens, HasFactory, Notifiable, HasUuids;/" app/Models/User.php
            sed -i "/namespace App\\\\Models;/a use Laravel\\\\Sanctum\\\\HasApiTokens;" app/Models/User.php
        fi
    fi

    # Remove default Laravel 11 /user route to prevent duplicates
    # Use perl for safe multi-line removal of the default /user route
    perl -i -0777 -pe 's/Route::get\('\''\/user'\''.*?\}\)->middleware\('\''auth:sanctum'\''\);//gs' routes/api.php 2>/dev/null || true
    perl -i -0777 -pe 's/Route::get\('\''\/user'\''.*?\}\);//gs' routes/api.php 2>/dev/null || true

    # Update routes/api.php
    ensure_api_routes_file
    
    # Add Import to api.php
    if ! grep -q "AuthController" routes/api.php; then
        if [[ "$OS_TYPE" == "Mac" ]]; then
            sed -i '' "1a\\
use App\\\\Http\\\\Controllers\\\\Api\\\\AuthController;" routes/api.php
        else
            sed -i "1a use App\\Http\\Controllers\\Api\\AuthController;" routes/api.php
        fi
    fi

    if grep -q "FAIZ_INSTALLER_AUTH_ROUTES_START" routes/api.php; then
        log_skip "API auth routes already registered."
    else
        cat >> routes/api.php <<'EOF'

// FAIZ_INSTALLER_AUTH_ROUTES_START
Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);
Route::post('/otp/send', [AuthController::class, 'sendOTP']);
Route::post('/otp/verify', [AuthController::class, 'verifyOTP']);
Route::post('/password/reset', [AuthController::class, 'resetPassword']);

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user', function (\Illuminate\Http\Request $request) {
        return $request->user();
    });
    Route::post('/logout', [AuthController::class, 'logout']);
});
// FAIZ_INSTALLER_AUTH_ROUTES_END
EOF
    fi

    log_ok "API Auth system (Login, Register, Logout, Forgot Password) ready."
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 10. CRUD GENERATOR
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

run_crud_generator() {
    if [[ "$MODE" == "quick" ]]; then return 0; fi

    if [[ "$MODE" == "no-interaction" ]]; then
        [[ "$GENERATE_CRUD" =~ ^[Yy]$ ]] || return 0
        model_name=${CRUD_MODEL:-}
        table_name=${CRUD_TABLE:-}
        fields=${CRUD_FIELDS:-}
        if ! validate_crud_input "$model_name" "$table_name" "$fields"; then
            log_fail "$CRUD_VALIDATION_ERROR"
            return 1
        fi
    else
        while true; do
            printf "\n${BOLD}CRUD Generator:${RESET}\n"
            printf "${GREY}(Ketik 'back' untuk kembali ke instalasi, 'skip' untuk lewat)${RESET}\n"
            read -r -p "Generate a CRUD now? (y/n/back/skip) [n]: " crud_opt
            
            if [[ "$crud_opt" == "back" ]]; then return 1; fi
            if [[ "$crud_opt" == "skip" || ! "$crud_opt" =~ ^[Yy]$ ]]; then return 0; fi

            read -r -p "Model Name (e.g. Product): " model_name
            read -r -p "Table Name (e.g. products): " table_name
            printf "${GREY}Fields (format: name:string,price:integer,user_id:foreign:users)${RESET}\n"
            read -r -p "Fields: " fields

            if ! validate_crud_input "$model_name" "$table_name" "$fields"; then
                log_fail "$CRUD_VALIDATION_ERROR"
                log_info "Mengulang input CRUD..."
                continue
            fi

            # Basic Confirmation
            echo -e "\n${CYAN}Konfirmasi CRUD:${RESET}"
            echo "Model : $model_name"
            echo "Table : $table_name"
            echo "Fields: $fields"
            read -r -p "Apakah data ini sudah benar? (y/retry/back): " confirm
            
            if [[ "$confirm" == "back" ]]; then return 1; fi
            if [[ "$confirm" =~ ^[Yy]$ ]]; then break; fi
            log_info "Mengulang input CRUD..."
        done
    fi
    
    log_info "Generating Best Practice CRUD for $model_name..."
    GENERATED_MODELS_DATA+=("${model_name}|${fields}")
    
    # 1. Migration
    local migration_output=""
    local migration_file=""

    if ! migration_output=$(php artisan make:migration "create_${table_name}_table" --path=database/migrations 2>> "$LOG_FILE"); then
        log_fail "Gagal membuat migration. Check $LOG_FILE"
        return 1
    fi
    migration_file=$(printf "%s" "$migration_output" | grep -o 'database/migrations/.*\.php' | head -n 1 || true)

    if [ -z "$migration_file" ] || [ ! -f "$migration_file" ]; then
        log_fail "Migration file tidak ditemukan setelah make:migration. Check $LOG_FILE"
        return 1
    fi
    
    # Parse fields for migration
    local migration_fields=""
    local fillables=""
    local validation_rules=""
    
    IFS=',' read -ra ADDR <<< "$fields"
    for i in "${ADDR[@]}"; do
        i=$(trim "$i")
        IFS=':' read -ra FIELD <<< "$i"
        local f_name
        local f_type
        local f_ref
        f_name=$(trim "${FIELD[0]}")
        f_type=$(normalize_field_type "$(trim "${FIELD[1]:-string}")")
        f_ref=$(trim "${FIELD[2]:-}")
        
        if [ "$f_type" == "foreign" ]; then
            migration_fields+="            \$table->foreignUuid('${f_name}')->constrained('${f_ref}')->onDelete('cascade');\n"
        else
            migration_fields+="            \$table->${f_type}('${f_name}')->nullable();\n"
        fi
        
        fillables+="'${f_name}', "
        validation_rules+="'${f_name}' => 'required',"
    done

    # Update Migration File using a more robust approach for Mac/Linux
    printf "%b" "$migration_fields" > migration_fields.tmp
    
    if [[ "$OS_TYPE" == "Mac" ]]; then
        sed -i '' "/\$table->id();/r migration_fields.tmp" "$migration_file"
        sed -i '' "s/.*\$table->id();/            \$table->uuid('id')->primary();/" "$migration_file"
    else
        sed -i "/\$table->id();/r migration_fields.tmp" "$migration_file"
        sed -i "s/.*\$table->id();/            \$table->uuid('id')->primary();/" "$migration_file"
    fi
    rm migration_fields.tmp

    # 2. Model with UUID & SoftDeletes
    php artisan make:model "$model_name" >> "$LOG_FILE" 2>&1
    cat > "app/Models/${model_name}.php" <<EOF
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ${model_name} extends Model
{
    use HasUuids, SoftDeletes;

    protected \$fillable = [${fillables}];
}
EOF

    # 3. Controller with Best Practice Logic
    mkdir -p app/Http/Controllers/Api
    cat > "app/Http/Controllers/Api/${model_name}Controller.php" <<EOF
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\BaseApiController;
use App\Models\\${model_name};
use App\Helpers\ResponseHelper;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ${model_name}Controller extends BaseApiController
{
    public function index()
    {
        \$data = ${model_name}::latest()->get();
        return ResponseHelper::success(\$data, 'Data retrieved successfully');
    }

    public function store(Request \$request)
    {
        \$validator = Validator::make(\$request->all(), [
            ${validation_rules}
        ]);

        if (\$validator->fails()) {
            return ResponseHelper::error('Validation Error', 422, \$validator->errors());
        }

        \$item = ${model_name}::create(\$request->all());
        return ResponseHelper::success(\$item, 'Data created successfully', 201);
    }

    public function show(\$id)
    {
        \$item = ${model_name}::find(\$id);
        if (!\$item) return ResponseHelper::error('Data not found', 404);
        
        return ResponseHelper::success(\$item, 'Data retrieved successfully');
    }

    public function update(Request \$request, \$id)
    {
        \$item = ${model_name}::find(\$id);
        if (!\$item) return ResponseHelper::error('Data not found', 404);

        \$validator = Validator::make(\$request->all(), [
            ${validation_rules}
        ]);

        if (\$validator->fails()) {
            return ResponseHelper::error('Validation Error', 422, \$validator->errors());
        }

        \$item->update(\$request->all());
        return ResponseHelper::success(\$item, 'Data updated successfully');
    }

    public function destroy(\$id)
    {
        \$item = ${model_name}::find(\$id);
        if (!\$item) return ResponseHelper::error('Data not found', 404);

        \$item->delete();
        return ResponseHelper::success(null, 'Data deleted successfully');
    }
}
EOF

    # 4. Route with Import
    ensure_api_routes_file
    
    # Add Import to api.php
    if ! grep -q "${model_name}Controller" routes/api.php; then
        sed -i '' "1a\\
use App\\\\Http\\\\Controllers\\\\Api\\\\${model_name}Controller;" routes/api.php 2>/dev/null || \
        sed -i "1a use App\\Http\\Controllers\\Api\\${model_name}Controller;" routes/api.php
    fi

    local route_marker="FAIZ_INSTALLER_CRUD_${table_name}_ROUTES_START"
    if grep -q "$route_marker" routes/api.php; then
        log_skip "Route CRUD untuk $table_name sudah ada."
    else
        {
            printf "\n// %s\n" "$route_marker"
            printf "Route::apiResource('/%s', %sController::class);\n" "$table_name" "$model_name"
            printf "// FAIZ_INSTALLER_CRUD_%s_ROUTES_END\n" "$table_name"
        } >> routes/api.php
    fi

    # NEW: Add API JSON Response for root route
    log_info "Setting up API root response..."
    cat > routes/web.php <<EOF
<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response()->json([
        'app' => 'Laravel API',
        'status' => 'Running',
        'author' => 'Faiz Auto-Installer'
    ]);
});
EOF
    log_ok "API root response ready."

    log_ok "CRUD for $model_name generated successfully with full API logic."
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11. DEFAULT USER SEEDER
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_default_user() {
    log_info "Creating default admin user..."
    
    cat > database/seeders/AdminUserSeeder.php <<EOF
<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class AdminUserSeeder extends Seeder
{
    public function run()
    {
        // Create Admin
        User::updateOrCreate(
            ['email' => 'admin@mail.com'],
            [
                'name' => 'Admin Faiz',
                'password' => Hash::make('password'),
                'email_verified_at' => now(),
            ]
        );

        // Create Regular User for Testing
        User::updateOrCreate(
            ['email' => 'user@mail.com'],
            [
                'name' => 'Regular User',
                'password' => Hash::make('password'),
                'email_verified_at' => now(),
            ]
        );
    }
}
EOF
    
    # Add to DatabaseSeeder (Robust Way)
    if grep -q "AdminUserSeeder::class" database/seeders/DatabaseSeeder.php; then
        log_skip "AdminUserSeeder already registered."
    else
        # Using perl for safe multiline replacement inside the run() method
        if grep -q "run(): void" database/seeders/DatabaseSeeder.php; then
            perl -i -pe 'BEGIN{undef $/;} s/(public function run\(\): void\s*\{)/$1\n        \$this->call(AdminUserSeeder::class);/g' database/seeders/DatabaseSeeder.php
        else
            # Fallback for older versions
            if [[ "$OS_TYPE" == "Mac" ]]; then
                sed -i '' "/run()/a \\
        \$this->call(AdminUserSeeder::class);" database/seeders/DatabaseSeeder.php 2>/dev/null || true
            else
                sed -i "/run()/a \        \$this->call(AdminUserSeeder::class);" database/seeders/DatabaseSeeder.php 2>/dev/null || true
            fi
        fi
    fi

    log_ok "AdminUserSeeder created (admin@mail.com / password)."
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 12. FINALIZATION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

show_summary() {
    local next_path=${INSTALL_PATH:-.}

    echo -e "\n"
    echo -e "╔══════════════════════════════════════════════╗"
    echo -e "║${BOLD}          FAIZ INSTALLER — SUMMARY            ${RESET}║"
    echo -e "╠══════════════════════════════════════════════╣"
    
    print_summary_line() {
        local key=$1
        local status=$2
        local color=$GREEN
        [[ "$status" == "FAIL" ]] && color=$RED
        [[ "$status" == "SKIP" || "$status" == "None" ]] && color=$YELLOW
        printf "║ %-20s [  ${color}%-9s${RESET}  ] ║\n" "$key" "$status"
    }

    print_summary_line "Laravel" "$S_LARAVEL"
    print_summary_line "Sanctum" "$S_SANCTUM"
    print_summary_line "Telescope" "$S_TELESCOPE"
    print_summary_line "Spatie" "$S_SPATIE"
    print_summary_line "Docker" "$S_DOCKER"
    print_summary_line "UUID Setup" "$S_UUID"
    print_summary_line "API Helpers" "$S_API"
    
    echo -e "╚══════════════════════════════════════════════╝"
    echo -e "\n${BOLD}🔑 TEST CREDENTIALS:${RESET}"
    echo -e "Admin : admin@mail.com / password"
    echo -e "User  : user@mail.com  / password"

    echo -e "\n${L_CYAN}Next Steps:${RESET}"
    echo -e "1. cd $next_path"
    echo -e "2. php artisan migrate --seed"
    echo -e "3. php artisan serve"
    
    if [[ "$S_DOCKER" == "Custom" ]]; then
        echo -e "\n${GREY}(Or use Docker: docker-compose up -d)${RESET}"
    fi
    echo ""
    log_ok "Installation Finished! Happy Coding."

    if prompt_yes_no "Generate Postman Collection?" "y"; then
        generate_postman_collection
    fi
}

generate_postman_collection() {
    local project_name=$(basename "$(pwd)")
    local file_name="${project_name}_postman_collection.json"
    
    log_info "Generating Postman Collection..."
    
    cat > "$file_name" <<EOF
{
	"info": {
		"name": "${project_name} API",
		"schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
	},
	"item": [
		{
			"name": "Auth",
			"item": [
				{
					"name": "Register",
					"request": {
						"method": "POST",
						"header": [
							{"key": "Accept", "value": "application/json"}
						],
						"body": {
							"mode": "raw",
							"raw": "{\n    \"name\": \"Test User\",\n    \"email\": \"test@mail.com\",\n    \"password\": \"password\",\n    \"password_confirmation\": \"password\"\n}",
							"options": {"raw": {"language": "json"}}
						},
						"url": { "raw": "{{base_url}}/register", "host": ["{{base_url}}"], "path": ["register"] }
					}
				},
				{
					"name": "Login",
					"event": [
						{
							"listen": "test",
							"script": {
								"exec": [
									"var jsonData = pm.response.json();",
									"if (jsonData.data && jsonData.data.token) {",
									"    pm.environment.set(\"token\", jsonData.data.token);",
									"}"
								],
								"type": "text/javascript"
							}
						}
					],
					"request": {
						"method": "POST",
						"header": [
							{"key": "Accept", "value": "application/json"}
						],
						"body": {
							"mode": "raw",
							"raw": "{\n    \"email\": \"admin@mail.com\",\n    \"password\": \"password\"\n}",
							"options": {"raw": {"language": "json"}}
						},
						"url": { "raw": "{{base_url}}/login", "host": ["{{base_url}}"], "path": ["login"] }
					}
				},
				{
					"name": "Send OTP",
					"request": {
						"method": "POST",
						"header": [
							{"key": "Accept", "value": "application/json"}
						],
						"body": {
							"mode": "raw",
							"raw": "{\n    \"email\": \"admin@mail.com\"\n}",
							"options": {"raw": {"language": "json"}}
						},
						"url": { "raw": "{{base_url}}/otp/send", "host": ["{{base_url}}"], "path": ["otp", "send"] }
					}
				},
				{
					"name": "Verify OTP",
					"request": {
						"method": "POST",
						"header": [
							{"key": "Accept", "value": "application/json"}
						],
						"body": {
							"mode": "raw",
							"raw": "{\n    \"email\": \"admin@mail.com\",\n    \"otp\": \"123456\"\n}",
							"options": {"raw": {"language": "json"}}
						},
						"url": { "raw": "{{base_url}}/otp/verify", "host": ["{{base_url}}"], "path": ["otp", "verify"] }
					}
				},
				{
					"name": "Reset Password",
					"request": {
						"method": "POST",
						"header": [
							{"key": "Accept", "value": "application/json"}
						],
						"body": {
							"mode": "raw",
							"raw": "{\n    \"email\": \"admin@mail.com\",\n    \"reset_token\": \"TOKEN_DARI_VERIFY_OTP\",\n    \"password\": \"newpassword123\",\n    \"password_confirmation\": \"newpassword123\"\n}",
							"options": {"raw": {"language": "json"}}
						},
						"url": { "raw": "{{base_url}}/password/reset", "host": ["{{base_url}}"], "path": ["password", "reset"] }
					}
				},
				{
					"name": "Logout",
					"request": {
						"auth": { "type": "bearer", "bearer": [{"key": "token", "value": "{{token}}", "type": "string"}] },
						"method": "POST",
						"header": [
							{"key": "Accept", "value": "application/json"}
						],
						"url": { "raw": "{{base_url}}/logout", "host": ["{{base_url}}"], "path": ["logout"] }
					}
				}
			]
		}
EOF

    for data in "${GENERATED_MODELS_DATA[@]}"; do
        local model=$(echo "$data" | cut -d'|' -f1)
        local raw_fields=$(echo "$data" | cut -d'|' -f2)
        local lower_model=$(echo "$model" | tr '[:upper:]' '[:lower:]')
        local plural_model="${lower_model}s"
        
        # Build JSON body from fields
        local json_body="{\\n"
        IFS=',' read -ra ADDR <<< "$raw_fields"
        local first=true
        for field_def in "${ADDR[@]}"; do
            local field_name=$(echo "$field_def" | cut -d':' -f1)
            local field_type=$(echo "$field_def" | cut -d':' -f2)
            
            if [ "$first" = true ]; then
                first=false
            else
                json_body+=",\\n"
            fi
            
            local val="\\\"\\\""
            [[ "$field_type" == "integer" || "$field_type" == "float" || "$field_type" == "decimal" ]] && val="0"
            [[ "$field_type" == "boolean" ]] && val="true"
            
            json_body+="    \\\"$field_name\\\": $val"
        done
        json_body+="\\n}"

        cat >> "$file_name" <<EOF
		,{
			"name": "${model}",
			"item": [
				{
					"name": "List ${model}",
					"request": {
						"auth": { "type": "bearer", "bearer": [{"key": "token", "value": "{{token}}", "type": "string"}] },
						"method": "GET",
						"header": [{"key": "Accept", "value": "application/json"}],
						"url": { "raw": "{{base_url}}/${plural_model}", "host": ["{{base_url}}"], "path": ["${plural_model}"] }
					}
				},
				{
					"name": "Create ${model}",
					"request": {
						"auth": { "type": "bearer", "bearer": [{"key": "token", "value": "{{token}}", "type": "string"}] },
						"method": "POST",
						"header": [{"key": "Accept", "value": "application/json"}],
						"body": {
							"mode": "raw",
							"raw": "${json_body}",
							"options": {"raw": {"language": "json"}}
						},
						"url": { "raw": "{{base_url}}/${plural_model}", "host": ["{{base_url}}"], "path": ["${plural_model}"] }
					}
				},
				{
					"name": "Get ${model}",
					"request": {
						"auth": { "type": "bearer", "bearer": [{"key": "token", "value": "{{token}}", "type": "string"}] },
						"method": "GET",
						"header": [{"key": "Accept", "value": "application/json"}],
						"url": { "raw": "{{base_url}}/${plural_model}/:id", "host": ["{{base_url}}"], "path": ["${plural_model}", ":id"], "variable": [{"key": "id", "value": ""}] }
					}
				},
				{
					"name": "Update ${model}",
					"request": {
						"auth": { "type": "bearer", "bearer": [{"key": "token", "value": "{{token}}", "type": "string"}] },
						"method": "PUT",
						"header": [{"key": "Accept", "value": "application/json"}],
						"body": {
							"mode": "raw",
							"raw": "${json_body}",
							"options": {"raw": {"language": "json"}}
						},
						"url": { "raw": "{{base_url}}/${plural_model}/:id", "host": ["{{base_url}}"], "path": ["${plural_model}", ":id"], "variable": [{"key": "id", "value": ""}] }
					}
				},
				{
					"name": "Delete ${model}",
					"request": {
						"auth": { "type": "bearer", "bearer": [{"key": "token", "value": "{{token}}", "type": "string"}] },
						"method": "DELETE",
						"header": [{"key": "Accept", "value": "application/json"}],
						"url": { "raw": "{{base_url}}/${plural_model}/:id", "host": ["{{base_url}}"], "path": ["${plural_model}", ":id"], "variable": [{"key": "id", "value": ""}] }
					}
				}
			]
		}
EOF
    done

    cat >> "$file_name" <<EOF
	],
	"variable": [
		{ "key": "base_url", "value": "http://localhost:8000/api", "type": "string" },
		{ "key": "token", "value": "", "type": "string" }
	]
}
EOF
    log_ok "Postman Collection generated: ${file_name}"
}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MAIN EXECUTION (State Machine Flow)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

handle_args "$@"
show_banner
check_dependencies
detect_os
show_environment_info

STEP=1
while [ $STEP -ne 0 ] && [ $STEP -le 10 ]; do
    case $STEP in
        1)  show_main_menu && STEP=2 ;;
        2)  select_version && STEP=3 || STEP=1 ;;
        3)  select_project_dir && STEP=4 || STEP=2 ;;
        4)  install_laravel && STEP=5 || STEP=3 ;;
        5)  run_crud_generator && STEP=6 || STEP=4 ;;
        6)  setup_docker && STEP=7 || STEP=5 ;;
        7)  setup_env && STEP=8 || STEP=6 ;;
        8)  install_mandatory_packages && STEP=9 || STEP=7 ;;
        9)  setup_uuid_and_helpers && STEP=10 || STEP=8 ;;
        10) setup_default_user && STEP=11 || STEP=9 ;;
    esac
done

show_summary
