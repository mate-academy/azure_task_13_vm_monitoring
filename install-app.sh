#!/bin/bash
set -euxo pipefail

apt-get update -yq
apt-get install -yq git python3-pip python3-venv

REPO_URL="https://github.com/NazarKulyk6/azure_task_13_vm_monitoring.git"
APP_DIR=/app
rm -rf "${APP_DIR:?}"/*
mkdir -p "$APP_DIR"

cd /tmp
rm -rf azure_task_13_vm_monitoring
git clone --depth 1 "$REPO_URL" azure_task_13_vm_monitoring
cp -r azure_task_13_vm_monitoring/app/* "$APP_DIR/"
chmod +x "$APP_DIR/start.sh"

python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"
"$APP_DIR/venv/bin/python" "$APP_DIR/manage.py" migrate --noinput

mv "$APP_DIR/todoapp.service" /etc/systemd/system/
systemctl daemon-reload
systemctl start todoapp
systemctl enable todoapp
