#!/bin/bash

apt-get update -yq
apt-get install python3-pip python3-venv git -yq

rm -rf /app
mkdir /app

cd /tmp
rm -rf azure_task_12_deploy_app_with_vm_extention
git clone https://github.com/mate-academy/azure_task_13_vm_monitoring.git

find /tmp/azure_task_12_deploy_app_with_vm_extention/app -type f -exec sed -i 's/\r$//' {} +

cp -r /tmp/azure_task_12_deploy_app_with_vm_extention/app/* /app/

mv /app/todoapp.service /etc/systemd/system/

chmod +x /app/start.sh

systemctl daemon-reload
systemctl start todoapp
systemctl enable todoapp

rm -rf /tmp/azure_task_12_deploy_app_with_vm_extention
