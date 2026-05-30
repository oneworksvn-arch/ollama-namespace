# VieNeu-TTS - Auto Install cho Namespace Devbox

Script cai dat tu dong [VieNeu-TTS](https://github.com/pnnbao97/VieNeu-TTS) tren Namespace Devbox.

## Tinh nang

- Cai dat VieNeu-TTS (Text-to-Speech tieng Viet) chi voi 1 lenh
- Ho tro 2 che do: **Web UI** (Gradio) va **Streaming API** (FastAPI)
- Nginx Reverse Proxy tu dong
- **Auto-start**: Tu dong khoi dong khi Devbox bat lai tu trang thai ngu
- **Keep-alive**: Chong Devbox bi tam dung do idle timeout
- Chay tren CPU (khong can GPU)

## Cai dat nhanh

```bash
# Clone repo
git clone https://github.com/oneworksvn-arch/vieneu-namespace.git
cd vieneu-namespace

# Cai dat voi Web UI (mac dinh)
bash install.sh install

# Hoac: Cai dat voi Streaming API
bash install.sh install --mode stream

# Hoac: Doi port proxy
bash install.sh install --port 8080
```

## Cac lenh

| Lenh | Mo ta |
|------|-------|
| `bash install.sh install` | Cai dat day du |
| `bash install.sh start` | Khoi dong server |
| `bash install.sh stop` | Dung server |
| `bash install.sh status` | Xem trang thai |
| `bash install.sh test` | Test ket noi |
| `bash install.sh update` | Cap nhat VieNeu-TTS |
| `bash install.sh keep-alive` | Bat keep-alive thu cong |
| `bash install.sh startup` | Khoi dong thu cong (auto-start) |
| `bash install.sh uninstall` | Go cai dat |

## Che do chay

### Web UI (Gradio) - Mac dinh
- Giao dien Web day du voi nhieu tinh nang
- Nhap van ban -> Nghe giong doc tieng Viet
- Ho tro clone giong noi, chon giong, podcast mode
- Port mac dinh: 7860 (proxy qua Nginx port 7000)

### Streaming API (FastAPI)
- API endpoint cho tich hop vao ung dung
- Streaming audio real-time
- Port mac dinh: 8001 (proxy qua Nginx port 7000)

## Model ho tro (CPU)

| Model | Mo ta |
|-------|-------|
| VieNeu-TTS-v2-Turbo (CPU) | Sieu nhanh, song ngu En-Vi |
| VieNeu-TTS-v2-CPU (GGUF) | Chat luong cao hon |

## Chong Devbox ngu/tam dung

Script tu dong:
1. **Keep-alive**: Tao task file trong `/.namespace/tasks/` moi 5 phut
2. **Auto-start**: Khi mo terminal, VieNeu-TTS + Nginx tu dong bat lai
3. **Auto-recovery**: Neu VieNeu-TTS bi crash, keep-alive se khoi dong lai

## Yeu cau

- Namespace Devbox (Ubuntu)
- Khong can GPU (chay tren CPU)
- RAM: 2GB+ khuyen nghi
