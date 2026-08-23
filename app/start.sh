#! /bin/bash

set -e

cd /app

# Create a symlink to the folder with VM extension logs, so we can
# validate that azure monitor agent is sending metrics by checking
# the Azure Monitor Agent log /var/opt/microsoft/azuremonitoragent/log/mdsd.info
mkdir -p /app/todolist/static/files
ln -sfn /var/opt/microsoft/azuremonitoragent /app/todolist/static/files/azuremonitoragent

/app/.venv/bin/python manage.py migrate
exec /app/.venv/bin/python manage.py runserver 0.0.0.0:8080