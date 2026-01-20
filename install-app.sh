#!/bin/bash

apt-get update -yq
apt-get install python3-pip python3-venv git -yq

rm -rf /app
mkdir -p /app

cd /tmp
rm -rf azure_task_13_vm_monitoring
git clone https://github.com/whatislavx/azure_task_13_vm_monitoring.git

find /tmp/azure_task_13_vm_monitoring/app -type f -exec sed -i 's/\r$//' {} +

cp -r /tmp/azure_task_13_vm_monitoring/app/* /app/

mv /app/todoapp.service /etc/systemd/system/
chmod +x /app/start.sh

chown -R id010806:id010806 /app
chmod -R 755 /app

systemctl daemon-reload
systemctl enable todoapp
systemctl start todoapp

rm -rf /tmp/azure_task_13_vm_monitoring