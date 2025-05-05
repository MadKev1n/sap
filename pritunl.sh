#!/bin/bash

source "$(dirname "$(realpath "$0")")/common.sh"

readonly LOG_FILE="/var/log/pritunl_setup.log"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5
readonly SERVICE_WAIT_TIMEOUT=30  # Максимальное время ожидания инициализации сервисов (секунды)

# Проверка сетевой доступности
check_network() {
    echo -e "${YELLOW}Проверка сетевой доступности...${NC}"
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${RED}Сеть недоступна. Проверьте подключение к интернету.${NC}" >&2
        log_action "ERROR" "Сеть недоступна" "$LOG_FILE"
        exit 1
    fi
    log_action "INFO" "Сеть доступна" "$LOG_FILE"
}

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
    mkdir -p /usr/share/keyrings
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

# Функция загрузки ключей с повторными попытками
fetch_key_with_retry() {
    local url="$1"
    local output="$2"
    local name="$3"
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        echo -e "${YELLOW}Попытка $attempt: загрузка ключа $name...${NC}"
        if curl -fsSL --connect-timeout 10 --retry 2 "$url" | gpg --dearmor -o "$output" --yes; then
            # Проверка, что файл не пустой
            if [ -s "$output" ]; then
                log_action "INFO" "Ключ $name успешно загружен" "$LOG_FILE"
                return 0
            else
                echo -e "${RED}Ключ $name пустой или поврежден${NC}" >&2
                log_action "ERROR" "Ключ $name пустой или поврежден" "$LOG_FILE"
            fi
        else
            echo -e "${RED}Ошибка загрузки ключа $name (попытка $attempt/${MAX_RETRIES})${NC}" >&2
            log_action "ERROR" "Ошибка загрузки ключа $name (попытка $attempt)" "$LOG_FILE"
        fi
        attempt=$((attempt + 1))
        sleep $RETRY_DELAY
    done
    echo -e "${RED}Не удалось загрузить ключ $name после $MAX_RETRIES попыток${NC}" >&2
    log_action "ERROR" "Не удалось загрузить ключ $name" "$LOG_FILE"
    exit 1
}

# Добавление ключей
add_keys() {
    echo -e "${YELLOW}Добавление ключей...${NC}"
    fetch_key_with_retry "https://www.mongodb.org/static/pgp/server-8.0.asc" "/usr/share/keyrings/mongodb-server-8.0.gpg" "MongoDB"
    fetch_key_with_retry "https://swupdate.openvpn.net/repos/repo-public.gpg" "/usr/share/keyrings/openvpn-repo.gpg" "OpenVPN"
    fetch_key_with_retry "https://raw.githubusercontent.com/pritunl/pgp/master/pritunl_repo_pub.asc" "/usr/share/keyrings/pritunl.gpg" "Pritunl"
    log_action "INFO" "Все ключи добавлены" "$LOG_FILE"
}

# Установка пакетов
install_packages() {
    echo -e "${YELLOW}Установка пакетов...${NC}"
    if ! apt update -y; then
        echo -e "${RED}Ошибка обновления списка пакетов${NC}" >&2
        log_action "ERROR" "Ошибка обновления списка пакетов" "$LOG_FILE"
        exit 1
    fi
    if ! apt install -y pritunl openvpn mongodb-org wireguard wireguard-tools; then
        echo -e "${RED}Ошибка установки пакетов${NC}" >&2
        log_action "ERROR" "Ошибка установки пакетов" "$LOG_FILE"
        exit 1
    fi
    log_action "INFO" "Пакеты установлены" "$LOG_FILE"
}

# Ожидание инициализации сервиса
wait_for_service() {
    local service_name="$1"
    local timeout="$SERVICE_WAIT_TIMEOUT"
    local elapsed=0
    
    echo -e "${YELLOW}Ожидание инициализации $service_name...${NC}"
    
    while [ $elapsed -lt $timeout ]; do
        if systemctl is-active --quiet "$service_name"; then
            # Дополнительная проверка для MongoDB
            if [ "$service_name" == "mongod" ]; then
                if mongo --eval "db.runCommand({ping:1})" >/dev/null 2>&1; then
                    echo -e "${GREEN}$service_name готов к работе${NC}"
                    log_action "INFO" "$service_name успешно инициализирован" "$LOG_FILE"
                    return 0
                fi
            else
                echo -e "${GREEN}$service_name готов к работе${NC}"
                log_action "INFO" "$service_name успешно инициализирован" "$LOG_FILE"
                return 0
            fi
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -e "${YELLOW}Прошло $elapsed секунд...${NC}"
    done
    
    echo -e "${RED}Таймаут ожидания $service_name${NC}" >&2
    log_action "ERROR" "Таймаут ожидания $service_name" "$LOG_FILE"
    return 1
}

# Настройка сервисов
setup_services() {
    echo -e "${YELLOW}Настройка сервисов...${NC}"
    systemctl disable ufw >/dev/null 2>&1 || true
    
    for service in mongod pritunl; do
        if ! systemctl enable "$service"; then
            echo -e "${RED}Ошибка включения $service${NC}" >&2
            log_action "ERROR" "Ошибка включения $service" "$LOG_FILE"
            exit 1
        fi
        
        if ! systemctl restart "$service"; then
            echo -e "${RED}Ошибка перезапуска $service${NC}" >&2
            log_action "ERROR" "Ошибка перезапуска $service" "$LOG_FILE"
            exit 1
        fi
        
        if ! wait_for_service "$service"; then
            echo -e "${RED}$service не инициализировался за отведенное время${NC}" >&2
            log_action "ERROR" "$service не инициализировался" "$LOG_FILE"
            exit 1
        fi
    done
    
    log_action "INFO" "Сервисы настроены" "$LOG_FILE"
}

# Получение данных Pritunl
get_pritunl_data() {
    echo -e "${YELLOW}Получение данных Pritunl...${NC}"
    
    # Добавляем небольшую задержку перед получением данных
    sleep 5
    
    local attempt=1
    local setup_key=""
    local default_password=""
    
    while [ $attempt -le $MAX_RETRIES ]; do
        echo -e "${YELLOW}Попытка $attempt получить данные...${NC}"
        
        # Получаем ключ установки
        if setup_key=$(pritunl setup-key 2>/dev/null); then
            # Получаем пароль по умолчанию
            if default_password=$(pritunl default-password 2>/dev/null); then
                echo -e "${GREEN}Данные успешно получены${NC}"
                echo -e "${RED}Ключ для активации Pritunl:${NC}"
                echo "$setup_key"
                echo -e "${RED}Временные данные для входа:${NC}"
                echo "$default_password"
                log_action "INFO" "Данные Pritunl успешно получены" "$LOG_FILE"
                return 0
            fi
        fi
        
        echo -e "${YELLOW}Ошибка получения данных (попытка $attempt/${MAX_RETRIES})${NC}"
        sleep $RETRY_DELAY
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}Не удалось получить данные Pritunl после $MAX_RETRIES попыток${NC}" >&2
    echo -e "${YELLOW}Вы можете попробовать получить данные вручную после перезагрузки:${NC}"
    echo -e "1. Ключ установки: ${GREEN}pritunl setup-key${NC}"
    echo -e "2. Пароль по умолчанию: ${GREEN}pritunl default-password${NC}"
    log_action "ERROR" "Не удалось получить данные Pritunl" "$LOG_FILE"
    return 1
}

# Основной процесс
main() {
    clear
    echo -e "${GREEN}=== Установка Pritunl VPN ===${NC}"
    check_root
    install_dependencies "lsb-release gpg curl apt systemctl"
    check_network
    check_ubuntu_version
    add_repositories
    add_keys
    install_packages
    setup_services
    get_pritunl_data
    echo -e "${GREEN}Установка завершена${NC}"
    echo -e "${YELLOW}Доступ к веб-интерфейсу: https://<ваш_IP>${NC}"
    log_action "INFO" "Установка Pritunl завершена" "$LOG_FILE"
}

main
