<div align="center">

# 🚀 Infrastructure Automation Shell Scripts

### Linux • Kubernetes • Server Onboarding • SSL Management • Cloud Image VM Tooling

Automating repetitive infrastructure tasks with Bash.

<br>

![GitHub stars](https://img.shields.io/github/stars/iamraj-patel/shell-script?style=for-the-badge)
ttps://img.shields.io/github/forks/iamraj-patel/shell-script?style=for-the-badge)
mit](https://img.shields.io/github/last-commit/iamraj-patel/shell-script?style=for-the//img.shields.io/badge/Linux-Supported-FCC624?style=for-the-badge&logo=linux&logoColor=blackhttps://img.shields.io/badge/Bash-Scripting-4EAA25?style=for-the-badge&logo=gnubash&logoColor[Kubernetes](https://img.shields.io/badge/Kubernetes-Utilities-326CE5?style=for-the-badge&logo=kubernetes&logoColor=
---

# 📖 About

This repository contains a growing collection of infrastructure automation scripts developed to simplify Linux administration, Kubernetes operations, server onboarding, SSL certificate management, and virtual machine preparation.

## Goals

✅ Reduce manual administrative effort

✅ Standardize server deployments

✅ Improve operational consistency

✅ Accelerate troubleshooting

✅ Automate common infrastructure workflows

✅ Enable repeatable and reliable infrastructure operations

---

# 📑 Table of Contents

- #-about
- [🗂 Repository Structure [⚙️ Automation Categories](#️-automation-categories)
low
- [-requirements
- #-getting-started
- [✅ Recommended Validation Workflow](#-repository-focus
- #-security-guidance
- #-contributing
- [🗺 Roadmap](#-roadr

---

# 🗂 Repository Structure

```text
shell-script/
│
├── server-onboarding/
│
├── kubernetes/
│
├── motd-message/
│
├── vm-from-cloud-images/
│   └── vm-tools/
│
├── copy-ssl-from-remote.sh
│
└── README.md
```

---

# ⚙️ Automation Categories

## 🖥 Server Onboarding

Automates common tasks performed after deploying a new Linux server.

### Features

- Operating system updates
- Package installation
- Server preparation
- User configuration
- SSH configuration
- Environment standardization
- Administrative tooling setup

### Benefits

- Faster server provisioning
- Consistent deployments
- Reduced human error
- Standardized configuration

---

## ☸️ Kubernetes Utilities

Scripts and utilities that assist with Kubernetes administration and troubleshooting.

### Common Use Cases

- Kubernetes host preparation
- Cluster validation
- Node health checks
- Runtime verification
- Troubleshooting assistance
- Operational automation
- Administrative utilities

### Focus Areas

- kubeadm environments
- Linux prerequisites
- Cluster operations
- Validation and troubleshooting

---

## 📢 MOTD Configuration

Message of the Day configurations for Linux systems.

### Capabilities

- Server identification
- Environment information
- Resource statistics
- Administrative notices
- Login banner customization

### Typical Information Displayed

- Hostname
- Operating system
- Kernel version
- Uptime
- CPU information
- Memory usage
- Disk usage
- Network details

---

## 🔐 SSL Certificate Management

Tools designed to simplify certificate migration and handling.

### Features

- Remote certificate retrieval
- Certificate migration
- Backup workflows
- Simplified administration

### Benefits

- Reduced manual effort
- Faster migrations
- Consistent handling procedures

---

## ☁️ Cloud Image VM Tools

Resources used when creating virtual machines from cloud images.

### Typical Tasks

- Guest preparation
- Post-deployment configuration
- VM customization
- Environment provisioning

---

# 🏗 Example Automation Workflow

```text
┌──────────────────────────┐
│  🚀 Deploy Linux Server  │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│ ⚙️ Run Onboarding Script │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│ 📦 Install Packages      │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│ 👤 Configure Users & SSH │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│ 🔒 Apply Security Config │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│ 📢 Configure MOTD        │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│ ✅ Production Ready      │
└──────────────────────────┘
```

---

# 🧰 Requirements

## Supported Linux Distributions

| Distribution | Supported |
| ------------ | --------- |
| Ubuntu | ✅ |
| Debian | ✅ |
| Fedora | ✅ |
| Rocky Linux | ✅ |
| AlmaLinux | ✅ |

## Common Requirements

- Bash
- Standard Linux utilities
- sudo privileges (where required)
- Network connectivity
- SSH access for remote operations

### Kubernetes Scripts May Also Require

- kubectl
- kubeadm
- kubelet
- containerd
- CRI-compatible runtime

---

# 🚀 Getting Started

## Clone Repository

```bash
git clone https://github.com/iamraj-patel/shell-script.git
cd shell-script
```

## Discover Available Scripts

```bash
find . -type f | sort
```

## Review Script

```bash
less script.sh
```

## Validate Syntax

```bash
bash -n script.sh
```

## Run ShellCheck

```bash
shellcheck script.sh
```

## Make Executable

```bash
chmod +x script.sh
```

## Run Script

```bash
./script.sh
```

or

```bash
sudo ./script.sh
```

---

# ✅ Recommended Validation Workflow

```text
┌─────────────┐
│ 🔍 Inspect  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 📝 bash -n  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 🧹 ShellCheck │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 🧪 Test VM  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 💾 Backup   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ ▶️ Execute  │
└──────┬──────┘
       │
       ▼
┌────────────────────────┐
│ ✅ Validate Results    │
│ ✅ Check Idempotency   │
└────────────────────────┘
```

## Validation Steps

1. Inspect script contents.
2. Review variables and paths.
3. Validate syntax with `bash -n`.
4. Run ShellCheck.
5. Test in a lab environment.
6. Back up existing configuration.
7. Execute carefully.
8. Validate expected outcomes.
9. Confirm repeatable execution.

---

# 📊 Repository Focus

| Technology | Status |
| ---------- | ------ |
| Linux Administration | ✅ |
| Infrastructure Automation | ✅ |
| Kubernetes | ✅ |
| Bash Scripting | ✅ |
| Security Operations | ✅ |
| Server Onboarding | ✅ |
| SSL Management | ✅ |
| Virtual Machine Provisioning | ✅ |

---

# 🔒 Security Guidance

## Always

- Review scripts before executing.
- Verify repositories and downloads.
- Back up existing configurations.
- Use least privilege.
- Protect certificates and private keys.
- Test before production deployment.

## Never

- Commit secrets to Git.
- Store passwords in plain text.
- Expose private keys.
- Blindly execute scripts from unknown sources.
- Skip validation testing.

---

# 🤝 Contributing

Contributions, suggestions, and improvements are welcome.

```bash
git checkout -b feature/my-improvement

git add .

git commit -m "Add improvement"

git push origin feature/my-improvement
```

### Contribution Guidelines

- Keep scripts documented.
- Follow shell scripting best practices.
- Avoid hardcoded secrets.
- Test changes before submitting.
- Update documentation when necessary.

---

# 🗺 Roadmap

- [ ] Health-check automation
- [ ] Kubernetes reporting tools
- [ ] SSL expiration monitoring
- [ ] Automated server inventory
- [ ] ShellCheck GitHub Actions
- [ ] CI/CD validation
- [ ] Enhanced logging
- [ ] Standardized error handling
- [ ] Additional Linux distribution testing

---

# 👨‍💻 Author

## Raj Patel

**Infrastructure Managed Services Senior Analyst**

Linux • Windows Server • VMware • Kubernetes • Automation

### GitHub

https://github.com/iamraj-patel

---

<div align="center">

### ⭐ If you find these scripts useful, consider giving the repository a star.

**Building better infrastructure through automation.**

</div>
