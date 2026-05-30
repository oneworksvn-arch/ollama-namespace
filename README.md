# Ollama API Gateway - Cài đặt nhanh

Script tự động cài đặt **Ollama + Nginx Reverse Proxy**, biến server thành OpenAI-compatible API gateway với API Key bảo mật.

## Đặc điểm

- **Một lệnh cài đặt xong** - không cần cấu hình thủ công
- **Chuẩn OpenAI API** - tương thích Dify, LobeChat, NextChat, ChatBox, CodeGPT, GoClaw, ...
- **API Key bảo mật** - chặn truy cập không có key
- **Đổi model dễ dàng** - chỉ 1 lệnh
- **Tương thích Devbox/Container** - không cần systemd, không cần Database
- **Hỗ trợ Streaming** - phản hồi tức thì từng từ

## Cài đặt nhanh

```bash
# Tải script
curl -fsSL -o install.sh https://raw.githubusercontent.com/YOUR_REPO/install.sh
chmod +x install.sh

# Cài đặt với cấu hình mặc định (model: qwen2.5:3b)
./install.sh install

# Hoặc tùy chỉnh
./install.sh install --model qwen2.5:1.5b --key sk-your-secret-key --port 4000
```

## Quản lý model

```bash
# Xem danh sách model đã tải
./install.sh list-models

# Tải thêm model mới
./install.sh pull qwen2.5:7b

# Đổi model đang dùng
./install.sh change-model qwen2.5:1.5b

# Xóa model không cần
./install.sh remove-model qwen2.5:3b
```

## Quản lý hệ thống

```bash
# Xem trạng thái
./install.sh status

# Đổi API Key
./install.sh change-key sk-new-key-456

# Test kết nối
./install.sh test

# Khởi động lại
./install.sh restart

# Dừng dịch vụ
./install.sh stop
```

## Thông tin kết nối

Sau khi cài đặt, điền vào ứng dụng chat:

| Cấu hình   | Giá trị                              |
|-------------|---------------------------------------|
| Provider    | `OpenAI Compatible` / `Custom OpenAI` |
| Base URL    | `http://<IP_SERVER>:4000/v1`          |
| API Key     | `sk-my-awesome-key-2026` (mặc định)   |
| Model       | `qwen2.5:3b` (mặc định)              |

## Model khuyên dùng (chạy tốt trên CPU, hỗ trợ Tiếng Việt)

| Model          | Kích thước | Tốc độ CPU | Tiếng Việt | Ghi chú                 |
|----------------|------------|-------------|------------|--------------------------|
| `qwen2.5:0.5b` | ~400MB     | Rất nhanh   | Tốt        | Siêu nhẹ                |
| `qwen2.5:1.5b` | ~1GB       | Nhanh       | Rất tốt    | Cân bằng tốc độ/chất lượng |
| `qwen2.5:3b`   | ~2GB       | Trung bình  | Xuất sắc   | Chất lượng cao           |
| `qwen2.5:7b`   | ~4.5GB     | Chậm        | Xuất sắc   | Cần >= 8GB RAM           |
| `gemma2:2b`     | ~1.6GB     | Nhanh       | Khá        | Model Google             |

## Endpoints hỗ trợ

| Method | Endpoint                 | Chức năng         | Cần Key |
|--------|--------------------------|-------------------|---------|
| POST   | `/v1/chat/completions`   | Chat              | Có      |
| POST   | `/v1/completions`        | Text completions  | Có      |
| GET    | `/v1/models`             | Danh sách model   | Có      |
| POST   | `/v1/embeddings`         | Embedding vectors | Có      |
| GET    | `/health`                | Health check      | Không   |
