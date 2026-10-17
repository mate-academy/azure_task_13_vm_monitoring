#!/bin/bash

set -Eeuo pipefail

REPOSITORY_ARCHIVE="https://github.com/aleksandrmajlo/azure_task_13_vm_monitoring/archive/refs/heads/azure-majlo.tar.gz"
ARCHIVE_PATH="/tmp/azure_task_13_vm_monitoring.tar.gz"
TEMP_DIRECTORY="/tmp/azure_task_13_vm_monitoring"
APP_DIRECTORY="/app"

echo "Checking Python..."

python3 --version

echo "Checking pip..."

if ! python3 -m pip --version >/dev/null 2>&1
then
    echo "Installing pip without apt..."

    python3 - <<'PYTHON'
import urllib.request

urllib.request.urlretrieve(
    "https://bootstrap.pypa.io/get-pip.py",
    "/tmp/get-pip.py",
)
PYTHON

    python3 /tmp/get-pip.py --break-system-packages
fi

echo "Downloading application..."

rm -rf "$TEMP_DIRECTORY"
rm -rf "$APP_DIRECTORY"
rm -f "$ARCHIVE_PATH"

mkdir -p "$TEMP_DIRECTORY"
mkdir -p "$APP_DIRECTORY"

python3 - <<PYTHON
import urllib.request

urllib.request.urlretrieve(
    "$REPOSITORY_ARCHIVE",
    "$ARCHIVE_PATH",
)
PYTHON

echo "Extracting application..."

tar \
    -xzf "$ARCHIVE_PATH" \
    -C "$TEMP_DIRECTORY" \
    --strip-components=1

cp -r "$TEMP_DIRECTORY/app/." "$APP_DIRECTORY/"

chmod +x "$APP_DIRECTORY/start.sh"

echo "Installing Python dependencies..."

cd "$APP_DIRECTORY"

PIP_BREAK_SYSTEM_PACKAGES=1 \
python3 -m pip install \
    --disable-pip-version-check \
    -r requirements.txt

echo "Configuring todoapp service..."

mv "$APP_DIRECTORY/todoapp.service" \
    /etc/systemd/system/todoapp.service

systemctl daemon-reload
systemctl enable todoapp
systemctl restart todoapp

echo "Application installation completed."

systemctl status todoapp --no-pager