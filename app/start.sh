#!/bin/bash

mkdir -p /app/todolist/static/files

ln -sf /var/opt/microsoft /app/todolist/static/files/

lsblk -o NAME,HCTL,SIZE,MOUNTPOINT > /app/todolist/static/files/task3.log

cd /app
python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt
python3 manage.py migrate

python3 manage.py runserver 0.0.0.0:8080