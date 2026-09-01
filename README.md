<div align="center">

# 🚀 Infrastructure Automation Shell Scripts

### Linux • Kubernetes • Server Onboarding • SSL Management • Cloud VM Tooling

Automating repetitive infrastructure tasks through Bash scripting and operational automation.

<br>

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnubash&logote
![Linux](https://img.shields.io/badge/Platform-Linux-FCC624?style=for-the-badge&logo=linux&logock
![Kubernetes](https://img.shields.io/badge/Kubernetes-Utilities-326CE5?style=for-the-badge&logo=kuberneteste
![Automation](https://img.shields.io/badge/Focus-Automation-orange?style=for-theub last commit](https://img.shields.io/github/last-commit/ipt?style=flat-square
![GitHub stars](https://img.shields.io/github/stars/iamraj-patel/shell-script?styleitHub forks](https://img.shields.io/github/forks/iamraj-patel/shellat-square

</div>

---

# 📖 About

This repository contains a growing collection of Bash scripts, automation utilities, and Linux administration tools used to simplify infrastructure operations and standardize system management tasks.

The primary objectives are:

✅ Reduce manual effort

✅ Standardize deployments

✅ Improve operational consistency

✅ Accelerate troubleshooting

✅ Automate common infrastructure workflows

✅ Improve system reliability

✅ Build reusable operational tooling

---

# 📑 Table of Contents

- #-repository-structure
- [-automation-categories
- [Example Automation Workfloww
- [Repositoryy-focus
- [Requirementss
- #-getting-started
- [Recommended Validationn-workflow
- [Security Guidance](#-security-guidance)
ments
- [-contributing
- [Roadmapp
- #-author

---

# 🗂 Repository Structure

```text
shell-script/
│
├── kubernetes/
│   └── Kubernetes administration utilities
│
├── server-onboarding/
│   └── Linux server onboarding automation
│
├── motd-message/
│   └── Dynamic MOTD configuration
│
├── vm-from-cloud-images/
│   └── vm-tools/
│       └── VM preparation utilities
│
├── copy-ssl-from-remote.sh
│   └── SSL certificate transfer utility
│
└── README.md
```

---

# ⚙️ Automation Categories

## ☸️ Kubernetes Utilities

Tools and scripts designed for Kubernetes administration and operational validation.

### Use Cases

- Kubernetes host preparation
- Cluster validation
- Node health checks
- Runtime verification
- Troubleshooting assistance
- Operational automation
- Configuration validation

### Benefits

- Faster troubleshooting
- Standardized validation
- Consistent deployments
- Reduced configuration errors

---

## 🖥️ Server Onboarding

Automation used after deploying a new Linux server.

### Typical Tasks

- System updates
- Package installation
- User creation
- SSH configuration
- Environment preparation
- Security baseline configuration
- Administrative tooling installation

### Benefits

- Faster deployment
- Consistent server builds
- Reduced manual work
- Improved operational standards

---

## 📢 MOTD Management

Dynamic Message of the Day configurations for Linux systems.

### Information Displayed

- Hostname
- Operating System
- Uptime
- CPU Information
- Memory Usage
- Disk Utilization
- Network Information
- Administrative Notices

### Benefits

- Quick server visibility
- Consistent login experience
- Easier troubleshooting
- Environment identification

---

## 🔐 SSL Certificate Management

Automation for certificate migration and remote certificate retrieval.

### Features

- Remote certificate copying
- Certificate migration
- SSL backup workflows
- Reduced manual transfer effort

### Recommended Checks

- Verify certificate permissions
- Confirm file ownership
- Validate certificate chain
- Check expiration dates

---

## ☁️ Cloud Image VM Tools

Utilities for preparing virtual machines built from cloud images.

### Common Tasks

- Initial VM preparation
- Post-deployment configuration
- Environment standardization
- Guest tooling setup
- Operational readiness checks

### Benefits

- Faster VM provisioning
- Consistent VM configuration
- Improved deployment repeatability

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

# 📊 Repository Focus

| Technology | Focus |
|------------|--------|
| Linux Administration | ✅ |
| Infrastructure Automation | ✅ |
| Kubernetes | ✅ |
| Security | ✅ |
| VMware | ✅ |
| Cloud Images | ✅ |
| Bash Scripting | ✅ |
| Server Standardization | ✅ |

---

# 🧰 Requirements

## Supported Distributions

| Distribution | Supported |
|-------------|-----------|
| Ubuntu | ✅ |
| Debian | ✅ |
| Fedora | ✅ |
| Rocky Linux | ✅ |
| AlmaLinux | ✅ |

## General Requirements

- Bash
- Linux operating system
- Standard GNU utilities
- sudo privileges (when required)
- Network connectivity
- SSH client tools

For Kubernetes-specific scripts:

- kubectl
- kubeadm
- kubelet
- Container runtime

---

# 🚀 Getting Started

## Clone Repository

```bash
git clone https://github.com/iamraj-patel/shell-script.git
cd shell-script
```

## Review Scripts

```bash
find . -type f
```

## Validate Bash Syntax

```bash
bash -n script.sh
```

## Run ShellCheck

```bash
shellcheck script.sh
```

## Grant Execute Permission

```bash
chmod +x script.sh
```

## Execute Script

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

### Recommended Process

1. Review script contents.
2. Validate syntax with `bash -n`.
3. Run ShellCheck.
4. Test in a lab environment.
5. Back up configuration.
6. Execute script.
7. Validate results.
8. Confirm idempotency.
9. Document findings.

---

# 🔒 Security Guidance

## Never

❌ Commit secrets

❌ Commit private keys

❌ Commit kubeconfig files

❌ Store credentials in scripts

❌ Expose tokens in logs

## Always

✅ Review scripts before execution

✅ Follow least privilege principles

✅ Back up configurations

✅ Verify permissions

✅ Validate certificates

✅ Test in non-production environments

✅ Document infrastructure changes

---

# 🌍 Supported Environments

The repository primarily targets Linux environments including:

- Ubuntu
- Debian
- Fedora
- Rocky Linux
- AlmaLinux
- Cloud-based Linux images
- Virtualized Linux workloads

Compatibility depends on the individual script and should always be validated before production use.

---

# 🤝 Contributing

Contributions, suggestions, and improvements are welcome.

## Example Workflow

```bash
git checkout -b feature/new-improvement

git add .

git commit -m "Add improvement"

git push origin feature/new-improvement
```

### Contribution Guidelines

- Test your changes
- Follow Bash best practices
- Add comments where appropriate
- Keep code readable
- Update documentation
- Avoid committing secrets

---

# 🗺 Roadmap

- [ ] Health-check automation
- [ ] Server inventory reporting
- [ ] SSL expiration monitoring
- [ ] Kubernetes reporting tools
- [ ] ShellCheck GitHub Actions
- [ ] Automated testing
- [ ] Standardized logging
- [ ] Improved error handling
- [ ] Release versioning
- [ ] Additional Linux distribution support

---

# 👨‍💻 Author

## Raj Patel

**Infrastructure Managed Services Senior Analyst**

Linux • Windows Server • VMware • Kubernetes • Automation

GitHub: https://github.com/iamraj-patel

---

<div align="center">

### ⭐ If you find these scripts useful, consider starring the repository.

**Building better infrastructure through automation.**

</div>
