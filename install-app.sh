#!/bin/bash

# Update packages
sudo apt-get update

# Install git
sudo apt-get install -y git

# Install Node.js
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt-get install -y nodejs

# Clone the repository
git clone https://github.com/Yevgene-DP/azure_task_13_vm_monitoring.git /home/azureuser/app

# Navigate to app directory
cd /home/azureuser/app

# Install dependencies
npm install

# Start the application
npm start &