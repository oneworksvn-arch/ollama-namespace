#!/bin/bash
# ==============================================================================
#  VIENEU-TTS - SCRIPT CAI DAT TU DONG CHO NAMESPACE DEVBOX
#  Cai dat VieNeu-TTS (Text-to-Speech tieng Viet) voi Web UI va API
#  Ho tro: Devbox / Container / VPS (khong can systemd, khong can GPU)
# ==============================================================================

set -e

# --- MAU SAC HIEN THI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- CAU HINH MAC DINH ---
INSTALL_DIR="/workspaces/VieNeu-TTS"
VIENEU_REPO="https://github.com/pnnbao97/VieNeu-TTS.git"
WEB_PORT=7860
STREAM_PORT=8001
PROXY_PORT=7000
SERVER_MODE="web"  # web | stream

# --- CONFIG FILE ---
CONFIG_DIR="/etc/vieneu-tts"
CONFIG_FILE="$CONFIG_DIR/config"

# --- HAM HO TRO ---
print_step() {
    echo -e "\n${BLUE}${BOLD}[$1]${NC} $2"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_err() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_banner() {
    echo -e "${GREEN}${BOLD}"
    echo "  ============================================================"
    echo "   VIENEU-TTS INSTALLER cho Namespace Devbox"
    echo "   Text-to-Speech tieng Viet chat luong cao"
    echo "   Ho tro: Web UI (Gradio) + Streaming API (FastAPI)"
    echo "  ============================================================"
    echo -e "${NC}"
}

usage() {
    echo -e "${BOLD}Su dung:${NC}"
    echo ""
    echo "  ${BOLD}Cai dat day du:${NC}"
    echo "    bash install.sh install [--mode web|stream] [--port PORT]"
    echo ""
    echo "  ${BOLD}Khoi dong server:${NC}"
    echo "    bash install.sh start [--mode web|stream]"
    echo ""
    echo "  ${BOLD}Dung server:${NC}"
    echo "    bash install.sh stop"
    echo ""
    echo "  ${BOLD}Xem trang thai:${NC}"
    echo "    bash install.sh status"
    echo ""
    echo "  ${BOLD}Test TTS:${NC}"
    echo "    bash install.sh test"
    echo ""
    echo "  ${BOLD}Cap nhat VieNeu-TTS:${NC}"
    echo "    bash install.sh update"
    echo ""
    echo "  ${BOLD}Keep-alive (chong Devbox ngu):${NC}"
    echo "    bash install.sh keep-alive"
    echo ""
    echo "  ${BOLD}Auto-start (khi Devbox bat lai):${NC}"
    echo "    bash install.sh startup"
    echo ""
    echo "  ${BOLD}Go cai dat:${NC}"
    echo "    bash install.sh uninstall"
    echo ""
    echo -e "${BOLD}Tuy chon:${NC}"
    echo "  --mode web|stream   Che do chay: web (Gradio UI) hoac stream (FastAPI)"
    echo "  --port PORT         Port proxy Nginx (mac dinh: 7000)"
    echo ""
    echo -e "${BOLD}Vi du:${NC}"
    echo "  bash install.sh install                    # Cai dat voi Web UI"
    echo "  bash install.sh install --mode stream      # Cai dat voi Streaming API"
    echo "  bash install.sh install --port 8080        # Doi port proxy"
    echo ""
    echo -e "${BOLD}Model ho tro (CPU - khong can GPU):${NC}"
    echo "  - VieNeu-TTS-v2-Turbo (CPU)  : Sieu nhanh, ho tro song ngu En-Vi"
    echo "  - VieNeu-TTS-v2-CPU (GGUF)   : Chat luong cao hon, can CPU manh"
    echo ""
}

# --- DOC CAU HINH ---
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

save_config() {
    sudo mkdir -p "$CONFIG_DIR"
    sudo tee "$CONFIG_FILE" > /dev/null << EOF
INSTALL_DIR=$INSTALL_DIR
WEB_PORT=$WEB_PORT
STREAM_PORT=$STREAM_PORT
PROXY_PORT=$PROXY_PORT
SERVER_MODE=$SERVER_MODE
EOF
    print_ok "Da luu cau hinh."
}

# --- CAI DAT DEPENDENCY ---
install_deps() {
    local need_install=false
    for pkg in nginx curl git; do
        if ! command -v "$pkg" &>/dev/null; then
            need_install=true
            break
        fi
    done
    if $need_install; then
        echo "Cai dat cac goi can thiet (nginx, curl, git)..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq nginx curl git
        print_ok "Da cai dat cac goi can thiet."
    fi
}

# --- CAI DAT UV ---
install_uv() {
    print_step "1/5" "Kiem tra va cai dat uv (Python package manager)..."

    if command -v uv &>/dev/null; then
        print_ok "uv da duoc cai dat san."
        uv --version 2>/dev/null || true
    else
        echo "Dang tai va cai dat uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        # Add uv to PATH for current session
        export PATH="$HOME/.local/bin:$PATH"
        if command -v uv &>/dev/null; then
            print_ok "Cai dat uv thanh cong."
            uv --version
        else
            print_err "Khong the cai dat uv. Vui long cai dat thu cong."
            exit 1
        fi
    fi
}

# --- CLONE VIENEU-TTS ---
clone_vieneu() {
    print_step "2/5" "Clone VieNeu-TTS tu GitHub..."

    if [ -d "$INSTALL_DIR/.git" ]; then
        print_ok "VieNeu-TTS da duoc clone san tai $INSTALL_DIR"
        echo "Dang cap nhat..."
        cd "$INSTALL_DIR"
        git pull --ff-only 2>/dev/null || print_warn "Khong the cap nhat, su dung phien ban hien tai."
    else
        echo "Dang clone VieNeu-TTS..."
        if [ -d "$INSTALL_DIR" ]; then
            rm -rf "$INSTALL_DIR"
        fi
        git clone "$VIENEU_REPO" "$INSTALL_DIR"
        print_ok "Clone VieNeu-TTS thanh cong."
    fi
}

# --- CAI DAT DEPENDENCIES PYTHON ---
install_python_deps() {
    print_step "3/5" "Cai dat dependencies Python (CPU mode)..."

    cd "$INSTALL_DIR"

    echo "Dang chay: uv sync (Turbo/CPU mode - khong can GPU)..."
    echo "Luu y: Lan dau se mat vai phut de tai cac packages..."

    # Ensure PATH includes uv
    export PATH="$HOME/.local/bin:$PATH"

    uv sync 2>&1 | tail -5

    print_ok "Cai dat dependencies thanh cong."
}

# --- CAU HINH NGINX REVERSE PROXY ---
setup_nginx() {
    print_step "4/5" "Cau hinh Nginx Reverse Proxy..."

    local backend_port
    if [ "$SERVER_MODE" = "stream" ]; then
        backend_port=$STREAM_PORT
    else
        backend_port=$WEB_PORT
    fi

    sudo tee /etc/nginx/sites-available/vieneu-tts > /dev/null << NGINX_EOF
server {
    listen $PROXY_PORT;
    server_name _;

    # Tang timeout cho TTS (co the mat nhieu thoi gian)
    proxy_connect_timeout 300;
    proxy_send_timeout 300;
    proxy_read_timeout 300;

    # Health check
    location /health {
        access_log off;
        return 200 '{"status":"ok","service":"vieneu-tts","mode":"$SERVER_MODE"}';
        add_header Content-Type application/json;
    }

    # Proxy tat ca request den VieNeu-TTS
    location / {
        proxy_pass http://127.0.0.1:$backend_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Streaming support
        proxy_buffering off;
        chunked_transfer_encoding on;
    }
}
NGINX_EOF

    # Enable site
    sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    sudo ln -sf /etc/nginx/sites-available/vieneu-tts /etc/nginx/sites-enabled/

    # Test & reload
    sudo nginx -t 2>/dev/null && sudo service nginx restart 2>/dev/null || sudo nginx -s reload 2>/dev/null || true

    print_ok "Nginx proxy da cau hinh (port $PROXY_PORT -> $backend_port)."
}

# --- NAMESPACE DEVBOX: AUTO-START & KEEP-ALIVE ---
setup_autostart() {
    print_step "5/5" "Cau hinh auto-start cho Namespace Devbox..."

    # Tao startup script
    local startup_script="/workspaces/start-vieneu-tts.sh"
    cat > "$startup_script" << 'STARTUP_EOF'
#!/bin/bash
# Auto-start VieNeu-TTS khi Devbox khoi dong
CONFIG_FILE="/etc/vieneu-tts/config"
LOG_FILE="/tmp/vieneu-tts-autostart.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "=== AUTO-START BEGIN ==="

# Load config
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    log "Config loaded: mode=$SERVER_MODE, proxy_port=$PROXY_PORT"
else
    log "No config found, using defaults"
    INSTALL_DIR="/workspaces/VieNeu-TTS"
    SERVER_MODE="web"
    PROXY_PORT=7000
fi

# Ensure PATH
export PATH="$HOME/.local/bin:$PATH"

# Start VieNeu-TTS
if ! pgrep -f "gradio_main\|web_stream\|vieneu-web\|vieneu-stream" &>/dev/null; then
    log "Starting VieNeu-TTS ($SERVER_MODE mode)..."
    cd "$INSTALL_DIR"
    if [ "$SERVER_MODE" = "stream" ]; then
        GRADIO_SERVER_NAME=0.0.0.0 nohup uv run vieneu-stream >> /tmp/vieneu-tts-server.log 2>&1 &
    else
        GRADIO_SERVER_NAME=0.0.0.0 nohup uv run vieneu-web >> /tmp/vieneu-tts-server.log 2>&1 &
    fi
    log "VieNeu-TTS started (PID: $!)"
else
    log "VieNeu-TTS already running"
fi

# Start Nginx
if ! pgrep -f "nginx" &>/dev/null; then
    log "Starting Nginx..."
    sudo service nginx start 2>/dev/null || sudo nginx 2>/dev/null
    log "Nginx started"
else
    log "Nginx already running"
fi

log "=== AUTO-START COMPLETE ==="
STARTUP_EOF
    chmod +x "$startup_script"
    print_ok "Tao startup script: $startup_script"

    # Tao keep-alive script
    local keepalive_script="/workspaces/keep-alive-tts.sh"
    cat > "$keepalive_script" << 'KEEPALIVE_EOF'
#!/bin/bash
# Keep-alive: Chong Namespace Devbox bi tam dung do idle
LOG_FILE="/tmp/keep-alive-tts.log"
TASK_DIR="/.namespace/tasks"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Keep-alive TTS started"

while true; do
    # Tao/cap nhat task file de Namespace biet Devbox dang hoat dong
    if [ -d "$TASK_DIR" ] || sudo mkdir -p "$TASK_DIR" 2>/dev/null; then
        sudo touch "$TASK_DIR/vieneu-tts" 2>/dev/null || touch "$TASK_DIR/vieneu-tts" 2>/dev/null
    fi

    # Kiem tra va khoi dong lai VieNeu-TTS neu bi tat
    if ! pgrep -f "gradio_main\|web_stream\|vieneu-web\|vieneu-stream" &>/dev/null; then
        log "VieNeu-TTS khong chay, dang khoi dong lai..."
        if [ -f /workspaces/start-vieneu-tts.sh ]; then
            bash /workspaces/start-vieneu-tts.sh
        fi
    fi

    # Kiem tra Nginx
    if ! pgrep -f "nginx" &>/dev/null; then
        log "Nginx khong chay, dang khoi dong lai..."
        sudo service nginx start 2>/dev/null || sudo nginx 2>/dev/null
    fi

    log "Keep-alive ping OK"
    sleep 300  # Moi 5 phut
done
KEEPALIVE_EOF
    chmod +x "$keepalive_script"
    print_ok "Tao keep-alive script: $keepalive_script"

    # Them vao bashrc
    local bashrc_file="$HOME/.bashrc"
    if [ ! -f "$bashrc_file" ]; then
        touch "$bashrc_file"
    fi

    # Xoa entry cu neu co
    if grep -q "VieNeu-TTS Auto-Start" "$bashrc_file" 2>/dev/null; then
        # Remove old block
        sed -i '/# === VieNeu-TTS Auto-Start ===/,/# === End VieNeu-TTS ===/d' "$bashrc_file"
    fi

    cat >> "$bashrc_file" << 'BASHRC_EOF'

# === VieNeu-TTS Auto-Start ===
if [ -f /workspaces/start-vieneu-tts.sh ]; then
    /workspaces/start-vieneu-tts.sh &>/dev/null &
fi
# Keep-Alive TTS (chong Devbox tam dung)
if [ -f /workspaces/keep-alive-tts.sh ] && ! pgrep -f "keep-alive-tts.sh" &>/dev/null; then
    nohup /workspaces/keep-alive-tts.sh &>/dev/null &
fi
# === End VieNeu-TTS ===
BASHRC_EOF

    print_ok "Da them auto-start vao ~/.bashrc"
}

# === LENH: INSTALL ===
cmd_install() {
    print_banner

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                SERVER_MODE="$2"
                if [[ "$SERVER_MODE" != "web" && "$SERVER_MODE" != "stream" ]]; then
                    print_err "Mode khong hop le: $SERVER_MODE (chi ho tro: web, stream)"
                    exit 1
                fi
                shift 2
                ;;
            --port)
                PROXY_PORT="$2"
                shift 2
                ;;
            *)
                print_err "Tham so khong hop le: $1"
                usage
                exit 1
                ;;
        esac
    done

    echo -e "Cau hinh:"
    echo -e "  Mode:       ${BOLD}$SERVER_MODE${NC}"
    echo -e "  Proxy Port: ${BOLD}$PROXY_PORT${NC}"
    echo -e "  Install Dir: ${BOLD}$INSTALL_DIR${NC}"
    echo ""

    install_deps
    install_uv
    clone_vieneu
    install_python_deps
    setup_nginx
    save_config
    setup_autostart

    # Khoi dong server
    echo ""
    print_step "*" "Khoi dong VieNeu-TTS..."
    cmd_start_internal

    # Hien thi thong tin
    echo ""
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}  CAI DAT VIENEU-TTS THANH CONG!${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo ""

    local server_ip
    server_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

    echo -e "  ${BOLD}Web UI:${NC}         http://${server_ip}:${PROXY_PORT}"
    echo -e "  ${BOLD}Mode:${NC}           $SERVER_MODE"
    echo -e "  ${BOLD}Proxy Port:${NC}     $PROXY_PORT"
    if [ "$SERVER_MODE" = "web" ]; then
        echo -e "  ${BOLD}Gradio Port:${NC}    $WEB_PORT (internal)"
    else
        echo -e "  ${BOLD}Stream Port:${NC}   $STREAM_PORT (internal)"
    fi
    echo ""
    echo -e "  ${BOLD}Lenh huu ich:${NC}"
    echo -e "    bash install.sh status     # Xem trang thai"
    echo -e "    bash install.sh test       # Test TTS"
    echo -e "    bash install.sh stop       # Dung server"
    echo -e "    bash install.sh start      # Khoi dong lai"
    echo ""
}

# === LENH: START (internal, khong load config) ===
cmd_start_internal() {
    export PATH="$HOME/.local/bin:$PATH"
    cd "$INSTALL_DIR"

    if pgrep -f "gradio_main\|web_stream\|vieneu-web\|vieneu-stream" &>/dev/null; then
        print_warn "VieNeu-TTS dang chay. Dung 'bash install.sh stop' truoc."
        return 0
    fi

    if [ "$SERVER_MODE" = "stream" ]; then
        echo "Khoi dong VieNeu-TTS Stream API (port $STREAM_PORT)..."
        GRADIO_SERVER_NAME=0.0.0.0 nohup uv run vieneu-stream >> /tmp/vieneu-tts-server.log 2>&1 &
    else
        echo "Khoi dong VieNeu-TTS Web UI (port $WEB_PORT)..."
        GRADIO_SERVER_NAME=0.0.0.0 nohup uv run vieneu-web >> /tmp/vieneu-tts-server.log 2>&1 &
    fi
    local pid=$!
    echo "PID: $pid"

    # Doi server san sang
    echo "Dang doi server khoi dong (co the mat 1-2 phut lan dau)..."
    local target_port
    if [ "$SERVER_MODE" = "stream" ]; then
        target_port=$STREAM_PORT
    else
        target_port=$WEB_PORT
    fi

    local max_wait=180
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if curl -s "http://127.0.0.1:$target_port" &>/dev/null; then
            print_ok "VieNeu-TTS da san sang!"
            return 0
        fi
        # Check if process still alive
        if ! kill -0 $pid 2>/dev/null; then
            print_err "VieNeu-TTS da thoat bat thuong. Xem log:"
            echo "  tail -50 /tmp/vieneu-tts-server.log"
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
        echo "  Dang doi... ($waited/$max_wait giay)"
    done

    print_warn "Server chua san sang sau ${max_wait}s. Kiem tra log:"
    echo "  tail -50 /tmp/vieneu-tts-server.log"
}

# === LENH: START ===
cmd_start() {
    load_config

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                SERVER_MODE="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Start Nginx
    if ! pgrep -f "nginx" &>/dev/null; then
        sudo service nginx start 2>/dev/null || sudo nginx 2>/dev/null
        print_ok "Nginx da khoi dong."
    fi

    cmd_start_internal

    # Start keep-alive
    if [ -f /workspaces/keep-alive-tts.sh ] && ! pgrep -f "keep-alive-tts.sh" &>/dev/null; then
        nohup /workspaces/keep-alive-tts.sh &>/dev/null &
        print_ok "Keep-alive da bat."
    fi
}

# === LENH: STOP ===
cmd_stop() {
    load_config
    echo "Dang dung VieNeu-TTS..."

    # Stop VieNeu-TTS processes
    pkill -f "gradio_main" 2>/dev/null || true
    pkill -f "web_stream" 2>/dev/null || true
    pkill -f "vieneu-web" 2>/dev/null || true
    pkill -f "vieneu-stream" 2>/dev/null || true

    # Stop keep-alive
    pkill -f "keep-alive-tts.sh" 2>/dev/null || true

    sleep 1
    print_ok "Da dung VieNeu-TTS."
}

# === LENH: STATUS ===
cmd_status() {
    load_config

    echo ""
    echo -e "${BOLD}=== TRANG THAI HE THONG ===${NC}"
    echo ""

    # VieNeu-TTS process
    if pgrep -f "gradio_main\|web_stream\|vieneu-web\|vieneu-stream" &>/dev/null; then
        print_ok "VieNeu-TTS: DANG CHAY"
        pgrep -fa "gradio_main\|web_stream" 2>/dev/null | head -3
    else
        print_err "VieNeu-TTS: KHONG CHAY"
    fi

    # Nginx
    if pgrep -f "nginx" &>/dev/null; then
        print_ok "Nginx: DANG CHAY"
    else
        print_err "Nginx: KHONG CHAY"
    fi

    # Proxy port
    if [ -n "$PROXY_PORT" ] && curl -s "http://127.0.0.1:$PROXY_PORT/health" &>/dev/null; then
        print_ok "Port $PROXY_PORT: DANG LANG NGHE"
    else
        print_err "Port ${PROXY_PORT:-7000}: KHONG MO"
    fi

    # Keep-alive
    if pgrep -f "keep-alive-tts.sh" &>/dev/null; then
        print_ok "Keep-alive: DANG CHAY"
    else
        print_warn "Keep-alive: KHONG CHAY"
    fi

    echo ""
    echo -e "  ${BOLD}Mode:${NC}        ${SERVER_MODE:-web}"
    echo -e "  ${BOLD}Proxy Port:${NC}  ${PROXY_PORT:-7000}"
    echo -e "  ${BOLD}Install Dir:${NC} ${INSTALL_DIR:-/workspaces/VieNeu-TTS}"
    echo ""
}

# === LENH: TEST ===
cmd_test() {
    load_config

    echo ""
    echo -e "${BOLD}=== TEST VIENEU-TTS ===${NC}"
    echo ""

    local proxy_port="${PROXY_PORT:-7000}"

    # 1. Health check
    echo -e "${BOLD}1. Health Check:${NC}"
    local health
    health=$(curl -s "http://127.0.0.1:$proxy_port/health" 2>/dev/null)
    if [ -n "$health" ]; then
        print_ok "Health: $health"
    else
        print_err "Khong ket noi duoc den server."
        echo "  Thu: bash install.sh start"
        return 1
    fi

    # 2. Check Web UI
    echo -e "\n${BOLD}2. Web UI:${NC}"
    local web_status
    web_status=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$proxy_port/" 2>/dev/null)
    if [ "$web_status" = "200" ]; then
        print_ok "Web UI: Truy cap OK (HTTP $web_status)"
    else
        print_warn "Web UI: HTTP $web_status"
    fi

    # 3. Check internal port
    echo -e "\n${BOLD}3. Internal Port:${NC}"
    local target_port
    if [ "$SERVER_MODE" = "stream" ]; then
        target_port=$STREAM_PORT
    else
        target_port=$WEB_PORT
    fi
    if curl -s "http://127.0.0.1:$target_port" &>/dev/null; then
        print_ok "Port $target_port (${SERVER_MODE:-web}): OK"
    else
        print_err "Port $target_port: Khong mo"
    fi

    # 4. Server IP info
    echo -e "\n${BOLD}4. Thong tin ket noi:${NC}"
    local server_ip
    server_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    echo -e "  URL: ${BOLD}http://${server_ip}:${proxy_port}${NC}"

    echo ""
    print_ok "Test hoan tat!"
}

# === LENH: UPDATE ===
cmd_update() {
    load_config
    print_step "*" "Cap nhat VieNeu-TTS..."

    if [ ! -d "$INSTALL_DIR/.git" ]; then
        print_err "Khong tim thay VieNeu-TTS tai $INSTALL_DIR"
        exit 1
    fi

    cd "$INSTALL_DIR"
    git pull --ff-only
    export PATH="$HOME/.local/bin:$PATH"
    uv sync

    print_ok "Cap nhat thanh cong. Khoi dong lai server:"
    echo "  bash install.sh stop && bash install.sh start"
}

# === LENH: KEEP-ALIVE ===
cmd_keepalive() {
    if pgrep -f "keep-alive-tts.sh" &>/dev/null; then
        print_ok "Keep-alive dang chay."
        pgrep -fa "keep-alive-tts.sh"
    else
        if [ -f /workspaces/keep-alive-tts.sh ]; then
            nohup /workspaces/keep-alive-tts.sh &>/dev/null &
            print_ok "Da bat keep-alive (PID: $!)"
        else
            print_err "Khong tim thay /workspaces/keep-alive-tts.sh"
            echo "  Chay: bash install.sh install de tao lai."
        fi
    fi
}

# === LENH: STARTUP ===
cmd_startup() {
    if [ -f /workspaces/start-vieneu-tts.sh ]; then
        echo "Dang chay startup script..."
        bash /workspaces/start-vieneu-tts.sh
        print_ok "Startup hoan tat."
    else
        print_err "Khong tim thay startup script."
        echo "  Chay: bash install.sh install de tao lai."
    fi
}

# === LENH: UNINSTALL ===
cmd_uninstall() {
    echo -e "${RED}${BOLD}Ban chac chan muon go cai dat VieNeu-TTS?${NC}"
    echo "Nhan Ctrl+C de huy, Enter de tiep tuc..."
    read -r

    cmd_stop

    # Remove Nginx config
    sudo rm -f /etc/nginx/sites-available/vieneu-tts
    sudo rm -f /etc/nginx/sites-enabled/vieneu-tts
    sudo nginx -s reload 2>/dev/null || true

    # Remove scripts
    rm -f /workspaces/start-vieneu-tts.sh
    rm -f /workspaces/keep-alive-tts.sh

    # Remove config
    sudo rm -rf "$CONFIG_DIR"

    # Remove bashrc entries
    if [ -f "$HOME/.bashrc" ]; then
        sed -i '/# === VieNeu-TTS Auto-Start ===/,/# === End VieNeu-TTS ===/d' "$HOME/.bashrc"
    fi

    # Remove VieNeu-TTS (keep if user wants)
    echo "Xoa thu muc VieNeu-TTS ($INSTALL_DIR)? [y/N]"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        print_ok "Da xoa $INSTALL_DIR"
    fi

    print_ok "Go cai dat hoan tat."
}

# === MAIN ===
case "${1:-}" in
    install)
        shift
        cmd_install "$@"
        ;;
    start)
        shift
        cmd_start "$@"
        ;;
    stop)
        cmd_stop
        ;;
    status)
        cmd_status
        ;;
    test)
        cmd_test
        ;;
    update)
        cmd_update
        ;;
    keep-alive)
        cmd_keepalive
        ;;
    startup)
        cmd_startup
        ;;
    uninstall)
        cmd_uninstall
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        print_err "Lenh khong hop le: $1"
        usage
        exit 1
        ;;
esac
