#!/bin/bash

source "$(dirname "$(realpath "$0")")/common.sh"

readonly VPN_DIR="/root/set-app-ports/vpn"
readonly OVPN_FILE="${VPN_DIR}/client.ovpn"
readonly LOG_FILE="/var/log/openvpn-client.log"

check_root
install_dependencies "openvpn curl wget unzip pgrep"

# Проверка URL
check_url() {
    local url="$1"
    [[ "$url" =~ ^https?:// ]] || {
        echo -e "${RED}Некорректный URL${NC}" >&2
        log_action "ERROR" "Некорректный URL: $url" "$LOG_FILE"
        exit 1
    }
}

# Очистка
cleanup() {
    echo -e "${YELLOW}Очистка...${NC}"
    pkill -SIGTERM openvpn 2>/dev/null || true
    sleep 1
    rm -rf "${VPN_DIR}"/* && mkdir -p "${VPN_DIR}" || {
        echo -e "${RED}Ошибка очистки директории${NC}" >&2
        log_action "ERROR" "Ошибка очистки $VPN_DIR" "$LOG_FILE"
        exit 1
    }
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
    [ ${#ovpn_files[@]} -eq 0 ] && {
        echo -e "${RED}Нет .ovpn файла в архиве${NC}" >&2
        log_action "ERROR" "Отсутствует .ovpn файл" "$LOG_FILE"
        exit 1
    }
    mv "${ovpn_files[0]}" "$OVPN_FILE" || {
        echo -e "${RED}Ошибка переименования файла${NC}" >&2
        log_action "ERROR" "Ошибка переименования ${ovpn_files[0]}" "$LOG_FILE"
        exit 1
    }
    log_action "INFO" "Профиль загружен" "$LOG_FILE"
}

# Проверка конфигурации
check_config() {
    echo -e "${YELLOW}Проверка конфигурации...${NC}"
    [ -f "$OVPN_FILE" ] || {
        echo -e "${RED}Файл $OVPN_FILE не найден${NC}" >&2
        log_action "ERROR" "Файл $OVPN_FILE не найден" "$LOG_FILE"
        exit 1
    }
    chmod 600 "$OVPN_FILE" || {
        echo -e "${RED}Ошибка изменения прав${NC}" >&2
        log_action "ERROR" "Ошибка изменения прав $OVPN_FILE" "$LOG_FILE"
        exit 1
    }
    log_action "INFO" "Конфигурация проверена" "$LOG_FILE"
}

# Запуск VPN
start_vpn() {
    echo -e "${YELLOW}Запуск OpenVPN...${NC}"
    openvpn --config "$OVPN_FILE" --daemon --log "$LOG_FILE" --writepid "/var/run/openvpn-client.pid" || {
        echo -e "${RED}Ошибка запуска OpenVPN${NC}" >&2
        log_action "ERROR" "Ошибка запуска OpenVPN" "$LOG_FILE"
        exit 1
    }
    sleep 5
    if pgrep -F "/var/run/openvpn-client.pid" >/dev/null 2>&1; then
        echo -e "${GREEN}VPN подключен. IP: $(curl -s ifconfig.me)${NC}"
        log_action "INFO" "VPN подключен" "$LOG_FILE"
    else
        echo -e "${RED}Ошибка подключения:${NC}"
        tail -n 20 "$LOG_FILE"
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
}

main