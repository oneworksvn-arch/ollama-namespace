#!/bin/bash
# ==============================================================================
#  OLLAMA API GATEWAY - SCRIPT CAI DAT TU DONG
#  Cai dat Ollama + Nginx Reverse Proxy chuan OpenAI API voi API Key bao mat
#  Ho tro: Devbox / Docker Container / VPS (khong can systemd, khong can Database)
# ==============================================================================

set -e

# --- MAU SAC HIEN THI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- CAU HINH MAC DINH (co the thay doi bang tham so) ---
DEFAULT_MODEL="qwen2.5:3b"
API_KEY="sk-my-awesome-key-2026"
API_PORT=4000
OLLAMA_PORT=11434

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
    echo "   OLLAMA API GATEWAY INSTALLER"
    echo "   Bien Ollama thanh OpenAI-compatible API voi API Key bao mat"
    echo "  ============================================================"
    echo -e "${NC}"
}

usage() {
    echo -e "${BOLD}Su dung:${NC}"
    echo ""
    echo "  ${BOLD}Cai dat day du:${NC}"
    echo "    ./install.sh install [--model MODEL] [--key API_KEY] [--port PORT]"
    echo ""
    echo "  ${BOLD}Doi model:${NC}"
    echo "    ./install.sh change-model MODEL_NAME"
    echo ""
    echo "  ${BOLD}Doi API Key:${NC}"
    echo "    ./install.sh change-key NEW_API_KEY"
    echo ""
    echo "  ${BOLD}Xem trang thai:${NC}"
    echo "    ./install.sh status"
    echo ""
    echo "  ${BOLD}Khoi dong lai Nginx:${NC}"
    echo "    ./install.sh restart"
    echo ""
    echo "  ${BOLD}Dung dich vu:${NC}"
    echo "    ./install.sh stop"
    echo ""
    echo "  ${BOLD}Xem danh sach model da tai:${NC}"
    echo "    ./install.sh list-models"
    echo ""
    echo "  ${BOLD}Tai them model moi:${NC}"
    echo "    ./install.sh pull MODEL_NAME"
    echo ""
    echo "  ${BOLD}Xoa model:${NC}"
    echo "    ./install.sh remove-model MODEL_NAME"
    echo ""
    echo "  ${BOLD}Test ket noi:${NC}"
    echo "    ./install.sh test [MODEL_NAME]"
    echo ""
    echo "  ${BOLD}Hien thi thong tin cau hinh:${NC}"
    echo "    ./install.sh info"
    echo ""
    echo -e "${BOLD}Vi du:${NC}"
    echo "  ./install.sh install --model qwen2.5:1.5b --key sk-mykey-123 --port 4000"
    echo "  ./install.sh change-model llama3.2:1b"
    echo "  ./install.sh pull gemma2:2b"
    echo "  ./install.sh test qwen2.5:3b"
    echo ""
    echo -e "${BOLD}Model khuyen dung (chay tot tren CPU, ho tro tieng Viet):${NC}"
    echo "  qwen2.5:0.5b   - Sieu nhe, nhanh nhat (0.5B tham so)"
    echo "  qwen2.5:1.5b   - Can bang toc do va chat luong (1.5B tham so)"
    echo "  qwen2.5:3b     - Chat luong tot, can nhieu RAM hon (3B tham so)"
    echo "  qwen2.5:7b     - Chat luong cao, can >= 8GB RAM (7B tham so)"
    echo "  gemma2:2b      - Google, nhe va nhanh (2B tham so)"
    echo ""
}

# --- LAY IP TAILSCALE (neu co) ---
get_tailscale_ip() {
    if command -v tailscale &>/dev/null; then
        tailscale ip -4 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# --- LAY IP CHINH CUA MAY ---
get_server_ip() {
    local ts_ip
    ts_ip=$(get_tailscale_ip)
    if [ -n "$ts_ip" ]; then
        echo "$ts_ip"
    else
        hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1"
    fi
}

# --- DOC CAU HINH HIEN TAI TU FILE ---
CONFIG_FILE="/etc/ollama-gateway/config"

save_config() {
    sudo mkdir -p /etc/ollama-gateway
    sudo bash -c "cat > $CONFIG_FILE" << EOF
API_KEY=$API_KEY
API_PORT=$API_PORT
DEFAULT_MODEL=$DEFAULT_MODEL
OLLAMA_PORT=$OLLAMA_PORT
EOF
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# --- CAI DAT OLLAMA ---
install_ollama() {
    print_step "1/6" "Kiem tra va cai dat Ollama..."

    if command -v ollama &>/dev/null; then
        print_ok "Ollama da duoc cai dat san."
        ollama --version 2>/dev/null || true
    else
        echo "Dang tai va cai dat Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
        print_ok "Cai dat Ollama thanh cong."
    fi

    # Dam bao Ollama dang chay
    if ! pgrep -f "ollama serve" &>/dev/null; then
        echo "Khoi dong Ollama server..."
        ollama serve > /tmp/ollama-serve.log 2>&1 &
        sleep 3
    fi

    # Kiem tra Ollama da san sang
    local retries=0
    while ! curl -s http://127.0.0.1:$OLLAMA_PORT/api/tags &>/dev/null; do
        retries=$((retries + 1))
        if [ $retries -ge 15 ]; then
            print_err "Khong the ket noi den Ollama sau 15 lan thu. Kiem tra lai bang: ollama serve"
            exit 1
        fi
        echo "Dang cho Ollama khoi dong... (lan $retries)"
        sleep 2
    done
    print_ok "Ollama server dang chay tai port $OLLAMA_PORT."
}

# --- TAI MODEL ---
pull_model() {
    local model_name="$1"
    print_step "2/6" "Tai model: $model_name ..."

    if ollama list 2>/dev/null | grep -q "$model_name"; then
        print_ok "Model $model_name da co san."
    else
        echo "Dang tai $model_name (co the mat vai phut tuy kich thuoc)..."
        ollama pull "$model_name"
        if [ $? -eq 0 ]; then
            print_ok "Tai model $model_name thanh cong."
        else
            print_err "Khong the tai model $model_name. Kiem tra ten model va ket noi mang."
            exit 1
        fi
    fi
}

# --- CAI DAT NGINX ---
install_nginx() {
    print_step "3/6" "Cai dat Nginx..."

    if command -v nginx &>/dev/null; then
        print_ok "Nginx da duoc cai dat san."
    else
        sudo apt-get update -qq
        sudo apt-get install -y -qq nginx
        print_ok "Cai dat Nginx thanh cong."
    fi
}

# --- CAU HINH NGINX REVERSE PROXY ---
configure_nginx() {
    print_step "4/6" "Cau hinh Nginx API Gateway (port $API_PORT, API Key bao mat)..."

    # Dung Nginx cu neu dang chay
    stop_nginx_quiet

    sudo bash -c "cat > /etc/nginx/sites-available/default" << 'NGINX_EOF'
server {
    listen __API_PORT__;
    client_max_body_size 100M;

    # --- CHAT COMPLETIONS (chuan OpenAI) ---
    location /v1/chat/completions {
        if ($http_authorization != "Bearer __API_KEY__") {
            return 401 '{"error": {"message": "Unauthorized: API Key khong hop le.", "type": "invalid_request_error", "code": "401"}}';
        }
        proxy_pass http://127.0.0.1:__OLLAMA_PORT__/api/chat;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Stream: bat chay tu tung tu, khong doi gom du moi gui
        proxy_buffering off;
        proxy_cache off;
        proxy_set_header Connection '';
        proxy_http_version 1.1;
        chunked_transfer_encoding on;
        proxy_read_timeout 10m;
        proxy_send_timeout 10m;
    }

    # --- COMPLETIONS (text completions) ---
    location /v1/completions {
        if ($http_authorization != "Bearer __API_KEY__") {
            return 401 '{"error": {"message": "Unauthorized", "type": "invalid_request_error", "code": "401"}}';
        }
        proxy_pass http://127.0.0.1:__OLLAMA_PORT__/api/generate;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_buffering off;
        proxy_cache off;
        proxy_http_version 1.1;
        proxy_read_timeout 10m;
        proxy_send_timeout 10m;
    }

    # --- FETCH MODEL LIST (tu dong nhan dien danh sach model) ---
    location /v1/models {
        if ($http_authorization != "Bearer __API_KEY__") {
            return 401 '{"error": {"message": "Unauthorized", "type": "invalid_request_error", "code": "401"}}';
        }
        proxy_pass http://127.0.0.1:__OLLAMA_PORT__/api/tags;
        proxy_set_header Host $host;
    }

    # --- EMBEDDINGS ---
    location /v1/embeddings {
        if ($http_authorization != "Bearer __API_KEY__") {
            return 401 '{"error": {"message": "Unauthorized", "type": "invalid_request_error", "code": "401"}}';
        }
        proxy_pass http://127.0.0.1:__OLLAMA_PORT__/api/embed;
        proxy_set_header Host $host;
        proxy_set_header Content-Type "application/json";
        proxy_buffering off;
        proxy_read_timeout 10m;
    }

    # --- HEALTH CHECK (khong can key) ---
    location /health {
        return 200 '{"status": "ok"}';
        add_header Content-Type application/json;
    }

    # --- CHAN TAT CA DUONG DAN KHAC ---
    location / {
        return 403 '{"error": {"message": "Access Denied: Chi phuc vu API Gateway.", "type": "access_denied", "code": "403"}}';
        add_header Content-Type application/json;
    }
}
NGINX_EOF

    # Thay the placeholder bang gia tri thuc te
    sudo sed -i "s/__API_PORT__/$API_PORT/g" /etc/nginx/sites-available/default
    sudo sed -i "s/__API_KEY__/$API_KEY/g" /etc/nginx/sites-available/default
    sudo sed -i "s/__OLLAMA_PORT__/$OLLAMA_PORT/g" /etc/nginx/sites-available/default

    # Kiem tra cau hinh Nginx hop le
    if sudo nginx -t 2>/dev/null; then
        print_ok "Cau hinh Nginx hop le."
    else
        print_err "Cau hinh Nginx bi loi. Kiem tra lai file /etc/nginx/sites-available/default"
        sudo nginx -t
        exit 1
    fi
}

# --- KHOI DONG NGINX (tuong thich Devbox/Container khong co systemd) ---
stop_nginx_quiet() {
    sudo nginx -s stop 2>/dev/null || true
    sudo pkill -f nginx 2>/dev/null || true
    sleep 1
}

start_nginx() {
    print_step "5/6" "Khoi dong Nginx Gateway..."

    # Thu cac phuong phap khoi dong theo thu tu uu tien
    if sudo service nginx restart 2>/dev/null; then
        print_ok "Nginx khoi dong thanh cong (service)."
    elif sudo nginx 2>/dev/null; then
        print_ok "Nginx khoi dong thanh cong (direct)."
    else
        print_err "Khong the khoi dong Nginx."
        exit 1
    fi

    # Xac nhan port dang listen
    sleep 1
    if ss -tulpn 2>/dev/null | grep -q ":$API_PORT" || netstat -tulpn 2>/dev/null | grep -q ":$API_PORT"; then
        print_ok "Nginx dang lang nghe tai port $API_PORT."
    else
        print_warn "Khong xac nhan duoc port $API_PORT. Kiem tra: sudo ss -tulpn | grep $API_PORT"
    fi
}

# --- HIEN THI THONG TIN CAU HINH ---
show_info() {
    local server_ip
    server_ip=$(get_server_ip)

    echo -e "\n${GREEN}${BOLD}========================================================================${NC}"
    echo -e "${GREEN}${BOLD}  CAU HINH HOAN TAT - THONG TIN KET NOI API GATEWAY${NC}"
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
    echo -e ""
    echo -e "  ${BOLD}Base URL:${NC}    http://${server_ip}:${API_PORT}/v1"
    echo -e "  ${BOLD}API Key:${NC}     ${API_KEY}"
    echo -e "  ${BOLD}Model:${NC}       ${DEFAULT_MODEL}"
    echo -e ""
    echo -e "  ${BOLD}Endpoints ho tro:${NC}"
    echo -e "    POST /v1/chat/completions   - Chat (chuan OpenAI)"
    echo -e "    POST /v1/completions        - Text completions"
    echo -e "    GET  /v1/models             - Danh sach model"
    echo -e "    POST /v1/embeddings         - Embedding vectors"
    echo -e "    GET  /health                - Health check (khong can key)"
    echo -e ""
    echo -e "  ${BOLD}Tuong thich voi:${NC} Dify, LobeChat, NextChat, ChatBox, CodeGPT,"
    echo -e "                   Open WebUI, Page Assist, GoClaw, va moi ung"
    echo -e "                   dung ho tro OpenAI API."
    echo -e ""
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
    echo -e ""
    echo -e "  ${BOLD}Vi du test bang curl:${NC}"
    echo -e "  curl -s http://${server_ip}:${API_PORT}/v1/chat/completions \\"
    echo -e "    -H 'Authorization: Bearer ${API_KEY}' \\"
    echo -e "    -H 'Content-Type: application/json' \\"
    echo -e "    -d '{\"model\":\"${DEFAULT_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Xin chao!\"}],\"stream\":false}'"
    echo -e ""
    echo -e "  ${BOLD}Vi du test bang PowerShell:${NC}"
    echo -e "  Invoke-RestMethod -Uri 'http://${server_ip}:${API_PORT}/v1/chat/completions' \`"
    echo -e "    -Method Post \`"
    echo -e "    -Headers @{ 'Authorization' = 'Bearer ${API_KEY}' } \`"
    echo -e "    -ContentType 'application/json' \`"
    echo -e "    -Body '{\"model\":\"${DEFAULT_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Xin chao!\"}],\"stream\":false}'"
    echo -e ""
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
}

# --- DOI MODEL ---
cmd_change_model() {
    local new_model="$1"
    if [ -z "$new_model" ]; then
        print_err "Vui long chi dinh ten model. Vi du: ./install.sh change-model qwen2.5:1.5b"
        exit 1
    fi

    load_config

    # Tai model neu chua co
    if ! ollama list 2>/dev/null | grep -q "$new_model"; then
        echo "Model $new_model chua co. Dang tai ve..."
        ollama pull "$new_model"
    fi

    DEFAULT_MODEL="$new_model"
    save_config
    print_ok "Da doi model mac dinh thanh: $new_model"
    show_info
}

# --- DOI API KEY ---
cmd_change_key() {
    local new_key="$1"
    if [ -z "$new_key" ]; then
        print_err "Vui long chi dinh API key moi. Vi du: ./install.sh change-key sk-newkey-789"
        exit 1
    fi

    load_config
    API_KEY="$new_key"
    save_config
    configure_nginx
    start_nginx
    print_ok "Da doi API Key thanh: $new_key"
    show_info
}

# --- TRANG THAI ---
cmd_status() {
    load_config
    echo -e "\n${BOLD}=== TRANG THAI HE THONG ===${NC}\n"

    # Ollama
    if pgrep -f "ollama" &>/dev/null; then
        print_ok "Ollama: DANG CHAY"
    else
        print_err "Ollama: KHONG CHAY"
    fi

    # Nginx
    if pgrep -f "nginx" &>/dev/null; then
        print_ok "Nginx:  DANG CHAY"
    else
        print_err "Nginx:  KHONG CHAY"
    fi

    # Port
    if ss -tulpn 2>/dev/null | grep -q ":$API_PORT" || netstat -tulpn 2>/dev/null | grep -q ":$API_PORT"; then
        print_ok "Port $API_PORT: DANG LANG NGHE"
    else
        print_err "Port $API_PORT: KHONG MO"
    fi

    echo ""

    # Danh sach model
    echo -e "${BOLD}Model da tai:${NC}"
    ollama list 2>/dev/null || echo "  (Khong the ket noi Ollama)"

    echo ""
    echo -e "${BOLD}Model mac dinh:${NC} $DEFAULT_MODEL"
    echo -e "${BOLD}API Key:${NC}        $API_KEY"
    echo -e "${BOLD}API Port:${NC}       $API_PORT"
}

# --- TEST KET NOI ---
cmd_test() {
    load_config
    local test_model="${1:-$DEFAULT_MODEL}"
    local server_ip
    server_ip=$(get_server_ip)

    echo -e "\n${BOLD}=== TEST KET NOI API GATEWAY ===${NC}\n"
    echo "Model: $test_model"
    echo "URL:   http://${server_ip}:${API_PORT}/v1/chat/completions"
    echo ""

    # Test health
    echo -n "Health check... "
    if curl -s "http://127.0.0.1:${API_PORT}/health" | grep -q "ok"; then
        print_ok "Health OK"
    else
        print_err "Health FAIL"
    fi

    # Test auth fail
    echo -n "Test API Key sai... "
    local bad_response
    bad_response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "http://127.0.0.1:${API_PORT}/v1/chat/completions" \
        -H "Authorization: Bearer wrong-key" \
        -H "Content-Type: application/json" \
        -d '{"model":"test","messages":[{"role":"user","content":"test"}]}')
    if [ "$bad_response" = "401" ]; then
        print_ok "Chan dung key sai (401)"
    else
        print_warn "Response code: $bad_response (mong doi 401)"
    fi

    # Test fetch models
    echo -n "Test fetch models... "
    if curl -s "http://127.0.0.1:${API_PORT}/v1/models" \
        -H "Authorization: Bearer ${API_KEY}" | grep -q "models\|name"; then
        print_ok "Fetch models OK"
    else
        print_warn "Fetch models khong tra ve du lieu mong doi"
    fi

    # Test chat
    echo -n "Test chat voi model $test_model... "
    local chat_response
    chat_response=$(curl -s --max-time 120 \
        -X POST "http://127.0.0.1:${API_PORT}/v1/chat/completions" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"${test_model}\",\"messages\":[{\"role\":\"user\",\"content\":\"Tra loi ngan gon: 2+2 bang bao nhieu?\"}],\"stream\":false}")

    if echo "$chat_response" | grep -q "message\|response\|content"; then
        print_ok "Chat thanh cong!"
        echo -e "\n${BOLD}Phan hoi tu AI:${NC}"
        echo "$chat_response" | python3 -m json.tool 2>/dev/null || echo "$chat_response"
    else
        print_err "Chat that bai."
        echo "Response: $chat_response"
    fi
}

# --- KHOI DONG LAI ---
cmd_restart() {
    load_config

    echo -e "\n${BOLD}Khoi dong lai he thong...${NC}"

    # Restart Nginx
    stop_nginx_quiet
    configure_nginx
    start_nginx

    print_ok "He thong da khoi dong lai."
}

# --- DUNG DICH VU ---
cmd_stop() {
    echo -e "\n${BOLD}Dung tat ca dich vu...${NC}"
    stop_nginx_quiet
    print_ok "Nginx da dung."
    echo "(Ollama van chay de phuc vu cac ung dung khac. Dung 'pkill ollama' neu muon tat.)"
}

# --- DANH SACH MODEL ---
cmd_list_models() {
    echo -e "\n${BOLD}Danh sach model da tai:${NC}\n"
    ollama list 2>/dev/null || echo "Khong the ket noi Ollama."
}

# --- TAI MODEL ---
cmd_pull() {
    local model_name="$1"
    if [ -z "$model_name" ]; then
        print_err "Vui long chi dinh ten model. Vi du: ./install.sh pull qwen2.5:1.5b"
        exit 1
    fi
    echo "Dang tai model: $model_name ..."
    ollama pull "$model_name"
    print_ok "Tai $model_name thanh cong."
}

# --- XOA MODEL ---
cmd_remove_model() {
    local model_name="$1"
    if [ -z "$model_name" ]; then
        print_err "Vui long chi dinh ten model. Vi du: ./install.sh remove-model qwen2.5:3b"
        exit 1
    fi
    echo "Dang xoa model: $model_name ..."
    ollama rm "$model_name"
    print_ok "Da xoa $model_name."
}

# ==============================================================================
#  CAI DAT DAY DU
# ==============================================================================
cmd_install() {
    # Parse tham so
    while [[ $# -gt 0 ]]; do
        case $1 in
            --model) DEFAULT_MODEL="$2"; shift 2 ;;
            --key)   API_KEY="$2"; shift 2 ;;
            --port)  API_PORT="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    print_banner
    echo -e "Cau hinh:"
    echo -e "  Model:    ${BOLD}$DEFAULT_MODEL${NC}"
    echo -e "  API Key:  ${BOLD}$API_KEY${NC}"
    echo -e "  API Port: ${BOLD}$API_PORT${NC}"
    echo ""

    # Step 1: Cai Ollama
    install_ollama

    # Step 2: Tai model
    pull_model "$DEFAULT_MODEL"

    # Step 3: Cai Nginx
    install_nginx

    # Step 4: Cau hinh Nginx
    configure_nginx

    # Step 5: Khoi dong Nginx
    start_nginx

    # Step 6: Luu cau hinh
    print_step "6/6" "Luu cau hinh he thong..."
    save_config
    print_ok "Cau hinh da duoc luu."

    # Hien thi thong tin
    show_info
}

# ==============================================================================
#  XU LY LENH CHINH
# ==============================================================================
COMMAND="${1:-}"

case "$COMMAND" in
    install)
        shift
        cmd_install "$@"
        ;;
    change-model)
        cmd_change_model "$2"
        ;;
    change-key)
        cmd_change_key "$2"
        ;;
    status)
        cmd_status
        ;;
    restart)
        cmd_restart
        ;;
    stop)
        cmd_stop
        ;;
    list-models)
        cmd_list_models
        ;;
    pull)
        cmd_pull "$2"
        ;;
    remove-model)
        cmd_remove_model "$2"
        ;;
    test)
        cmd_test "$2"
        ;;
    info)
        load_config
        show_info
        ;;
    help|--help|-h)
        usage
        ;;
    "")
        # Chay khong co tham so = cai dat voi cau hinh mac dinh
        cmd_install
        ;;
    *)
        print_err "Lenh khong hop le: $COMMAND"
        echo ""
        usage
        exit 1
        ;;
esac
