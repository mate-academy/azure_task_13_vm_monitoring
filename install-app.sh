#!/bin/bash

# Script to silently install and start the todo web app on the virtual machine. 
# Note that all commands bellow are without sudo - that's because extention mechanism 
# runs scripts under root user. 

# install system updates and isntall git/python3 packages using apt. '-yq' flags are
# used to suppress any interactive prompts - we won't be able to confirm operation
# when running the script as VM extention.
apt-get update -yq
apt-get install git python3 python3-venv -yq

# Create a directory for the app and download the files.
mkdir /app
git clone https://github.com/prostoponchik/azure_task_13_vm_monitoring.git
cp -r azure_task_13_vm_monitoring/app/* /app

# create a virtual environment and install app dependencies into it once,
# at deploy time - Ubuntu 24.04 blocks system-wide pip installs (PEP 668),
# and dependencies shouldn't be re-installed on every service start anyway.
python3 -m venv /app/.venv
/app/.venv/bin/pip install -r /app/requirements.txt

# create a service for the app via systemctl and start the app
mv /app/todoapp.service /etc/systemd/system/
systemctl daemon-reload
systemctl start todoapp
systemctl enable todoapp