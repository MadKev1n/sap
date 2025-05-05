<p></p>
<div class="section">
    <h2>Содержание</h2>
    <ol>
        <li><a href="#description">Описание скриптов</a></li>
        <li><a href="#requirements">Требования</a></li>
        <li><a href="#installation">Установка</a></li>
        <li><a href="#usage">Использование</a>
            <ul>
                <li><a href="#sap">sap.sh</a></li>
                <li><a href="#pritunl">pritunl.sh</a></li>
                <li><a href="#openvpn">openvpn-client.sh</a></li>
            </ul>
        </li>
        <li><a href="#logging">Логирование</a></li>
        <li><a href="#troubleshooting">Возможные проблемы и решения</a></li>
        <li><a href="#examples">Примеры</a></li>
        <li><a href="#updating">Обновление</a></li>
        <li><a href="#license">Лицензия</a></li>
    </ol>
</div>
<div class="section" id="description">
    <h2>Описание скриптов</h2>
    <h3>1. <code>sap.sh</code></h3>
    <p>Скрипт для управления портами приложений и настройки NAT.</p>
    <ul>
        <li><strong>Функции:</strong>
            <ul>
                <li> алиаса <code>sap</code> в <code>~/.bashrc</code>.</li>
                <li>Изменение IP-адреса для перенаправления портов.</li>
                <li>Включение/выключение IP-маскарада.</li>
                <li>Добавление игр и портов из <code>default.txt</code> или вручную.</li>
                <li>Удаление портов.</li>
                <li>Применение правил <code>iptables</code>.</li>
                <li>Обновление скриптов через Git.</li>
                <li> Pritunl и OpenVPN-клиента.</li>
            </ul>
        </li>
        <li><strong>Файлы:</strong>
            <ul>
                <li><code>app_list.txt</code>: IP и список игр с портами (создаётся при первом запуске, если отсутствует).</li>
                <li><code>default.txt</code>: Предустановленные игры и порты (опционально).</li>
                <li><code>script_log.txt</code>: Лог действий.</li>
            </ul>
        </li>
    </ul>
    <h3>2. <code>common.sh</code></h3>
    <p>Скрипт с общими функциями, используемыми другими скриптами.</p>
    <ul>
        <li><strong>Функции:</strong>
            <ul>
                <li>Логирование действий с ротацией логов.</li>
                <li>Проверка прав root.</li>
                <li> зависимостей.</li>
                <li>Проверка соединения с интернетом.</li>
                <li>Обновление файлов через Git.</li>
            </ul>
        </li>
    </ul>
    <h3>3. <code>pritunl.sh</code></h3>
    <p>Скрипт для установки Pritunl VPN-сервера.</p>
    <ul>
        <li><strong>Функции:</strong>
            <ul>
                <li> зависимостей (<code>lsb-release</code>, <code>gnupg</code>).</li>
                <li>Добавление репозиториев MongoDB, OpenVPN и Pritunl.</li>
                <li> пакетов (<code>pritunl</code>, <code>mongodb-org</code>, <code>openvpn</code>, <code>wireguard</code>).</li>
                <li>Запуск сервисов <code>mongod</code> и <code>pritunl</code>.</li>
                <li>Вывод ключа и пароля.</li>
            </ul>
        </li>
        <li><strong>Файлы:</strong>
            <ul>
                <li><code>/var/log/pritunl_setup.log</code>: Лог установки.</li>
            </ul>
        </li>
    </ul>
    <h3>4. <code>openvpn-client.sh</code></h3>
    <p>Скрипт для настройки OpenVPN-клиента.</p>
    <ul>
        <li><strong>Функции:</strong>
            <ul>
                <li> зависимостей (<code>openvpn</code>, <code>curl</code>, <code>wget</code>, <code>unzip</code>).</li>
                <li>Загрузка <code>.ovpn</code> профиля из ZIP по URL.</li>
                <li>Очистка старых настроек.</li>
                <li>Запуск VPN.</li>
            </ul>
        </li>
        <li><strong>Файлы:</strong>
            <ul>
                <li><code>vpn/client.ovpn</code>: Конфигурация VPN.</li>
                <li><code>/var/log/openvpn-client.log</code>: Лог подключения.</li>
            </ul>
        </li>
    </ul>
</div>
<div class="section" id="requirements">
    <h2>Требования</h2>
    <ul>
        <li><strong>ОС:</strong> Ubuntu 22.04.</li>
        <li><strong>Права root:</strong> Все действия выполняются от имени суперпользователя.</li>
        <li><strong>Интернет:</strong> Для загрузки файлов и пакетов.</li>
        <li><strong>Зависимости:</strong>
            <ul>
                <li><code>sap.sh</code>: <code>iptables</code>, <code>wget</code>, <code>dos2unix</code>, <code>awk</code>, <code>ip</code>, <code>git</code>.</li>
                <li><code>common.sh</code>: <code>git</code>.</li>
                <li><code>pritunl.sh</code>: <code>lsb-release</code>, <code>gnupg</code>, <code>curl</code>, <code>systemctl</code>.</li>
                <li><code>openvpn-client.sh</code>: <code>openvpn</code>, <code>curl</code>, <code>wget</code>, <code>unzip</code>, <code>pgrep</code>.</li>
            </ul>
        </li>
    </ul>
</div>
<div class="section" id="installation">
    <h2>Установка</h2>
    <p>Скрипты устанавливаются через клонирование репозитория GitHub с проверками и настройкой алиаса <code>sap</code>. Выполните:</p>
    <pre class="language-markup"><code>sudo bash -c 'REPO_URL="https://github.com/MadKev1n/sap.git"; INSTALL_DIR="/root/set-app-ports"; error() { echo -e "\033[0;31mОшибка: $1\033[0m" >&2; exit 1; }; ping -c 1 8.8.8.8 &>/dev/null || error "Нет интернета"; [ "$(id -u)" -eq 0 ] || error "Требуются права root"; apt update && apt install -y git dos2unix || error "Не удалось установить зависимости"; rm -rf "$INSTALL_DIR" && mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR" || error "Не удалось создать директорию"; git clone "$REPO_URL" . || error "Не удалось клонировать репозиторий"; [ -f common.sh ] || error "Файл common.sh отсутствует"; dos2unix *.sh; chmod +x sap.sh pritunl.sh openvpn-client.sh common.sh; touch app_list.txt default.txt; chmod 644 app_list.txt default.txt; bash sap.sh || error "Не удалось запустить sap.sh"; echo -e "\033[0;32mУстановка завершена\033[0m"; exec bash'</code></pre>
    <h3>Что делает команда:</h3>
    <ol>
        <li>Проверяет наличие интернета (<code>ping 8.8.8.8</code>).</li>
        <li>Проверяет права root (<code>id -u</code>).</li>
        <li>Удаляет старую директорию <code>/root/set-app-ports</code>.</li>
        <li>Создаёт директорию <code>/root/set-app-ports</code>.</li>
        <li>Устанавливает <code>git</code> и <code>dos2unix</code> через <code>apt</code>.</li>
        <li>Проверяет наличие <code>git</code> и <code>dos2unix</code>.</li>
        <li>Создаёт SSH-ключ, если он отсутствует.</li>
        <li>Проверяет SSH-доступ к GitHub; если не настроен, использует HTTPS.</li>
        <li>Клонирует репозиторий <code>git@github.com:MadKev1n/sap.git</code> или <code>https://github.com/MadKev1n/sap.git</code>.</li>
        <li>Проверяет наличие <code>common.sh</code>.</li>
        <li>Конвертирует все скрипты (<code>*.sh</code>) в формат LF с помощью <code>dos2unix</code>.</li>
        <li>Устанавливает права на скрипты.</li>
        <li>Создаёт пустые файлы <code>app_list.txt</code> и <code>default.txt</code>, если они отсутствуют.</li>
        <li>Устанавливает права на <code>app_list.txt</code> и <code>default.txt</code>.</li>
        <li>Запускает <code>sap.sh</code> для настройки алиаса <code>sap</code>.</li>
        <li>Применяет <code>~/.bashrc</code> для активации алиаса.</li>
        <li>Выводит сообщение о завершении и инструкцию запустить <code>sap</code>.</li>
    </ol>
    <p><strong>Настройка SSH-доступа (рекомендуется):</strong></p>
    <ul>
        <li>Сгенерируйте SSH-ключ (если не создан автоматически):
            <pre><code>ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/id_ed25519</code></pre>
        </li>
        <li>Добавьте ключ в GitHub:
            <pre><code>cat ~/.ssh/id_ed25519.pub</code></pre>
            Скопируйте и вставьте в <a href="https://github.com/settings/keys">настройки GitHub</a>.
        </li>
        <li>Проверьте доступ:
            <pre><code>ssh -T git@github.com</code></pre>
        </li>
    </ul>
    <p><strong>Примечания:</strong></p>
    <ul>
        <li>Требуется интернет для клонирования и установки пакетов.</li>
        <li>Если SSH-доступ не настроен, команда использует HTTPS.</li>
        <li>Файлы <code>app_list.txt</code> и <code>default.txt</code> создаются автоматически, если отсутствуют в репозитории.</li>
        <li>Все скрипты конвертируются в формат LF для предотвращения ошибок.</li>
        <li>После установки используйте <code>sap</code>. Если алиас не работает, выполните <code>source ~/.bashrc</code> или откройте новую сессию.</li>
        <li>Проверьте наличие файлов: <code>ls -l /root/set-app-ports</code>.</li>
    </ul>
</div>
<div class="section" id="usage">
    <h2>Использование</h2>
    <h3 id="sap"><code>sap.sh</code></h3>
    <p><strong>Запуск:</strong> После установки используйте команду <code>sap</code>. Если алиас не работает, выполните <code>sudo bash /root/set-app-ports/sap.sh</code> или <code>source ~/.bashrc</code>.</p>
    <p><strong>Меню:</strong></p>
    <ol>
        <li><strong>Смена IP:</strong> Укажите IP для перенаправления (например, <code>192.168.1.100</code>).</li>
        <li><strong>Маскарад:</strong> <code>on</code> — включить, <code>off</code> — выключить.</li>
        <li><strong>Игра из default.txt:</strong> Выберите игру из предустановленного списка.</li>
        <li><strong>Новая игра:</strong> Введите название и описание.</li>
        <li><strong>Новый порт:</strong> Укажите <code>protocol port</code> (например, <code>TCP 25565</code>) и описание.</li>
        <li><strong>Удаление порта:</strong> Выберите из списка.</li>
        <li><strong>Информация:</strong> Просмотр <code>app_list.txt</code>.</li>
        <li><strong>Применить:</strong> Обновление <code>iptables</code>.</li>
        <li><strong>Выход:</strong> Завершение работы.</li>
        <li><strong>Обновление:</strong> Загрузка новых версий скриптов через Git.</li>
        <li><strong>11-12. Установка:</strong> Запуск <code>pritunl.sh</code> или <code>openvpn-client.sh</code>.</li>
    </ol>
    <p><strong>После запуска:</strong> Используйте <code>sap</code> для повторного вызова.</p>
    <h3 id="pritunl"><code>pritunl.sh</code></h3>
    <p><strong>Запуск:</strong> <code>cd /root/set-app-ports && ./pritunl.sh</code></p>
    <p><strong>Процесс:</strong></p>
    <ul>
        <li>Устанавливает Pritunl и зависимости.</li>
        <li>Выводит ключ активации и временный пароль.</li>
    </ul>
    <p><strong>Действия после:</strong></p>
    <ul>
        <li>Перейдите на <code>https://<ваш-IP>:9700</code>, введите ключ и пароль.</li>
        <li>Смените пароль в веб-интерфейсе.</li>
    </ul>
    <h3 id="openvpn"><code>openvpn-client.sh</code></h3>
    <p><strong>Запуск:</strong> <code>cd /root/set-app-ports && ./openvpn-client.sh</code></p>
    <p><strong>Процесс:</strong></p>
    <ul>
        <li>Запрашивает URL ZIP-архива с <code>.ovpn</code>.</li>
        <li>Устанавливает зависимости, загружает и запускает VPN.</li>
    </ul>
    <p><strong>Проверка:</strong> Выводит внешний IP после подключения.</p>
</div>
<div class="section" id="logging">
    <h2>Логирование</h2>
    <ul>
        <li><code>sap.sh</code>: <code>script_log.txt</code> (ротация при >1MB).</li>
        <li><code>pritunl.sh</code>: <code>/var/log/pritunl_setup.log</code> (ротация при >1MB).</li>
        <li><code>openvpn-client.sh</code>: <code>/var/log/openvpn-client.log</code> (ротация при >1MB).</li>
        <li><strong>Формат:</strong> <code>[Дата Время] - [Пользователь] - [Уровень] [Сообщение]</code>.</li>
    </ul>
</div>
<div class="section" id="troubleshooting">
    <h2>Возможные проблемы и решения</h2>
    <h3>Общие</h3>
    <ul>
        <li><strong>Нет интернета:</strong>
            <ul>
                <li>Проверьте: <code>ping 8.8.8.8</code>.</li>
                <li>Исправьте DNS: <code>echo "nameserver 8.8.8.8" > /etc/resolv.conf</code>.</li>
            </ul>
        </li>
        <li><strong>Ошибка клонирования:</strong>
            <ul>
                <li>Проверьте SSH: <code>ssh -T git@github.com</code>.</li>
                <li>Используйте HTTPS: <code>git clone https://github.com/MadKev1n/sap.git</code>.</li>
            </ul>
        </li>
        <li><strong>Ошибки из-за CRLF в скриптах:</strong>
            <ul>
                <li>Проверьте формат: <code>file sap.sh</code> (должно быть "ASCII text").</li>
                <li>Конвертируйте в LF: <code>dos2unix sap.sh common.sh pritunl.sh openvpn-client.sh</code>.</li>
            </ul>
        </li>
    </ul>
    <h3><code>sap.sh</code></h3>
    <ul>
        <li><strong>Алиас <code>sap</code> не работает:</strong>
            <ul>
                <li>Выполните: <code>source ~/.bashrc</code>.</li>
                <li>Проверьте <code>~/.bashrc</code>: <code>grep "alias sap" ~/.bashrc</code>.</li>
            </ul>
        </li>
        <li><strong>Правила <code>iptables</code> не применяются:</strong>
            <ul>
                <li>Проверьте формат <code>app_list.txt</code>: <code>cat app_list.txt</code>.</li>
                <li>Убедитесь, что IP валиден: <code>grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' app_list.txt</code>.</li>
            </ul>
        </li>
        <li><strong>Файл <code>common.sh</code> не найден:</strong>
            <ul>
                <li>Проверьте наличие: <code>ls /root/set-app-ports/common.sh</code>.</li>
                <li>Убедитесь, что <code>common.sh</code> есть в репозитории: <code>git ls-files common.sh</code>.</li>
            </ul>
        </li>
    </ul>
    <h3><code>pritunl.sh</code></h3>
    <ul>
        <li><strong>Ошибка установки:</strong>
            <ul>
                <li>Проверьте репозитории: <code>ls /etc/apt/sources.list.d/</code>.</li>
                <li>Обновите ключи: <code>apt-key list</code>.</li>
            </ul>
        </li>
        <li><strong>Сервисы не запускаются:</strong>
            <ul>
                <li>Логи: <code>journalctl -u mongod</code> или <code>journalctl -u pritunl</code>.</li>
                <li>Порты: <code>netstat -tuln | grep 27017</code> (MongoDB), <code>9700</code> (Pritunl).</li>
            </ul>
        </li>
    </ul>
    <h3><code>openvpn-client.sh</code></h3>
    <ul>
        <li><strong>Ошибка подключения:</strong>
            <ul>
                <li>Лог: <code>tail -n 20 /var/log/openvpn-client.log</code>.</li>
                <li>Проверьте <code>.ovpn</code>: <code>cat vpn/client.ovpn</code>.</li>
            </ul>
        </li>
    </ul>
</div>
<div class="section" id="examples">
    <h2>Примеры</h2>
    <h3>Настройка Minecraft</h3>
    <ol>
        <li>Выполните установочную команду.</li>
        <li>Запустите <code>sap</code>, выберите "1", введите <code>192.168.1.100</code>.</li>
        <li>Выберите "3", выберите Minecraft из <code>default.txt</code>.</li>
        <li>Выберите "8" для применения.</li>
        <li>Проверьте: <code>iptables -t nat -L PREROUTING</code>.</li>
    </ol>
    <h3>Установка Pritunl</h3>
    <ol>
        <li>Запустите <code>sap</code>, выберите "11".</li>
        <li>Скопируйте ключ и пароль.</li>
        <li>В браузере: <code>https://<ваш-IP>:9700</code>.</li>
    </ol>
    <h3>Подключение VPN</h3>
    <ol>
        <li>Запустите <code>sap</code>, выберите "12".</li>
        <li>Введите URL: <code>https://example.com/vpn-profile.zip</code>.</li>
        <li>Проверьте IP в выводе.</li>
    </ol>
</div>
<div class="section" id="updating">
    <h2>Обновление</h2>
    <ul>
        <li>Запустите <code>sap</code> и выберите пункт 10 для загрузки новых версий из GitHub.</li>
        <li>Или повторите установочную команду.</li>
    </ul>
</div>
<div class="section" id="license">
    <h2>Лицензия</h2>
    <p>Проект распространяется под <a href="LICENSE">MIT License</a>. Используйте, изменяйте и распространяйте код свободно с сохранением авторства.</p>
</div>
<hr>
<p><strong>Автор:</strong> Kevin XY</p>
<p><strong>Контакты:</strong> <a href="mailto:kevin_xy@blitztime.ru">kevin_xy@blitztime.ru</a></p>
<p><strong>Дата:</strong> Апрель 2025</p>
