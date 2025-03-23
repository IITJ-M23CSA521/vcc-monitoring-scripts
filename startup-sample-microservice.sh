#!/bin/bash

# Update and install necessary packages
sudo apt update -y
sudo apt install -y curl git

# Install Node.js (LTS version 18)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Verify Node.js and npm
node -v
npm -v

# Clone Node.js microservice repo
git clone https://github.com/IITJ-M23CSA521/sample-microService.git /home/sample-microService

# Navigate into the project directory
cd /home/sample-microService

# Install dependencies
npm install

# Start the Node.js service (already coded to use port 5020)
# Run in background with logs
nohup npm start > app.log 2>&1 &
