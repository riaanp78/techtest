#!/bin/bash
set -xe

# Enable and install nginx
amazon-linux-extras enable nginx1
yum install -y nginx git

# Enable and install Python 3.8 + pip
amazon-linux-extras enable python3.8
yum install -y python3.8 python3.8-pip
alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 2
alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip3.8 2

# Upgrade pip & install app dependencies
pip3 install --upgrade pip
pip3 install gunicorn flask==2.3.3 psycopg2-binary configparser

# Deploy app under /opt/app/dummyapp
mkdir -p /opt/app
cd /opt/app
git clone https://${git_pat}@github.com/riaanp78/dummyapp.git dummyapp
chown -R nginx:nginx /opt/app/dummyapp

# Create config.ini using Terraform vars
cat > /opt/app/dummyapp/config.ini <<'EOF'
[postgres]
host=${db_host}
port=${db_port}
user=${db_user}
password=${db_password}
database=${db_name}
EOF
chown nginx:nginx /opt/app/dummyapp/config.ini

# Systemd service for Gunicorn (bind to 127.0.0.1:5000)
cat > /etc/systemd/system/flask-app.service <<'EOF'
[Unit]
Description=Gunicorn instance to serve Flask app
After=network.target

[Service]
User=nginx
Group=nginx
WorkingDirectory=/opt/app/dummyapp
ExecStart=/usr/bin/python3 -m gunicorn --workers 3 --bind 127.0.0.1:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flask-app
systemctl restart flask-app

# Nginx reverse proxy config
# Also basic hardening

cat > /etc/nginx/conf.d/flask.conf <<'EOF'
# rate limit: Each IP limited to 4 requests/sec (with default burst behavior).
limit_req_zone $binary_remote_addr zone=one:10m rate=4r/s;

server {
    listen 80;
    server_name _;

    # Hide Nginx server version
    server_tokens off;

    # Block user agents we don't want aka bots
    if ($http_user_agent ~* (curl|wget|httpclient|libwww|python-requests|java|nikto|sqlmap)) {
        return 403;
    }

    # Block common sensitive paths and all hidden files
    location ~* (^/(\.git|\.env|phpmyadmin|wp-admin|wp-login)) {
        deny all;
        return 404;
    }

    # Block any hidden file (e.g. /.anything)
    location ~ /\.(?!well-known) {
        deny all;
        return 404;
    }

    # Limit to GET/HEAD requests
    if ($request_method !~ ^(GET|HEAD)$) {
        return 405;
    }

    # Reverse proxy to python app
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }


}
EOF

systemctl enable nginx
systemctl restart nginx

# SSM agent logging
${ssm_log}
