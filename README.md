# 🚀 Shell Scripts

A collection of Bash scripts, automation utilities, and configuration resources for:

- 🐧 Linux Administration
- ☸️ Kubernetes Operations
- 🔧 Server Onboarding
- 🔐 SSL Certificate Management
- ☁️ Cloud Image Virtual Machines
- 📢 Dynamic MOTD Configuration

---

## 📖 About

This repository contains infrastructure-focused shell scripts used to automate common operational and administrative tasks.

The goals of this repository are:

- Reduce manual effort
- Standardize deployments
- Improve operational consistency
- Accelerate troubleshooting
- Promote reusable automation
- Simplify infrastructure management

---

## 📂 Repository Structure

```text
shell-script/
├── kubernetes/
├── motd-message/
├── server-onboarding/
├── vm-from-cloud-images/
│   └── vm-tools/
├── copy-ssl-from-remote.sh
└── README.md
```

---

## ☸️ Kubernetes

Scripts and supporting resources related to Kubernetes administration.

Typical use cases:

- Host preparation
- Cluster validation
- Health checks
- Runtime validation
- Troubleshooting
- Operational automation

---

## 🖥️ Server Onboarding

Scripts used to prepare newly deployed Linux servers.

Tasks may include:

- Package installation
- System updates
- User creation
- SSH configuration
- Security configuration
- Environment preparation

---

## 📢 MOTD Configuration

Dynamic Message of the Day configurations for Linux systems.

Typical information displayed:

- Hostname
- Operating System
- Uptime
- CPU Information
- Memory Usage
- Disk Usage
- Network Information

---

## 🔐 SSL Certificate Management

Utilities used to simplify SSL certificate migration and transfer.

Features:

- Copy certificates from remote systems
- Backup certificate files
- Certificate migration workflows
- Validation and verification tasks

---

## ☁️ Cloud VM Tools

Resources for preparing virtual machines deployed from cloud images.

Common tasks:

- Initial VM configuration
- Guest tool preparation
- Environment standardization
- Post-deployment configuration

---

## 🏗️ Typical Workflow

```text
Deploy Server
     │
     ▼
Run Onboarding Script
     │
     ▼
Install Required Packages
     │
     ▼
Configure Users & SSH
     │
     ▼
Apply Security Settings
     │
     ▼
Configure MOTD
     │
     ▼
Production Ready
```

---

## ✅ Recommended Validation Process

Before running any script:

1. Review the source code.
2. Validate syntax.

```bash
bash -n script.sh
```

3. Run ShellCheck.

```bash
shellcheck script.sh
```

4. Test in a lab environment.
5. Back up existing configuration.
6. Execute the script.
7. Validate the results.
8. Verify idempotency.

---

## 🧰 Requirements

Common requirements include:

- Linux Operating System
- Bash
- Standard GNU/Linux utilities
- Network connectivity
- sudo privileges (where required)

Kubernetes scripts may additionally require:

- kubectl
- kubeadm
- kubelet
- Compatible container runtime

---

## 🔒 Security Best Practices

- Never commit secrets
- Never commit private keys
- Never commit kubeconfig files
- Review scripts before execution
- Follow least privilege principles
- Back up configurations before modification
- Test changes in non-production environments

---

## 🌍 Supported Platforms

The repository primarily targets:

- Ubuntu
- Debian
- Fedora
- Rocky Linux
- AlmaLinux
- Cloud-hosted Linux systems

Compatibility varies by script.

---

## 🤝 Contributing

Contributions and improvements are welcome.

Example workflow:

```bash
git checkout -b feature/my-change
git add .
git commit -m "Describe change"
git push origin feature/my-change
```

---

## 🗺️ Roadmap

- Kubernetes health reporting
- SSL expiration monitoring
- Server inventory reporting
- GitHub Actions validation
- Enhanced logging
- Additional Linux distribution support

---

## 👨‍💻 Author

**Raj Patel**

Infrastructure Managed Services Senior Analyst

Linux • Windows Server • VMware • Kubernetes • Automation

GitHub: https://github.com/iamraj-patel

---

⭐ If you find these scripts useful, consider starring the repository.
