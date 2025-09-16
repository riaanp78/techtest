#!/bin/bash
set -xe

# Install PostgreSQL 13
amazon-linux-extras enable postgresql13
yum install -y postgresql-server postgresql-contrib

# Initialize DB cluster
postgresql-setup --initdb --unit postgresql

# Allow listen on all interfaces
sed -i "s/^#listen_addresses =.*/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf

# Allow connections from nginx subnet (10.0.1.0/24)
cat >> /var/lib/pgsql/data/pg_hba.conf <<EOF
host    ${db_name}    ${db_user}    10.0.1.0/24    md5
EOF

# Start and enable service
systemctl enable postgresql
systemctl start postgresql

# Create database if not exists
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '${db_name}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE ${db_name};"

# Create user if not exists
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = '${db_user}'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER ${db_user} WITH PASSWORD '${db_password}';"

# Grant privileges
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};"

# SSM Agent logging
${ssm_log}
