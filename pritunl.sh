#!/bin/bash

source "$(dirname "$(realpath "$0")")/common.sh"

readonly LOG_FILE="/var/log/pritunl_setup.log"

check_root
install_dependencies "lsb-release gpg curl apt systemctl"

# Проверка версии Ubuntu
check_ubuntu_version() {
    local version=$(lsb_release -rs)
    if [[ "$version" != "22.04" ]]; then
        echo -e "${RED}Скрипт оптимизирован для Ubuntu 22.04, текущая версия: $version${NC}" >&2
        log_action "ERROR" "Неподдерживаемая версия Ubuntu: $version" "$LOG_FILE"
        exit 1
    fi
}

# Добавление репозиториев
add_repositories() {
    local ubuntu_version=$(lsb_release -cs)
    echo -e "${YELLOW}Добавление репозиториев для $ubuntu_version...${NC}"
    cat > /etc/apt/sources.list.d/mongodb-org.list <<EOF
deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu $ubuntu_version/mongodb-org/8.0 multiverse
EOF
    cat > /etc/apt/sources.list.d/openvpn.list <<EOF
deb [ signed-by=/usr/share/keyrings/openvpn-repo.gpg ] https://build.openvpn.net/debian/openvpn/stable $ubuntu_version main
EOF
    cat > /etc/apt/sources.list.d/pritunl.list <<EOF
deb [ signed-by=/usr/share/keyrings/pritunl.gpg ] https://repo.pritunl.com/stable/apt $ubuntu_version main
EOF
    log_action "INFO" "Добавлены репозитории для $ubuntu_version" "$LOG_FILE"
}

# Добавление ключей
add_keys() {
    echo -e "${YELLOW}Добавление ключей...${NC}"
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg --yes || {
        echo -e "${RED}Ошибка добавления ключа MongoDB${NC}" >&2
        log_action "ERROR" "Ошибка добавления ключа MongoDB" "$LOG_FILE"
        exit 1
    }
    curl -fsSL https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor -o /usr/share/keyrings/openvpn-repo.gpg --yes || {
        echo -e "${RED}Ошибка добавления ключа OpenVPN${NC}" >&2
        log_action "ERROR" "Ошибка добавления ключа OpenVPN" "$LOG_FILE"
        exit 1
    }
    curl -fsSL https://raw.githubusercontent.com/pritunl/pgp/master/pritunl_repo_pub.asc | gpg --dearmor -o /usr/share/keyrings/pritunl.gpg --yes || {
        echo -e "${RED}Ошибка добавления ключа Pritunl${NC}" >&2
        log_action "ERROR" "Ошибка добавления ключа Pritunl" "$LOG_FILE"
        exit 1
    }
    log_action "INFO" "Ключи добавлены" "$LOG_FILE"
}

# Установка пакетов
install_packages() {
    echo -e "${YELLOW}Установка пакетов...${NC}"
    apt update -y && apt install -y pritunl openvpn mongodb-org wireguard wireguard-tools || {
        echo -e "${RED}Ошибка установки пакетов${NC}" >&2
        log_action "ERROR" "Ошибка установки пакетов" "$LOG_FILE"
        exit 1
    }
    log_action "INFO" "Пакеты установлены" "$LOG_FILE"
}

# Настройка сервисов
setup_services() {
    echo -e "${YELLOW}Настройка сервисов...${NC}"
    systemctl disable ufw >/dev/null 2>&1 || true
    for service in mongod pritunl; do
        systemctl enable "$service" && systemctl start "$service" || {
            echo -e "${RED}Ошибка запуска $service${NC}" >&2
            log_action "ERROR" "Ошибка запуска $service" "$LOG_FILE"
            exit 1
        }
        systemctl is-active --quiet "$service" && echo -e "${GREEN}$service запущен${NC}" || {
            echo -e "${RED}$service не работает. Проверьте логи: journalctl -u $service${NC}" >&2
            log_action "ERROR" "$service не работает" "$LOG_FILE"
            exit 1
        }
    done
    log_action "INFO" "Сервисы настроены" "$LOG_FILE"
}

# Основной процесс
main() {
    clear
    echo -e "${GREEN}=== Установка Pritunl VPN ===${NC}"
    check_ubuntu_version
    add_repositories
    add_keys
    install_packages
    setup_services
    echo -e "${RED}Ключ для активации Pritunl:${NC}"
    pritunl setup-key || {
        echo -e "${RED}Ошибка получения ключа${NC}" >&2
        log_action "ERROR" "Ошибка получения ключа Pritunl" "$LOG_FILE"
        exit 1
    }
    echo -e "${RED}Временные данные для входа:${NC}"
    pritunl default-password || {
        echo -e "${RED}Ошибка получения пароля${NC}" >&2
        log_action "ERROR" "Ошибка получения пароля Pritunl" "$LOG_FILE"
        exit 1
    }
    echo -e "${GREEN}Установка завершена${NC}"
    log_action "INFO" "Установка Pritunl завершена" "$LOG_FILE"
}

main