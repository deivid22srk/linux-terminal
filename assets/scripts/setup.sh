#!/data/data/com.termux/files/usr/bin/bash
# This script runs inside the PRoot environment for initial setup
echo "Linux Terminal - Debian Environment"
echo "Running initial setup..."
apt-get update -qq
echo "Setup complete. You can now install packages with apt."
