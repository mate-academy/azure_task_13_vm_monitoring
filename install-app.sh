#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

REPOSITORY_URL="https://github.com/aleksandrmajlo/azure_task_13_vm_monitoring.git"
REPOSITORY_BRANCH="azure-majlo"
TEMP_DIRECTORY="/tmp/azure_task_13_vm_monitoring"
APP_DIRECTORY="/app"

wait_for_apt() {
    while \
        fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
        fuser /var/cache/apt/archives/lock >/dev/null 2>&1
    do
        echo "Waiting for another apt process..."
        sleep 5
    done
}

echo "Updating package information..."

update_success=false

for attempt in 1 2 3 4 5
do
    wait_for_apt

    if apt-get update \
        -o APT::Update::Post-Invoke-Success::=
    then
        update_success=true
        break
    fi

    echo "apt-get update failed. Retrying..."
    sleep 15
done

if [ "$update_success" != "true" ]; then
    echo "Unable to update package information."
    exit 1
fi

echo "Installing required packages..."

install_success=false

for attempt in 1 2 3 4 5
do
    wait_for_apt

    if apt-get install -yq python3-pip git
    then
        install_success=true
        break
    fi

    echo "Package installation failed. Retrying..."
    sleep 15
done

if [ "$install_success" != "true" ]; then
    echo "Unable to install required packages."
    exit 1
fi

echo "Downloading application..."

rm -rf "$TEMP_DIRECTORY"
rm -rf "$APP_DIRECTORY"

git clone \
    --branch "$REPOSITORY_BRANCH" \
    --single-branch \
    "$REPOSITORY_URL" \
    "$TEMP_DIRECTORY"

mkdir -p "$APP_DIRECTORY"
cp -r "$TEMP_DIRECTORY/app/." "$APP_DIRECTORY/"

chmod +x "$APP_DIRECTORY/start.sh"

echo "Configuring todoapp service..."

mv "$APP_DIRECTORY/todoapp.service" \
    /etc/systemd/system/todoapp.service

systemctl daemon-reload
systemctl enable todoapp
systemctl restart todoapp

echo "Application installation completed."