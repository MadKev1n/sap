#!/bin/bash

# Подключение common.sh
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/common.sh" || {
    echo -e "${RED}Не удалось подключить common.sh${NC}" >&2
    exit 1
}

# Конфигурация
readonly VPN_DIR="/root/set-app-ports/vpn"
readonly OVPN_FILE="${VPN_DIR}/client.ovpn"
readonly LOG_FILE="/var/log/openvpn-client.log"

# Проверка прав и зависимостей
check_root
install_dependencies "openvpn curl wget unzip coreutils"

# Проверка URL
check_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        echo -e "${RED}Некорректный URL${NC}" >&2
        log_action "ERROR" "Некорректный URL: $url" "$LOG_FILE"
        exit 1
    fi
    log_action "INFO" "URL проверен: $url" "$LOG_FILE"
}

# Очистка
cleanup() {
    echo -e "${YELLOW}Очистка...${NC}"
    # Завершение процессов OpenVPN
    if pgrep openvpn >/dev/null 2>&1; then
        pkill -SIGTERM openvpn 2>/dev/null || {
            echo -e "${RED}Ошибка завершения процессов OpenVPN${NC}" >&2
            log_action "ERROR" "Ошибка завершения процессов OpenVPN" "$LOG_FILE"
        }
        sleep 1
    fi
    # Проверка и создание директории
    mkdir -p "${VPN_DIR}" || {
        echo -e "${RED}Ошибка создания директории $VPN_DIR${NC}" >&2
        log_action "ERROR" "Ошибка создания директории $VPN_DIR" "$LOG_FILE"
        exit 1
    }
    # Очистка содержимого
    rm -rf "${VPN_DIR}"/* 2>/dev/null || {
        echo -e "${RED}Ошибка очистки директории $VPN_DIR${NC}" >&2
        log_action "ERROR" "Ошибка очистки директории $VPN_DIR" "$LOG_FILE"
        exit 1
    }
    echo -e "${GREEN}Очистка завершена${NC}"
    log_action "INFO" "Очистка завершена" "$LOG_FILE"
}

# Загрузка профиля
download_profile() {
    local url="$1"
    echo -e "${YELLOW}Загрузка профиля...${NC}"
    local archive_name="${VPN_DIR}/profile_$(date +%s).zip"
    wget --no-check-certificate -q --show-progress -O "$archive_name" "$url" || {
        echo -e "${RED}Ошибка загрузки профиля${NC}" >&2
        log_action "ERROR" "Ошибка загрузки профиля с $url" "$LOG_FILE"
        exit 1
    }
    unzip -oj "$archive_name" -d "$VPN_DIR" || {
        echo -e "${RED}Ошибка распаковки${NC}" >&2
        log_action "ERROR" "Ошибка распаковки $archive_name" "$LOG_FILE"
        exit 1
    }
    local ovpn_files=("$VPN_DIR"/*.ovpn)
    if [ ${#ovpn_files[@]} -eq 0 ] || [ ! -f "${ovpn_files[0]}" ]; then
        echo -e "${RED}Нет .ovpn файла в архиве${NC}" >&2
        log_action "ERROR" "Отсутствует .ovpn файл" "$LOG_FILE"
        exit 1
    }
    mv "${ovpn_files[0]}" "$OVPN_FILE" || {
        echo -e "${RED}Ошибка переименования файла${NC}" >&2
        log_action "ERROR" "Ошибка переименования ${ovpn_files[0]}" "$LOG_FILE"
        exit 1
    }
    rm -f "$archive_name" 2>/dev/null || true
    echo -e "${GREEN}Профиль загружен${NC}"
    log_action "INFO" "Профиль загружен: $OVPN_FILE" "$LOG_FILE"
}

# Проверка конфигурации
check_config() {
    echo -e "${YELLOW}Проверка конфигурации...${NC}"
    if [ ! -f "$OVPN_FILE" ]; then
        echo -e "${RED}Файл $OVPN_FILE не найден${NC}" >&2
        log_action "ERROR" "Файл $OVPN_FILE не найден" "$LOG_FILE"
        exit 1
    fi
    chmod 600 "$OVPN_FILE" || {
        echo -e "${RED}Ошибка изменения прав${NC}" >&2
        log_action "ERROR" "Ошибка изменения прав $OVPN_FILE" "$LOG_FILE"
        exit 1
    }
    echo -e "${GREEN}Конфигурация проверена${NC}"
    log_action "INFO" "Конфигурация проверена: $OVPN_FILE" "$LOG_FILE"
}

# Запуск VPN
start_vpn() {
    echo -e "${YELLOW}Запуск OpenVPN...${NC}"
    # Создание директории для логов
    mkdir -p "$(dirname "$LOG_FILE")" || {
        echo -e "${RED}Ошибка создания директории для логов${NC}" >&2
        log_action "ERROR" "Ошибка создания директории $(dirname "$LOG_FILE")" "$LOG_FILE"
        exit 1
    }
    # Запуск OpenVPN
    openvpn --config "$OVPN_FILE" --daemon --log "$LOG_FILE" --writepid "/var/run/openvpn-client.pid" || {
        echo -e "${RED}Ошибка запуска OpenVPN${NC}" >&2
        log_action "ERROR" "Ошибка запуска OpenVPN" "$LOG_FILE"
        exit 1
    }
    sleep 5
    if pgrep -F "/var/run/openvpn-client.pid" >/dev/null 2>&1; then
        local public_ip
        public_ip=$(curl -s ifconfig.me || echo "не удалось определить")
        echo -e "${GREEN}VPN подключен. IP: $public_ip${NC}"
        log_action "INFO" "VPN подключен, IP: $public_ip" "$LOG_FILE"
    else
        echo -e "${RED}Ошибка подключения:${NC}"
        tail -n 20 "$LOG_FILE" 2>/dev/null || echo -e "${RED}Лог-файл недоступен${NC}"
        log_action "ERROR" "Ошибка подключения VPN" "$LOG_FILE"
        exit 1
    fi
}

# Основной процесс
main() {
    clear
    echo -e "${GREEN}=== Установка OpenVPN клиента ===${NC}"
    read -r -p "${YELLOW}Введите URL профиля: ${NC}" url
    check_url "$url"
    cleanup
    download_profile "$url"
    check_config
    start_vpn
    echo -e "${GREEN}Установка OpenVPN клиента завершена${NC}"
    log_action "INFO" "Установка OpenVPN клиента завершена" "$LOG_FILE"
}

main