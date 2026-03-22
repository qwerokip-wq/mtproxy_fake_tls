#!/bin/bash

# --- КОНФИГУРАЦИЯ ---
ALIAS_NAME="mtproxy"
BINARY_PATH="/usr/local/bin/mtproxy"
CONFIG_DIR="/etc/mtproxy"

# --- ЦВЕТА ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- СИСТЕМНЫЕ ПРОВЕРКИ ---
check_root() {
    if [ "$EUID" -ne 0 ]; then echo -e "${RED}Ошибка: запустите через sudo!${NC}"; exit 1; fi
}

install_deps() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}[*] Установка Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    fi
    if ! command -v qrencode &> /dev/null; then
        echo -e "${YELLOW}[*] Установка qrencode...${NC}"
        apt-get update && apt-get install -y qrencode || yum install -y qrencode
    fi
    mkdir -p "$CONFIG_DIR"
    cp "$0" "$BINARY_PATH" && chmod +x "$BINARY_PATH"
}

get_ip() {
    local ip
    ip=$(curl -s -4 --max-time 5 https://api.ipify.org || curl -s -4 --max-time 5 https://icanhazip.com || echo "0.0.0.0")
    echo "$ip" | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1
}

# --- ВЫБОР ДОМЕНА ---
select_domain() {
    local proxy_num="$1"
    local domains=(
        "google.com" "wikipedia.org" "habr.com" "github.com" 
        "coursera.org" "udemy.com" "medium.com" "stackoverflow.com"
        "bbc.com" "cnn.com" "reuters.com" "nytimes.com"
        "lenta.ru" "rbc.ru" "ria.ru" "kommersant.ru"
        "stepik.org" "duolingo.com" "khanacademy.org" "ted.com" 
        "rutube.ru" "live.vkvideo.ru" "youtube.com" "reddit.com"
        "cloudflare.com" "microsoft.com" "apple.com" "amazon.com"
    )
    
    echo -e "${CYAN}Выберите домен для прокси #${proxy_num}:${NC}"
    for i in "${!domains[@]}"; do
        printf "${YELLOW}%2d)${NC} %-20s " "$((i+1))" "${domains[$i]}"
        if [ $(( (i+1) % 3 )) -eq 0 ]; then
            echo ""
        fi
    done
    echo ""
    read -p "Ваш выбор [1-${#domains[@]}]: " d_idx
    
    if [ -z "$d_idx" ] || [ "$d_idx" -lt 1 ] || [ "$d_idx" -gt "${#domains[@]}" ]; then
        echo -e "${YELLOW}Использую домен по умолчанию: google.com${NC}"
        echo "google.com"
    else
        echo "${domains[$((d_idx-1))]}"
    fi
}

# --- ПЕРЕУСТАНОВКА ПРОКСИ #1 ---
reinstall_proxy1() {
    clear
    echo -e "${MAGENTA}=== Переустановка прокси #1 ===${NC}\n"
    
    # Проверяем существует ли прокси
    if docker ps -a | grep -q "mtproto-proxy1"; then
        echo -e "${YELLOW}[*] Останавливаю и удаляю старый прокси #1...${NC}"
        docker stop mtproto-proxy1 &>/dev/null
        docker rm mtproto-proxy1 &>/dev/null
    fi
    
    # Выбор нового домена
    DOMAIN1=$(select_domain "1")
    
    # Выбор порта
    echo -e "\n${CYAN}--- Выберите порт для прокси #1 ---${NC}"
    echo -e "1) Использовать существующий порт (${PORT1:-8443})"
    echo -e "2) 443 (стандартный HTTPS)"
    echo -e "3) 8443 (альтернативный)"
    echo -e "4) Свой порт"
    read -p "Выбор [1-4]: " p_choice
    
    case $p_choice in
        2) PORT1=443 ;;
        3) PORT1=8443 ;;
        4) read -p "Введите свой порт: " PORT1 ;;
        *) PORT1=${PORT1:-8443} ;;
    esac
    
    # Генерация нового секрета
    echo -e "${YELLOW}[*] Генерация нового секрета для прокси #1...${NC}"
    SECRET1=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN1")
    
    # Запуск прокси
    echo -e "${YELLOW}[*] Запуск прокси #1 (${DOMAIN1}) на порту $PORT1...${NC}"
    docker run -d --name mtproto-proxy1 --restart always -p "$PORT1":"$PORT1" \
        nineseconds/mtg:2 simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT1" "$SECRET1" > /dev/null
    
    # Сохраняем конфигурацию
    if [ -f "$CONFIG_DIR/dual_config" ]; then
        source "$CONFIG_DIR/dual_config"
    fi
    
    cat > "$CONFIG_DIR/dual_config" << EOF
PORT1=$PORT1
PORT2=${PORT2:-9443}
SECRET1=$SECRET1
SECRET2=${SECRET2:-}
DOMAIN1=$DOMAIN1
DOMAIN2=${DOMAIN2:-}
EOF
    
    clear
    echo -e "${GREEN}✓ Прокси #1 успешно переустановлен!${NC}"
    show_single_proxy 1
    read -p "Нажмите Enter..."
}

# --- ПЕРЕУСТАНОВКА ПРОКСИ #2 ---
reinstall_proxy2() {
    clear
    echo -e "${MAGENTA}=== Переустановка прокси #2 ===${NC}\n"
    
    # Проверяем существует ли прокси
    if docker ps -a | grep -q "mtproto-proxy2"; then
        echo -e "${YELLOW}[*] Останавливаю и удаляю старый прокси #2...${NC}"
        docker stop mtproto-proxy2 &>/dev/null
        docker rm mtproto-proxy2 &>/dev/null
    fi
    
    # Выбор нового домена
    DOMAIN2=$(select_domain "2")
    
    # Выбор порта
    echo -e "\n${CYAN}--- Выберите порт для прокси #2 ---${NC}"
    echo -e "1) Использовать существующий порт (${PORT2:-9443})"
    echo -e "2) 9443 (рекомендуется)"
    echo -e "3) 443 (стандартный HTTPS)"
    echo -e "4) 8443"
    echo -e "5) Свой порт"
    read -p "Выбор [1-5]: " p_choice
    
    case $p_choice in
        2) PORT2=9443 ;;
        3) PORT2=443 ;;
        4) PORT2=8443 ;;
        5) read -p "Введите свой порт: " PORT2 ;;
        *) PORT2=${PORT2:-9443} ;;
    esac
    
    # Проверка на конфликт портов с прокси #1
    if [ "$PORT2" = "$PORT1" ] && docker ps | grep -q "mtproto-proxy1"; then
        echo -e "${RED}Ошибка: Порт $PORT2 уже используется прокси #1!${NC}"
        echo -e "${YELLOW}Выберите другой порт...${NC}"
        sleep 2
        reinstall_proxy2
        return
    fi
    
    # Генерация нового секрета
    echo -e "${YELLOW}[*] Генерация нового секрета для прокси #2...${NC}"
    SECRET2=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN2")
    
    # Запуск прокси
    echo -e "${YELLOW}[*] Запуск прокси #2 (${DOMAIN2}) на порту $PORT2...${NC}"
    docker run -d --name mtproto-proxy2 --restart always -p "$PORT2":"$PORT2" \
        nineseconds/mtg:2 simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT2" "$SECRET2" > /dev/null
    
    # Сохраняем конфигурацию
    if [ -f "$CONFIG_DIR/dual_config" ]; then
        source "$CONFIG_DIR/dual_config"
    fi
    
    cat > "$CONFIG_DIR/dual_config" << EOF
PORT1=${PORT1:-8443}
PORT2=$PORT2
SECRET1=${SECRET1:-}
SECRET2=$SECRET2
DOMAIN1=${DOMAIN1:-}
DOMAIN2=$DOMAIN2
EOF
    
    clear
    echo -e "${GREEN}✓ Прокси #2 успешно переустановлен!${NC}"
    show_single_proxy 2
    read -p "Нажмите Enter..."
}

# --- ПОКАЗ ОДНОГО ПРОКСИ ---
show_single_proxy() {
    local num="$1"
    local container="mtproto-proxy$num"
    
    if ! docker ps | grep -q "$container"; then
        echo -e "${RED}Прокси #$num не найден или не запущен!${NC}"
        return 1
    fi
    
    IP=$(get_ip)
    PORT=$(docker inspect "$container" --format='{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}{{end}}' 2>/dev/null)
    SECRET=$(docker inspect "$container" --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}')
    
    # Пытаемся получить домен из конфига
    if [ -f "$CONFIG_DIR/dual_config" ]; then
        source "$CONFIG_DIR/dual_config"
        if [ "$num" = "1" ]; then
            DOMAIN_STR=$DOMAIN1
        else
            DOMAIN_STR=$DOMAIN2
        fi
    fi
    
    LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
    
    echo -e "\n${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}           ПРОКСИ #$num${NC}"
    if [ -n "$DOMAIN_STR" ]; then
        echo -e "${GREEN}           Маскировка: ${DOMAIN_STR}${NC}"
    fi
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "IP: ${CYAN}$IP${NC} | Port: ${CYAN}$PORT${NC}"
    echo -e "Secret: ${YELLOW}$SECRET${NC}"
    echo -e "Link: ${BLUE}$LINK${NC}"
    echo -e "\n${GREEN}QR Code:${NC}"
    qrencode -t ANSIUTF8 "$LINK"
    
    # Сохраняем ссылку
    echo "$LINK" > "$CONFIG_DIR/proxy${num}_link.txt"
}

# --- ПОКАЗ ДВУХ КОНФИГУРАЦИЙ ---
show_dual_config() {
    IP=$(get_ip)
    
    # Загрузка конфигурации если существует
    if [ -f "$CONFIG_DIR/dual_config" ]; then
        source "$CONFIG_DIR/dual_config"
    else
        # Автоопределение из docker
        PORT1=$(docker inspect mtproto-proxy1 --format='{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}{{end}}' 2>/dev/null)
        PORT2=$(docker inspect mtproto-proxy2 --format='{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}{{end}}' 2>/dev/null)
        SECRET1=$(docker inspect mtproto-proxy1 --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}' 2>/dev/null)
        SECRET2=$(docker inspect mtproto-proxy2 --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}' 2>/dev/null)
    fi
    
    if [ -z "$PORT1" ] || [ -z "$SECRET1" ]; then
        echo -e "${RED}Прокси не найдены!${NC}"
        return
    fi
    
    LINK1="tg://proxy?server=$IP&port=$PORT1&secret=$SECRET1"
    LINK2="tg://proxy?server=$IP&port=$PORT2&secret=$SECRET2"
    
    echo -e "\n${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}           ПРОКСИ #1 (${DOMAIN1:-Fake TLS})${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "IP: ${CYAN}$IP${NC} | Port: ${CYAN}$PORT1${NC}"
    echo -e "Secret: ${YELLOW}$SECRET1${NC}"
    echo -e "Link: ${BLUE}$LINK1${NC}"
    echo -e "\n${GREEN}QR Code:${NC}"
    qrencode -t ANSIUTF8 "$LINK1"
    
    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}           ПРОКСИ #2 (${DOMAIN2:-Fake TLS})${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════${NC}"
    echo -e "IP: ${CYAN}$IP${NC} | Port: ${CYAN}$PORT2${NC}"
    echo -e "Secret: ${YELLOW}$SECRET2${NC}"
    echo -e "Link: ${BLUE}$LINK2${NC}"
    echo -e "\n${MAGENTA}QR Code:${NC}"
    qrencode -t ANSIUTF8 "$LINK2"
    
    # Сохранение ссылок в файл
    cat > "$CONFIG_DIR/links.txt" << EOF
=== MTProxy Links ===
Proxy #1: $LINK1
Proxy #2: $LINK2
Дата создания: $(date)
EOF
    echo -e "\n${GREEN}[✓] Ссылки сохранены в: $CONFIG_DIR/links.txt${NC}"
}

# --- УСТАНОВКА ДВУХ ПРОКСИ ---
menu_install_dual() {
    clear
    echo -e "${CYAN}=== Установка двух прокси ===${NC}\n"
    
    # Выбор доменов
    DOMAIN1=$(select_domain "1")
    DOMAIN2=$(select_domain "2")
    
    # Выбор портов
    echo -e "\n${CYAN}--- Настройка портов ---${NC}"
    echo -e "1) Автоматически (порт 8443 и 9443)"
    echo -e "2) Вручную"
    read -p "Выбор: " port_choice
    
    if [ "$port_choice" = "2" ]; then
        read -p "Порт для первого прокси: " PORT1
        read -p "Порт для второго прокси: " PORT2
    else
        PORT1=8443
        PORT2=9443
    fi
    
    # Генерация двух secret
    echo -e "${YELLOW}[*] Генерация secret...${NC}"
    SECRET1=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN1")
    SECRET2=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN2")
    
    # Удаление старых контейнеров
    docker stop mtproto-proxy1 mtproto-proxy2 &>/dev/null
    docker rm mtproto-proxy1 mtproto-proxy2 &>/dev/null
    
    # Запуск первого прокси
    echo -e "${YELLOW}[*] Запуск прокси #1 (${DOMAIN1}) на порту $PORT1...${NC}"
    docker run -d --name mtproto-proxy1 --restart always -p "$PORT1":"$PORT1" \
        nineseconds/mtg:2 simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT1" "$SECRET1" > /dev/null
    
    # Запуск второго прокси
    echo -e "${YELLOW}[*] Запуск прокси #2 (${DOMAIN2}) на порту $PORT2...${NC}"
    docker run -d --name mtproto-proxy2 --restart always -p "$PORT2":"$PORT2" \
        nineseconds/mtg:2 simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT2" "$SECRET2" > /dev/null
    
    # Сохранение конфигурации
    cat > "$CONFIG_DIR/dual_config" << EOF
PORT1=$PORT1
PORT2=$PORT2
SECRET1=$SECRET1
SECRET2=$SECRET2
DOMAIN1=$DOMAIN1
DOMAIN2=$DOMAIN2
EOF
    
    clear
    show_dual_config
    read -p "Установка завершена. Нажмите Enter..."
}

# --- УСТАНОВКА ОДНОГО ПРОКСИ ---
menu_install_single() {
    clear
    echo -e "${CYAN}--- Выберите домен для маскировки (Fake TLS) ---${NC}"
    domains=(
        "google.com" "wikipedia.org" "habr.com" "github.com" 
        "coursera.org" "udemy.com" "medium.com" "stackoverflow.com"
        "bbc.com" "cnn.com" "reuters.com" "nytimes.com"
        "lenta.ru" "rbc.ru" "ria.ru" "kommersant.ru"
        "stepik.org" "duolingo.com" "khanacademy.org" "ted.com" "rutube.ru" "live.vkvideo.ru" 
    )
    
    for i in "${!domains[@]}"; do
        printf "${YELLOW}%2d)${NC} %-20s " "$((i+1))" "${domains[$i]}"
        [[ $(( (i+1) % 2 )) -eq 0 ]] && echo ""
    done
    
    read -p "Ваш выбор [1-22]: " d_idx
    DOMAIN=${domains[$((d_idx-1))]}
    DOMAIN=${DOMAIN:-google.com}

    echo -e "\n${CYAN}--- Выберите порт ---${NC}"
    echo -e "1) 443 (Рекомендуется)"
    echo -e "2) 8443"
    echo -e "3) Свой порт"
    read -p "Выбор: " p_choice
    case $p_choice in
        2) PORT=8443 ;;
        3) read -p "Введите свой порт: " PORT ;;
        *) PORT=443 ;;
    esac

    echo -e "${YELLOW}[*] Настройка прокси...${NC}"
    SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$DOMAIN")
    docker stop mtproto-proxy &>/dev/null && docker rm mtproto-proxy &>/dev/null
    
    docker run -d --name mtproto-proxy --restart always -p "$PORT":"$PORT" \
        nineseconds/mtg:2 simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:"$PORT" "$SECRET" > /dev/null
    
    clear
    show_config
    read -p "Установка завершена. Нажмите Enter..."
}

# --- ПОКАЗ ОДНОЙ КОНФИГУРАЦИИ ---
show_config() {
    if ! docker ps | grep -q "mtproto-proxy"; then 
        echo -e "${RED}Прокси не найден!${NC}"
        return
    fi
    SECRET=$(docker inspect mtproto-proxy --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}')
    IP=$(get_ip)
    PORT=$(docker inspect mtproto-proxy --format='{{range $p, $conf := .HostConfig.PortBindings}}{{(index $conf 0).HostPort}}{{end}}' 2>/dev/null)
    PORT=${PORT:-443}
    LINK="tg://proxy?server=$IP&port=$PORT&secret=$SECRET"

    echo -e "\n${GREEN}=== ПАНЕЛЬ ДАННЫХ ===${NC}"
    echo -e "IP: $IP | Port: $PORT"
    echo -e "Secret: $SECRET"
    echo -e "Link: ${BLUE}$LINK${NC}"
    qrencode -t ANSIUTF8 "$LINK"
}

# --- УДАЛЕНИЕ ВСЕХ ПРОКСИ ---
menu_remove_all() {
    echo -e "${RED}[!] Удаление всех прокси...${NC}"
    docker stop mtproto-proxy mtproto-proxy1 mtproto-proxy2 &>/dev/null
    docker rm mtproto-proxy mtproto-proxy1 mtproto-proxy2 &>/dev/null
    rm -f "$CONFIG_DIR/dual_config" "$CONFIG_DIR/links.txt" "$CONFIG_DIR/proxy"*_link.txt
    echo -e "${GREEN}[✓] Все прокси удалены${NC}"
    read -p "Нажмите Enter..."
}

# --- МЕНЮ УПРАВЛЕНИЯ ДВУМЯ ПРОКСИ ---
menu_dual_management() {
    while true; do
        clear
        echo -e "${MAGENTA}=== Управление двумя прокси ===${NC}\n"
        
        # Показываем статус
        if docker ps | grep -q "mtproto-proxy1"; then
            echo -e "${GREEN}✓ Прокси #1: ЗАПУЩЕН${NC}"
        else
            echo -e "${RED}✗ Прокси #1: НЕ ЗАПУЩЕН${NC}"
        fi
        
        if docker ps | grep -q "mtproto-proxy2"; then
            echo -e "${GREEN}✓ Прокси #2: ЗАПУЩЕН${NC}"
        else
            echo -e "${RED}✗ Прокси #2: НЕ ЗАПУЩЕН${NC}"
        fi
        
        echo -e "\n${CYAN}Выберите действие:${NC}"
        echo -e "1) Переустановить прокси #1 (новый секрет и домен)"
        echo -e "2) Переустановить прокси #2 (новый секрет и домен)"
        echo -e "3) Показать оба прокси"
        echo -e "4) Показать только прокси #1"
        echo -e "5) Показать только прокси #2"
        echo -e "6) Остановить прокси #1"
        echo -e "7) Остановить прокси #2"
        echo -e "8) Запустить прокси #1"
        echo -e "9) Запустить прокси #2"
        echo -e "0) Вернуться в главное меню"
        
        read -p "Выбор: " choice
        
        case $choice in
            1) reinstall_proxy1 ;;
            2) reinstall_proxy2 ;;
            3) clear; show_dual_config; read -p "Нажмите Enter..." ;;
            4) clear; show_single_proxy 1; read -p "Нажмите Enter..." ;;
            5) clear; show_single_proxy 2; read -p "Нажмите Enter..." ;;
            6) docker stop mtproto-proxy1 && echo "Прокси #1 остановлен" || echo "Ошибка"; sleep 1 ;;
            7) docker stop mtproto-proxy2 && echo "Прокси #2 остановлен" || echo "Ошибка"; sleep 1 ;;
            8) docker start mtproto-proxy1 && echo "Прокси #1 запущен" || echo "Ошибка"; sleep 1 ;;
            9) docker start mtproto-proxy2 && echo "Прокси #2 запущен" || echo "Ошибка"; sleep 1 ;;
            0) break ;;
            *) echo "Неверный ввод"; sleep 1 ;;
        esac
    done
}

# --- ВЫХОД ---
show_exit() {
    clear
    if docker ps | grep -q "mtproto-proxy1"; then
        show_dual_config 2>/dev/null
    elif docker ps | grep -q "mtproto-proxy"; then
        show_config 2>/dev/null
    fi
    echo -e "\n${GREEN}До свидания!${NC}"
    exit 0
}

# --- СТАРТ СКРИПТА ---
check_root
install_deps

echo " __  __ _____ ____                      "
echo "|  \/  |_   _|  _ \ _ __ _____  ___   _ "
echo "| |\/| | | | | |_) | '__/ _ \ \/ / | | |"
echo "| |  | | | | |  __/| | | (_) >  <| |_| |"
echo "|_|  |_| |_| |_|   |_|  \___/_/\_\\__, |"
echo "                                  |___/ "

while true; do
    echo -e "\n${MAGENTA}=== MTProxy Manager Fake TLS ===${NC}"
    echo -e "1) ${GREEN}Установить ОДИН прокси${NC}"
    echo -e "2) ${GREEN}Установить ДВА прокси (разные порты)${NC}"
    echo -e "3) ${CYAN}Управление двумя прокси${NC} ${YELLOW}(переустановка, остановка)${NC}"
    echo -e "4) Показать данные подключения (один прокси)${NC}"
    echo -e "5) Показать данные подключения (два прокси)${NC}"
    echo -e "6) ${RED}Удалить все прокси${NC}"
    echo -e "0) Выход${NC}"
    read -p "Пункт: " m_idx
    case $m_idx in
        1) menu_install_single ;;
        2) menu_install_dual ;;
        3) menu_dual_management ;;
        4) clear; show_config; read -p "Нажмите Enter..." ;;
        5) clear; show_dual_config; read -p "Нажмите Enter..." ;;
        6) menu_remove_all ;;
        0) show_exit ;;
        *) echo "Неверный ввод" ;;
    esac
done
