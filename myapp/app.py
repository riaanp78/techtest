from flask import Flask, render_template, request
import psycopg2
from psycopg2 import pool
import configparser
import os
from datetime import datetime
import re

app = Flask(__name__)

# Load configuration from config.ini
config = configparser.ConfigParser()
config_path = '/opt/app/dummyapp/config.ini'
if not os.path.exists(config_path):
    raise FileNotFoundError(f"Configuration file {config_path} not found")
config.read(config_path)

# Get Postgres connection details
db_host = config['postgres']['host']
db_password = config['postgres']['password']
db_user = config['postgres']['user']
db_name = config['postgres']['database']
db_port = config['postgres']['port']

# PostgreSQL connection pool
db_pool = psycopg2.pool.SimpleConnectionPool(
    1, 20,
    user=db_user,
    password=db_password,
    host=db_host,
    port=db_port,
    database=db_name
)

def mask_ip(ip: str) -> str:
    """Mask IPv4 addresses by keeping only the first 2 octets, 
    obfuscating the rest. Example: 192.168.xxx.xxx"""
    if re.match(r'^\d{1,3}(\.\d{1,3}){3}$', ip):  # IPv4
        parts = ip.split('.')
        return f"{parts[0]}.{parts[1]}.xxx.xxx"
    return ip  # leave IPv6 or unknown as is

@app.route('/')
def index():
    conn = db_pool.getconn()
    try:
        cur = conn.cursor()

        # Capture visitor IP (via proxy headers if present)
        if request.headers.get("X-Forwarded-For"):
            visitor_ip = request.headers.get("X-Forwarded-For").split(",")[0].strip()
        else:
            visitor_ip = request.remote_addr

        visitor_ip = mask_ip(visitor_ip)

        user_agent = request.headers.get("User-Agent", "Unknown")

        # Create table if not exists
        cur.execute("""
            CREATE TABLE IF NOT EXISTS visits (
                id SERIAL PRIMARY KEY,
                ip VARCHAR(50),
                user_agent TEXT,
                ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Insert masked IP, user agent, timestamp
        cur.execute(
            "INSERT INTO visits (ip, user_agent, ts) VALUES (%s, %s, %s)",
            (visitor_ip, user_agent, datetime.utcnow())
        )
        conn.commit()

        # Fetch logs (latest 100)
        cur.execute("SELECT ip, ts, user_agent FROM visits ORDER BY ts DESC LIMIT 100")
        visits = cur.fetchall()

        # Count IPv4 entries only (masked pattern check)
        cur.execute("SELECT COUNT(*) FROM visits WHERE ip ~ '^[0-9]+\\.[0-9]+\\.xxx\\.xxx$'")
        ipv4_count = cur.fetchone()[0]

        cur.close()
        return render_template('index.html', visits=visits, ipv4_count=ipv4_count)
    finally:
        db_pool.putconn(conn)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
