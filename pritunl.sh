#!/bin/bash

source "$(dirname "$(realpath "$0")")/common.sh"

readonly LOG_FILE="/var/log/pritunl_setup.log"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5
readonly SERVICE_TIMEOUT=30
readonly MONGODB_PORT=27017
readonly PRITUNL_CONF="/etc/pritunl.conf"
readonly PRITUNL_DATA_DIR="/var/lib/pritunl"
readonly PRITUNL_JSON="$PRITUNL_DATA_DIR/pritunl.json"

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
    echo -e "${YELLOW}Обнаружена версия ОС: Ubuntu $version${NC}"
    log_action "INFO" "Обнаружена версия ОС: Ubuntu $version" "$LOG_FILE"
    if [[ "$version" != "22.04" && "$version" != "24.04" ]]; then
        echo -e "${RED}Скрипт поддерживает только Ubuntu 22.04 и 24.04, текущая версия: $version${NC}" >&2
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

# Проверка готовности сервиса
wait_for_service() {
    local service="$1"
    local timeout="$2"
    local elapsed=0
    local interval=2

    echo -e "${YELLOW}Ожидание готовности сервиса $service...${NC}"
    while [ $elapsed -lt "$timeout" ]; do
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}Сервис $service активен${NC}"
            log_action "INFO" "Сервис $service активен" "$LOG_FILE"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    echo -e "${RED}Сервис $service не запустился за $timeout секунд${NC}" >&2
    log_action "ERROR" "Сервис $service не запустился за $timeout секунд" "$LOG_FILE"
    exit 1
}

# Проверка доступности MongoDB
check_mongodb() {
    echo -e "${YELLOW}Проверка доступности MongoDB...${NC}"
    local timeout=30
    local elapsed=0
    local interval=2

    while [ $elapsed -lt "$timeout" ]; do
        if nc -z localhost $MONGODB_PORT >/dev/null 2>&1; then
            echo -e "${GREEN}MongoDB доступен на порту $MONGODB_PORT${NC}"
            log_action "INFO" "MongoDB доступен на порту $MONGODB_PORT" "$LOG_FILE"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    echo -e "${RED}MongoDB недоступен на порту $MONGODB_PORT после $timeout секунд${NC}" >&2
    log_action "ERROR" "MongoDB недоступен на порту $MONGODB_PORT" "$LOG_FILE"
    exit 1
}

# Исправление конфигурации Pritunl
fix_pritunl_conf() {
    echo -e "${YELLOW}Проверка и исправление конфигурации Pritunl...${NC}"
    if [ -f "$PRITUNL_CONF" ]; then
        if grep -q '^mongodb_uri = ""' "$PRITUNL_CONF" || ! grep -q '^mongodb_uri' "$PRITUNL_CONF"; then
            echo -e "${YELLOW}Установка mongodb_uri в $PRITUNL_CONF...${NC}"
            sed -i '/^mongodb_uri/d' "$PRITUNL_CONF"  # Удаляем старую строку, если есть
            echo 'mongodb_uri = "mongodb://localhost:27017/pritunl"' >> "$PRITUNL_CONF"
            log_action "INFO" "Добавлен mongodb_uri в $PRITUNL_CONF" "$LOG_FILE"
        else
            echo -e "${GREEN}mongodb_uri уже настроен${NC}"
            log_action "INFO" "mongodb_uri уже настроен в $PRITUNL_CONF" "$LOG_FILE"
        fi
    else
        echo -e "${RED}Файл конфигурации $PRITUNL_CONF не найден${NC}" >&2
        log_action "ERROR" "Файл конфигурации $PRITUNL_CONF не найден" "$LOG_FILE"
        exit 1
    fi
}

# Проверка и очистка конфигурационных файлов Pritunl
clean_pritunl_config() {
    echo -e "${YELLOW}Проверка и очистка конфигурационных файлов Pritunl...${NC}"
    if [ -d "$PRITUNL_DATA_DIR" ]; then
        # Создаём резервную копию
        local backup_dir="$PRITUNL_DATA_DIR/backup_$(date +%F_%H-%M-%S)"
        echo -e "${YELLOW}Создание резервной копии конфигурации в $backup_dir...${NC}"
        mkdir -p "$backup_dir"
        cp -r "$PRITUNL_DATA_DIR"/*.json "$backup_dir" 2>/dev/null || true
        log_action "INFO" "Создана резервная копия конфигурации в $backup_dir" "$LOG_FILE"

        # Проверяем JSON-файл
        if [ -f "$PRITUNL_JSON" ]; then
            if ! python3 -m json.tool "$PRITUNL_JSON" >/dev/null 2>&1; then
                echo -e "${RED}Обнаружен некорректный JSON в $PRITUNL_JSON, удаление...${NC}"
                log_action "WARNING" "Некорректный JSON в $PRITUNL_JSON, файл удалён" "$LOG_FILE"
                rm -f "$PRITUNL_JSON"
            else
                echo -e "${GREEN}JSON в $PRITUNL_JSON корректен${NC}"
                log_action "INFO" "JSON в $PRITUNL_JSON корректен" "$LOG_FILE"
            fi
        fi
    else
        echo -e "${YELLOW}Директория $PRITUNL_DATA_DIR не существует, пропускаем...${NC}"
        log_action "INFO" "Директория $PRITUNL_DATA_DIR не существует" "$LOG_FILE"
    fi
}

# Настройка сервисов
setup_services() {
    echo -e "${YELLOW}Настройка сервисов...${NC}"
    systemctl disable ufw >/dev/null 2>&1 || true
    for service in mongod pritunl; do
        if ! systemctl enable "$service" || ! systemctl start "$service"; then
            echo -e "${RED}Ошибка запуска $service${NC}" >&2
            log_action "ERROR" "Ошибка запуска $service" "$LOG_FILE"
            exit 1
        fi
        wait_for_service "$service" $SERVICE_TIMEOUT
    done
    log_action "INFO" "Сервисы настроены" "$LOG_FILE"
}

# Выполнение команды с повторными попытками
run_with_retry() {
    local command="$1"
    local description="$2"
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        echo -e "${YELLOW}Попытка $attempt: $description...${NC}"
        if $command; then
            log_action "INFO" "$description успешно выполнено" "$LOG_FILE"
            return 0
        else
            echo -e "${RED}Ошибка: $description (попытка $attempt/${MAX_RETRIES})${NC}" >&2
            log_action "ERROR" "Ошибка: $description (попытка $attempt)" "$LOG_FILE"
        fi
        attempt=$((attempt + 1))
        sleep $RETRY_DELAY
    done
    echo -e "${RED}Не удалось выполнить $description после $MAX_RETRIES попыток${NC}" >&2
    log_action "ERROR" "Не удалось выполнить $description" "$LOG_FILE"
    exit 1
}

# Основной процесс
main() {
    clear
    echo -e "${GREEN}=== Установка Pritunl VPN ===${NC}"
    check_root
    install_dependencies "lsb-release gpg curl apt systemctl netcat-traditional python3"
    check_network
    check_ubuntu_version
    add_repositories
    add_keys
    install_packages
    setup_services
    fix_pritunl_conf
    check_mongodb
    clean_pritunl_config
    echo -e "${YELLOW}Ожидание полной инициализации сервисов...${NC}"
    sleep 5  # Дополнительная задержка для стабилизации
    echo -e "${RED}Ключ для активации Pritunl:${NC}"
    run_with_retry "pritunl setup-key" "Получение ключа Pritunl"
    # Перезапуск Pritunl для применения изменений
    echo -e "${YELLOW}Перезапуск сервиса Pritunl...${NC}"
    systemctl restart pritunl
    wait_for_service "pritunl" $SERVICE_TIMEOUT
    echo -e "${GREEN}Установка завершена${NC}"
    log_action "INFO" "Установка Pritunl завершена" "$LOG_FILE"
}

main
