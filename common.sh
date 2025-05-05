#!/bin/bash

# Цвета
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Логирование с уровнями
log_action() {
    local level="$1"
    local message="$2"
    local log_file="$3"
    local max_size=$((1024*1024)) # 1MB

    # Проверка, передан ли путь к лог-файлу
    if [ -z "$log_file" ]; then
        echo -e "${RED}Ошибка: не указан лог-файл для log_action${NC}" >&2
        return 1
    fi

    # Создание директории для лог-файла, если она отсутствует
    local log_dir
    log_dir=$(dirname "$log_file")
    mkdir -p "$log_dir" 2>/dev/null || {
        echo -e "${RED}Ошибка создания директории для логов: $log_dir${NC}" >&2
        return 1
    }

    # Проверка и создание лог-файла
    touch "$log_file" 2>/dev/null || {
        echo -e "${RED}Ошибка создания лог-файла $log_file${NC}" >&2
        return 1
    }

    # Проверка прав на запись
    if [ ! -w "$log_file" ]; then {
        echo -e "${RED}Нет прав на запись в $log_file${NC}" >&2
        return 1
    }

    # Ротация логов при превышении размера
    if [ -f "$log_file" ] && [ "$(stat -c %s "$log_file")" -gt "$max_size" ]; then {
        mv "$log_file" "$log_file.old" 2>/dev/null || {
            echo -e "${RED}Ошибка ротации логов $log_file${NC}" >&2
            return 1
        }
    }

    # Запись в лог
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $(whoami) - [$level] $message" >> "$log_file" 2>/dev/null || {
        echo -e "${RED}Ошибка записи в лог-файл $log_file${NC}" >&2
        return 1
    }
}

# Проверка прав root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Требуются права root!${NC}" >&2
        log_action "ERROR" "Запуск без прав root" "$LOG_FILE"
        exit 1
    }
}

# Проверка и установка зависимостей
install_dependencies() {
    local deps="$1"
    local updated=false
    echo -e "${YELLOW}Проверка зависимостей...${NC}"
    for cmd in $deps; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${YELLOW}Установка $cmd...${NC}"
            if ! $updated; then
                apt update -y || {
                    echo -e "${RED}Ошибка обновления репозиториев${NC}" >&2
                    log_action "ERROR" "Ошибка обновления репозиториев" "$LOG_FILE"
                    exit 1
                }
                updated=true
            fi
            apt install -y "$cmd" || {
                echo -e "${RED}Ошибка установки $cmd${NC}" >&2
                log_action "ERROR" "Ошибка установки $cmd" "$LOG_FILE"
                exit 1
            }
        fi
    done
    echo -e "${GREEN}Все зависимости установлены.${NC}"
    log_action "INFO" "Все зависимости установлены" "$LOG_FILE"
}

# Проверка соединения с интернетом
check_internet() {
    ping -c 1 8.8.8.8 >/dev/null 2>&1 || {
        echo -e "${RED}Нет соединения с интернетом${NC}" >&2
        log_action "ERROR" "Нет соединения с интернетом" "$LOG_FILE"
        exit 1
    }
}

# Обновление через Git
update_from_git() {
    local repo_url="$1"
    local branch="$2"
    local target_dir="$3"
    local log_file="$4"
    local repo_dir="/tmp/sap_repo_$(date +%s)"

    # Проверка зависимостей
    install_dependencies "git"

    # Проверка интернета
    check_internet

    echo -e "${YELLOW}Обновление скриптов через Git...${NC}"

    # Клонирование или обновление репозитория
    if [ -d "$repo_dir" ]; then
        rm -rf "$repo_dir"
    fi

    git clone --depth 1 --branch "$branch" "$repo_url" "$repo_dir" >/dev/null 2>&1 || {
        echo -e "${RED}Ошибка клонирования репозитория${NC}" >&2
        log_action "ERROR" "Ошибка клонирования $repo_url" "$log_file"
        exit 1
    }

    # Копирование файлов
    for file in sap.sh pritunl.sh openvpn-client.sh common.sh app_list.txt default.txt; do
        if [ -f "$repo_dir/$file" ]; then
            cp "$repo_dir/$file" "$target_dir/" || {
                echo -e "${RED}Ошибка копирования $file${NC}" >&2
                log_action "ERROR" "Ошибка копирования $file" "$log_file"
                exit 1
            }
            chmod +x "$target_dir/$file" 2>/dev/null || true
            dos2unix "$target_dir/$file" 2>/dev/null || true
            echo -e "${GREEN}$file обновлен${NC}"
            log_action "INFO" "$file обновлен" "$log_file"
        else
            echo -e "${YELLOW}Файл $file не найден в репозитории${NC}"
            log_action "WARNING" "Файл $file не найден в репозитории" "$log_file"
        fi
    done

    # Очистка
    rm -rf "$repo_dir"
    echo -e "${GREEN}Обновление завершено${NC}"
    log_action "INFO" "Обновление через Git завершено" "$log_file"
}
