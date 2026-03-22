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
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    fi
    if ! command -v qrencode &> /dev/null; then
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

# --- ГЕНЕРАЦИЯ ДВУХ SECRET ---
generate_two_secrets() {
    local domain1="$1"
    local domain2="$2"
    
    # Генерируем два разных secret для разных доменов
    SECRET1=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$domain1")
    SECRET2=$(docker run --rm nineseconds/mtg:2 generate-secret --hex "$domain2")
    
    echo "$SECRET1|$SECRET2"
}

# --- УСТАНОВКА С ДВУМЯ ПРОКСИ ---
menu_install_dual() {
    clear
    echo -e "${CYAN}=== Установка двух прокси на разных портах ===${NC}\n"
    
    # Выбор доменов
    domains=(
        "google.com" "wikipedia.org" "habr.com" "github.com" 
        "coursera.org" "udemy.com" "medium.com" "stackoverflow.com"
        "bbc.com" "cnn.com" "reuters.com" "nytimes.com"
        "lenta.ru" "rbc.ru" "ria.ru" "kommersant.ru"
        "stepik.org" "duolingo.com" "khanacademy.org" "ted.com" 
        "rutube.ru" "live.vkvideo.ru" "youtube.com" "reddit.com"
    )
    
    echo -e "${YELLOW}Выберите домен для первого прокси:${NC}"
    for i in "${!domains[@]}"; do
        printf "${YELLOW}%2d)${NC} %-20s " "$((i+1))" "${domains[$i]}"
        [[ $(( (i+1) % 3 )) -eq 0 ]] && echo ""
    done
    echo ""
    read -p "Ваш выбор [1-${#domains[@]}]: " d1_idx
    DOMAIN1=${domains[$((d1_idx-1))]}
    
    echo -e "\n${YELLOW}Выберите домен для второго прокси:${NC}"
    read -p "Ваш выбор [1-${#domains[@]}]: " d2_idx
    DOMAIN2=${domains[$((d2_idx-1))]}
    
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
    SECRETS=$(generate_two_secrets "$DOMAIN1" "$DOMAIN2")
    SECRET1=$(echo "$SECRETS" | cut -d'|' -f1)
    SECRET2=$(echo "$SECRETS" | cut -d'|' -f2)
    
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
        SECRET1=$(docker inspect mtproto-proxy1 --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}')
        SECRET2=$(docker inspect mtproto-proxy2 --format='{{range .Config.Cmd}}{{.}} {{end}}' | awk '{print $NF}')
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
EOF
    echo -e "\n${GREEN}[✓] Ссылки сохранены в: $CONFIG_DIR/links.txt${NC}"
}

# --- УСТАНОВКА ОДНОГО ПРОКСИ (оригинальная функция) ---
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
    rm -f "$CONFIG_DIR/dual_config" "$CONFIG_DIR/links.txt"
    echo -e "${GREEN}[✓] Все прокси удалены${NC}"
    read -p "Нажмите Enter..."
}

# --- ВЫХОД ---
show_exit() {
    clear
    show_dual_config 2>/dev/null || show_config 2>/dev/null
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
    echo -e "3) Показать данные подключения (один прокси)${NC}"
    echo -e "4) Показать данные подключения (два прокси)${NC}"
    echo -e "5) ${RED}Удалить все прокси${NC}"
    echo -e "0) Выход${NC}"
    read -p "Пункт: " m_idx
    case $m_idx in
        1) menu_install_single ;;
        2) menu_install_dual ;;
        3) clear; show_config; read -p "Нажмите Enter..." ;;
        4) clear; show_dual_config; read -p "Нажмите Enter..." ;;
        5) menu_remove_all ;;
        0) show_exit ;;
        *) echo "Неверный ввод" ;;
    esac
done
