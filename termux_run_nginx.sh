#!/data/data/com.termux/files/usr/bin/bash
set -e

# ================================================================
# IP Webcam CORS reverse proxy for Termux
# nginx listens on :8081  ->  proxies to IP Webcam on :8080
# ================================================================

# 1. Update packages and install nginx
pkg update -y && pkg upgrade -y
pkg install -y nginx termux-api

NGINX_CONF="$PREFIX/etc/nginx/nginx.conf"

# 2. Back up the original config (only once)
[ -f "$NGINX_CONF" ] && [ ! -f "$NGINX_CONF.bak" ] && cp "$NGINX_CONF" "$NGINX_CONF.bak"

# 3. Write the reverse proxy config
cat << 'EOF' > "$NGINX_CONF"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout  65;

    server {
        listen       8081;
        server_name  localhost;

        # host page
        location = /monitor {
            alias /data/data/com.termux/files/home/www/baby-monitor-notify.html;
            default_type text/html;
        }
        # service worker (needed for notification popups on Android Chrome);
        # must be served here, not proxied to IP Webcam
        location = /sw.js {
            alias /data/data/com.termux/files/home/www/sw.js;
            default_type application/javascript;
            add_header Cache-Control 'no-cache';
        }
        location / {
            # --- CORS headers ---
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;

            # Answer preflight requests directly
            if ($request_method = 'OPTIONS') {
                add_header 'Access-Control-Allow-Origin' '*';
                add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
                add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
                add_header 'Access-Control-Max-Age' 1728000;
                add_header 'Content-Type' 'text/plain; charset=utf-8';
                add_header 'Content-Length' 0;
                return 204;
            }

            # --- Upstream: IP Webcam app on its default port ---
            proxy_pass http://127.0.0.1:8080;

            # Prevent duplicate CORS headers if the app sends its own
            proxy_hide_header Access-Control-Allow-Origin;

            # --- Streaming: no buffering (critical for MJPEG/audio) ---
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;

            # Standard proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
EOF

# 4. Validate config
nginx -t

# 5. Start (or reload if already running)
if pgrep -x nginx > /dev/null; then
    nginx -s reload
    echo "nginx reloaded"
else
    nginx
    echo "nginx started"
fi

# 6. Keep Android from killing the process
termux-wake-lock

# 7. Auto-start on boot (requires the Termux:Boot app from F-Droid)
mkdir -p ~/.termux/boot
cat << 'EOF' > ~/.termux/boot/start-proxy.sh
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
nginx
EOF
chmod +x ~/.termux/boot/start-proxy.sh

# 8. Summary
IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "<phone-ip>")
echo "------------------------------------------------"
echo "✅ Reverse proxy running"
echo "   Browser/HTML page  ->  http://$IP:8081"
echo "   Proxies to         ->  http://127.0.0.1:8080 (IP Webcam)"
echo "------------------------------------------------"