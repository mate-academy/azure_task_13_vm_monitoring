#! /bin/bash 

echo "Preparing the system for a check..."
# Create a symlinc to the folder with VM extention logs, so we can
# validate that azure monitor agent is sending metrics by checking 
# the Azure Monitor Agend log /var/opt/microsoft/azuremonitoragent/log/mdsd.info
ln -s  /var/opt/microsoft /app/todolist/static/files

lsblk -o NAME,HCTL,SIZE,MOUNTPOINT > /data/app/todolist/static/files/task3.log

cd /app

python3 -m venv venv
source venv/bin/activate

pip install -r requirements.txt
python3 manage.py migrate
python3 manage.py runserver 0.0.0.0:8080
