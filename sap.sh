#!/bin/bash

# Подключение общих функций
source "$(dirname "$(realpath "$0")")/common.sh"

# Конфигурация
readonly SCRIPT_DIR="$(dirname "$(realpath "$0")")"
readonly APP_LIST_FILE="$SCRIPT_DIR/app_list.txt"
readonly DEFAULT_FILE="$SCRIPT_DIR/default.txt"
readonly LOG_FILE="$SCRIPT_DIR/script_log.txt"
readonly REPO_URL="git@github.com:MadKev1n/sap.git" # SSH-URL для безопасности
readonly REPO_BRANCH="main"

# Проверка прав и зависимостей
check_root
install_dependencies "iptables wget dos2unix awk ip git"

# Проверка и создание файлов
check_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo -e "${YELLOW}Файл $file не найден. Создание...${NC}"
        touch "$file" || {
            echo -e "${RED}Ошибка создания $file${NC}" >&2
            log_action "ERROR" "Ошибка создания $file" "$LOG_FILE"
            exit 1
        }
        log_action "INFO" "Создан файл $file" "$LOG_FILE"
    else
        echo -e "${GREEN}Файл $file найден.${NC}"
    fi
}

# Установка алиаса
setup_alias() {
    if ! grep -q "alias sap=" ~/.bashrc; then
        echo -e "${YELLOW}Добавление алиаса 'sap'...${NC}"
        echo "alias sap='bash $SCRIPT_DIR/sap.sh'" >> ~/.bashrc
        source ~/.bashrc 2>/dev/null || echo -e "${YELLOW}Выполните 'source ~/.bashrc' вручную${NC}"
        log_action "INFO" "Добавлен алиас sap" "$LOG_FILE"
    else
        echo -e "${GREEN}Алиас 'sap' уже существует${NC}"
    fi
}

# Включение/выключение маскарада
toggle_masquerade() {
    local interface=$(ip -o -4 route show to default | awk '{print $5}')
    [ -z "$interface" ] && {
        echo -e "${RED}Не найден сетевой интерфейс${NC}" >&2
        log_action "ERROR" "Не найден сетевой интерфейс" "$LOG_FILE"
        return 1
    }
    local action="$1"
    case "$action" in
        on)
            if ! iptables -t nat -C POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null; then
                iptables -t nat -A POSTROUTING -o "$interface" -j MASQUERADE || {
                    echo -e "${RED}Ошибка включения маскарада${NC}" >&2
                    log_action "ERROR" "Ошибка включения маскарада" "$LOG_FILE"
                    return 1
                }
                echo -e "${GREEN}Маскарад включен на $interface${NC}"
                log_action "INFO" "Маскарад включен на $interface" "$LOG_FILE"
            else
                echo -e "${GREEN}Маскарад уже включен${NC}"
            fi
            ;;
        off)
            if iptables -t nat -C POSTROUTING -o "$interface" -j MASQUERADE 2>/dev/null; then
                iptables -t nat -D POSTROUTING -o "$interface" -j MASQUERADE || {
                    echo -e "${RED}Ошибка выключения маскарада${NC}" >&2
                    log_action "ERROR" "Ошибка выключения маскарада" "$LOG_FILE"
                    return 1
                }
                echo -e "${GREEN}Маскарад выключен${NC}"
                log_action "INFO" "Маскарад выключен на $interface" "$LOG_FILE"
            else
                echo -e "${GREEN}Маскарад уже выключен${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Используйте 'on' или 'off'${NC}" >&2
            ;;
    esac
}

# Смена IP-адреса
change_ip() {
    read -r -p "Введите новый IP: " new_ip
    if [[ "$new_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [ ! -s "$APP_LIST_FILE" ]; then
            echo "$new_ip, IP-адрес сервера" > "$APP_LIST_FILE"
        else
            sed -i "1s/.*/$new_ip, IP-адрес сервера/" "$APP_LIST_FILE" || {
                echo -e "${RED}Ошибка записи IP${NC}" >&2
                log_action "ERROR" "Ошибка записи IP $new_ip" "$LOG_FILE"
                return 1
            }
        fi
        echo -e "${GREEN}IP обновлен: $new_ip${NC}"
        log_action "INFO" "IP обновлен: $new_ip" "$LOG_FILE"
    else
        echo -e "${RED}Некорректный IP${NC}" >&2
    fi
}

# Добавление игры из default.txt
add_game_from_default() {
    echo -e "${YELLOW}Доступные игры из $DEFAULT_FILE:${NC}"
    mapfile -t games < <(cut -d',' -f1 "$DEFAULT_FILE" | sort -u)
    if [ ${#games[@]} -eq 0 ]; then
        echo -e "${RED}Файл $DEFAULT_FILE пуст или не содержит игр${NC}" >&2
        return 1
    fi
    for i in "${!games[@]}"; do
        echo "$((i+1))) ${games[$i]}"
    done
    read -r -p "Выберите номер игры: " game_choice
    if [[ "$game_choice" =~ ^[0-9]+$ ]] && [ "$game_choice" -ge 1 ] && [ "$game_choice" -le "${#games[@]}" ]; then
        selected_game="${games[$((game_choice-1))]}"
        game_ports=$(grep "^$selected_game," "$DEFAULT_FILE")
        if ! grep -q "^$selected_game," "$APP_LIST_FILE"; then
            echo "$selected_game,\"$selected_game\"" >> "$APP_LIST_FILE"
            echo -e "${GREEN}Добавлена игра '$selected_game' в $APP_LIST_FILE${NC}"
        fi
        ports_added=0
        while IFS= read -r line; do
            port=$(echo "$line" | cut -d',' -f2 | tr -d '[:space:]')
            description=$(echo "$line" | cut -d',' -f3 | tr -d '"')
            if [[ -n "$port" ]]; then
                protocol_port=$(echo "$port" | sed 's/\([A-Z]*\)\([0-9]\)/\1 \2/')
                if ! grep -q "^$selected_game,$protocol_port," "$APP_LIST_FILE"; then
                    echo "$selected_game,$protocol_port,\"$description\"" >> "$APP_LIST_FILE"
                    ((ports_added++))
                    echo -e "${GREEN}Добавлен порт '$protocol_port' для '$selected_game'${NC}"
                fi
            fi
        done <<< "$game_ports"
        if [ $ports_added -gt 0 ]; then
            echo -e "${GREEN}Добавлено $ports_added портов для '$selected_game'${NC}"
            log_action "INFO" "Добавлено $ports_added портов для '$selected_game'" "$LOG_FILE"
        else
            echo -e "${YELLOW}Новых портов для '$selected_game' не добавлено${NC}"
        fi
    else
        echo -e "${RED}Некорректный выбор игры${NC}" >&2
    fi
}

# Добавление новой игры
add_game() {
    read -r -p "Введите название игры: " new_game
    if grep -q "^$new_game," "$APP_LIST_FILE"; then
        echo -e "${RED}Игра '$new_game' уже существует${NC}" >&2
        return 1
    fi
    read -r -p "Введите описание для '$new_game': " description
    echo "$new_game,\"$description\"" >> "$APP_LIST_FILE" || {
        echo -e "${RED}Ошибка добавления игры${NC}" >&2
        log_action "ERROR" "Ошибка добавления игры $new_game" "$LOG_FILE"
        return 1
    }
    echo -e "${GREEN}Игра '$new_game' добавлена: \"$description\"${NC}"
    log_action "INFO" "Добавлена игра: $new_game (\"$description\")" "$LOG_FILE"
}

# Добавление порта для игры
add_port() {
    echo -e "${YELLOW}Список игр из $APP_LIST_FILE:${NC}"
    mapfile -t games < <(tail -n +2 "$APP_LIST_FILE" | grep -v '^$' | cut -d',' -f1 | sort -u)
    if [ ${#games[@]} -eq 0 ]; then
        echo -e "${RED}Нет игр в $APP_LIST_FILE${NC}" >&2
        return 1
    fi
    for i in "${!games[@]}"; do
        echo "$((i+1))) ${games[$i]}"
    done
    read -r -p "Выберите номер игры: " game_choice
    if [[ "$game_choice" =~ ^[0-9]+$ ]] && [ "$game_choice" -ge 1 ] && [ "$game_choice" -le "${#games[@]}" ]; then
        selected_game="${games[$((game_choice-1))]}"
        read -r -p "Введите протокол и порт (например, TCP 25565): " port
        protocol=$(echo "$port" | awk '{print $1}')
        port_number=$(echo "$port" | awk '{print $2}')
        if [[ "$protocol" =~ ^(TCP|UDP)$ ]] && [[ "$port_number" =~ ^[0-9]+$ ]] && [ "$port_number" -ge 1 ] && [ "$port_number" -le 65535 ]; then
            read -r -p "Введите описание порта: " description
            if grep -q "^$selected_game,$port," "$APP_LIST_FILE"; then
                echo -e "${RED}Порт $port уже добавлен для '$selected_game'${NC}" >&2
            else
                echo "$selected_game,$port,\"$description\"" >> "$APP_LIST_FILE" || {
                    echo -e "${RED}Ошибка добавления порта${NC}" >&2
                    log_action "ERROR" "Ошибка добавления порта $port для $selected_game" "$LOG_FILE"
                    return 1
                }
                echo -e "${GREEN}Порт $port добавлен для '$selected_game': \"$description\"${NC}"
                log_action "INFO" "Добавлен порт $port для '$selected_game': \"$description\"" "$LOG_FILE"
            fi
        else
            echo -e "${RED}Некорректный протокол или порт${NC}" >&2
        fi
    else
        echo -e "${RED}Некорректный выбор игры${NC}" >&2
    fi
}

# Удаление порта
remove_port() {
    echo -e "${YELLOW}Список портов из $APP_LIST_FILE:${NC}"
    mapfile -t ports < <(grep -E '^[^,]+,[^,]+,' "$APP_LIST_FILE")
    if [ ${#ports[@]} -eq 0 ]; then
        echo -e "${RED}Нет портов для удаления${NC}" >&2
        return 1
    fi
    for i in "${!ports[@]}"; do
        game_port_info=$(echo "${ports[$i]}" | cut -d',' -f1,2)
        echo "$((i+1))) $game_port_info"
    done
    read -r -p "Выберите номер порта для удаления: " port_choice
    if [[ "$port_choice" =~ ^[0-9]+$ ]] && [ "$port_choice" -ge 1 ] && [ "$port_choice" -le "${#ports[@]}" ]; then
        selected_port="${ports[$((port_choice-1))]}"
        grep -v "^$selected_port$" "$APP_LIST_FILE" > temp_file && mv temp_file "$APP_LIST_FILE" || {
            echo -e "${RED}Ошибка удаления порта${NC}" >&2
            log_action "ERROR" "Ошибка удаления порта $selected_port" "$LOG_FILE"
            return 1
        }
        echo -e "${GREEN}Порт '$selected_port' удален${NC}"
        log_action "INFO" "Удален порт '$selected_port'" "$LOG_FILE"
    else
        echo -e "${RED}Некорректный выбор порта${NC}" >&2
    fi
}

# Вывод содержимого app_list
show_app_list() {
    echo -e "${YELLOW}Содержимое файла $APP_LIST_FILE:${NC}"
    if [[ ! -s "$APP_LIST_FILE" ]]; then
        echo -e "${RED}Файл $APP_LIST_FILE пуст${NC}" >&2
        return 1
    fi
    current_game=""
    while IFS= read -r line; do
        game=$(echo "$line" | cut -d',' -f1)
        port=$(echo "$line" | cut -d',' -f2 | cut -d' ' -f2-)
        description=$(echo "$line" | cut -d',' -f3 | tr -d '"')
        if [[ "$game" != "$current_game" ]]; then
            [ -n "$current_game" ] && echo -e "${NC}"
            echo -e "${GREEN}$game:${NC}"
            current_game="$game"
        fi
        [ -n "$port" ] && echo -e "    - ${YELLOW}$port:${NC} $description"
    done < "$APP_LIST_FILE"
    echo -e "${NC}"
    log_action "INFO" "Выведено содержимое $APP_LIST_FILE" "$LOG_FILE"
}

# Применение правил iptables
apply_iptables() {
    local ip_address=$(head -n 1 "$APP_LIST_FILE" | cut -d',' -f1)
    if [ -z "$ip_address" ]; then
        echo -e "${RED}IP-адрес не задан${NC}" >&2
        return 1
    fi
    echo -e "${YELLOW}Очистка старых правил DNAT...${NC}"
    iptables -t nat -F PREROUTING || {
        echo -e "${RED}Ошибка очистки PREROUTING${NC}" >&2
        log_action "ERROR" "Ошибка очистки PREROUTING" "$LOG_FILE"
        return 1
    }
    echo -e "${YELLOW}Добавление новых правил...${NC}"
    while IFS= read -r line; do
        game=$(echo "$line" | cut -d',' -f1)
        port=$(echo "$line" | cut -d',' -f2 | awk '{print $2}')
        protocol=$(echo "$line" | cut -d',' -f2 | awk '{print $1}')
        if [[ "$protocol" =~ ^(TCP|UDP)$ ]]; then
            iptables -t nat -A PREROUTING -p "$protocol" --dport "$port" -j DNAT --to-destination "$ip_address:$port" || {
                echo -e "${RED}Ошибка добавления DNAT для $protocol $port${NC}" >&2
                log_action "ERROR" "Ошибка DNAT для $protocol $port" "$LOG_FILE"
                continue
            }
            iptables -A FORWARD -p "$protocol" --dport "$port" -d "$ip_address" -j ACCEPT || {
                echo -e "${RED}Ошибка добавления FORWARD для $protocol $port${NC}" >&2
                log_action "ERROR" "Ошибка FORWARD для $protocol $port" "$LOG_FILE"
                continue
            }
            echo -e "${GREEN}Добавлено правило: $protocol $port -> $ip_address:$port${NC}"
            log_action "INFO" "Добавлено правило: $protocol $port -> $ip_address:$port" "$LOG_FILE"
        fi
    done < <(grep -E '^[^,]+,[^,]+,' "$APP_LIST_FILE")
    install_dependencies "iptables-persistent"
    iptables-save > /etc/iptables/rules.v4 || {
        echo -e "${YELLOW}Не удалось сохранить правила${NC}" >&2
        log_action "WARNING" "Не удалось сохранить правила в /etc/iptables/rules.v4" "$LOG_FILE"
    }
    echo -e "${GREEN}Правила применены${NC}"
    log_action "INFO" "Применены правила iptables" "$LOG_FILE"
}

# Основное меню
main_menu() {
    while true; do
        clear
        echo -e "${YELLOW}=== Меню SAP ===${NC}"
        echo "1) Смена IP-адреса"
        echo "2) Включить/выключить маскарад"
        echo "3) Добавить игру из default.txt"
        echo "4) Добавить игру"
        echo "5) Добавить порт для игры"
        echo "6) Удалить порт"
        echo "7) Показать app_list"
        echo "8) Применить правила iptables"
        echo "9) Выход"
        echo "10) Обновить скрипты через Git"
        echo "11) Установить Pritunl"
        echo "12) Установить VPN-клиент"
        read -r -p "Выберите действие: " choice

        case "$choice" in
            1)
                change_ip
                ;;
            2)
                read -r -p "Включить (on) или выключить (off) маскарад: " action
                toggle_masquerade "$action"
                ;;
            3)
                add_game_from_default
                ;;
            4)
                add_game
                ;;
            5)
                add_port
                ;;
            6)
                remove_port
                ;;
            7)
                show_app_list
                ;;
            8)
                apply_iptables
                ;;
            9)
                echo -e "${GREEN}Выход${NC}"
                log_action "INFO" "Выход из программы" "$LOG_FILE"
                exit 0
                ;;
            10)
                update_from_git "$REPO_URL" "$REPO_BRANCH" "$SCRIPT_DIR" "$LOG_FILE"
                echo -e "${YELLOW}Перезапуск скрипта...${NC}"
                exec bash "$SCRIPT_DIR/sap.sh"
                ;;
            11)
                [ -f "$SCRIPT_DIR/pritunl.sh" ] && {
                    chmod +x "$SCRIPT_DIR/pritunl.sh" 2>/dev/null
                    dos2unix "$SCRIPT_DIR/pritunl.sh" 2>/dev/null
                    bash "$SCRIPT_DIR/pritunl.sh" || {
                        echo -e "${RED}Ошибка запуска pritunl.sh${NC}" >&2
                        log_action "ERROR" "Ошибка запуска pritunl.sh" "$LOG_FILE"
                    }
                } || {
                    echo -e "${RED}pritunl.sh не найден${NC}" >&2
                    log_action "ERROR" "pritunl.sh не найден" "$LOG_FILE"
                }
                ;;
            12)
                [ -f "$SCRIPT_DIR/openvpn-client.sh" ] && {
                    chmod +x "$SCRIPT_DIR/openvpn-client.sh" 2>/dev/null
                    dos2unix "$SCRIPT_DIR/openvpn-client.sh" 2>/dev/null
                    bash "$SCRIPT_DIR/openvpn-client.sh" || {
                        echo -e "${RED}Ошибка запуска openvpn-client.sh${NC}" >&2
                        log_action "ERROR" "Ошибка запуска openvpn-client.sh" "$LOG_FILE"
                    }
                } || {
                    echo -e "${RED}openvpn-client.sh не найден${NC}" >&2
                    log_action "ERROR" "openvpn-client.sh не найден" "$LOG_FILE"
                }
                ;;
            *)
                echo -e "${RED}Неверный выбор${NC}" >&2
                ;;
        esac
        read -r -p "Нажмите Enter..."
    done
}

# Инициализация
check_file "$APP_LIST_FILE"
check_file "$DEFAULT_FILE"
setup_alias
main_menu