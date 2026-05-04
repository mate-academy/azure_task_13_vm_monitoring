#!/bin/bash
set -euo pipefail
# Expose AMA logs for validate-artifacts: /static/files/azuremonitoragent/log/mdsd.info
mkdir -p /app/todolist/static/files
ln -sfn /var/opt/microsoft/azuremonitoragent /app/todolist/static/files/azuremonitoragent
cd /app
exec ./venv/bin/python manage.py runserver 0.0.0.0:8080
