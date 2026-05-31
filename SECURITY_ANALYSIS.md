# NoKey 项目安全风险全面深入分析报告

本报告对 `nokey` 项目的核心安装与配置脚本 (`nokey.sh`) 以及相关的系统服务配置文件进行了深入的安全审查。以下是发现的安全隐患、风险评估以及相应的修复建议。

## 1. 核心高危风险 (High Risk)

### 1.1 别名(Alias)注入导致潜在的远程命令执行 (RCE) 与供应链攻击
**问题描述：**
脚本通过 `add_alias_if_missing` 函数在用户的 `.bashrc`、`.zshrc` 等 shell 配置文件中写入了以下别名：
```bash
alias nokey="bash <(curl -fsSL https://raw.githubusercontent.com/shaolonger/nokey/refs/heads/main/nokey.sh)"
```
**安全隐患：**
- 每次用户在终端中输入 `nokey` 时，都会直接从 GitHub `main` 分支实时拉取并使用 `bash` 执行。
- 这是一个典型的**高危供应链风险**。如果 GitHub 仓库被攻击者入侵并篡改了 `nokey.sh`（或者网络层面发生了针对 GitHub Raw 域名的极其复杂的 MITM 攻击），攻击者可以直接在用户的服务器上获取 `root` 权限的远程代码执行 (RCE) 能力。
- 即使用户在首次安装时检查了源码，未来的每次调用都在执行未经验证的最新网络代码。

**修复建议：**
- 取消这种通过 `curl | bash` 设置的长期命令别名。
- 应将脚本直接下载到本地（例如 `/usr/local/bin/nokey`），赋予执行权限，并在需要更新时提供一个专门的更新命令（如 `nokey update`），更新时必须进行哈希校验。

### 1.2 服务权限过高：Sing-box 以 Root 身份运行
**问题描述：**
在 `sing-box.service` 文件中，服务被配置为直接以 `root` 用户运行：
```ini
[Service]
Type=simple
User=root
```
**安全隐患：**
- 暴露在公网的网络代理服务（处理不受信任的网络输入）绝不应该以 `root` 权限运行。
- 如果 `sing-box` 存在任何缓冲区溢出、反序列化或其他漏洞，攻击者可以直接获得系统的完整 `root` 控制权。相比之下，项目中的 `xray` 和 `realm` 服务已被正确配置为使用 `nobody` 和 `$INSTALL_USER` 运行，只有 `sing-box` 存在此问题。

**修复建议：**
- 修改 `sing-box.service`，将 `User=root` 更改为 `User=nobody`（或创建一个专用的低权限系统账户）。
- 如果需要绑定 1024 以下的特权端口（如 443），请在 Systemd 配置文件中配置 `AmbientCapabilities=CAP_NET_BIND_SERVICE`。

---

## 2. 中危风险 (Medium Risk)

### 2.1 依赖下载的哈希校验降级 (Fallback) 机制
**问题描述：**
在 `download_if_sha_differs` 和安装过程代码中，脚本尝试通过 GitHub API 抓取 Release 的 SHA256 校验和（`fetch_release_sha256_map`）。但是，如果获取失败，脚本会输出警告并直接回退到无校验的下载模式：
```bash
warn "获取Release校验和失败，回退到直接下载文件 / Failed to fetch release checksums; fallback to downloading files directly."
```
**安全隐患：**
- 在网络环境不稳定或遭遇中间人拦截 API 请求时，哈希校验机制将被完全绕过。
- 攻击者可以故意阻断对 API (`api.github.com`) 的请求，强制脚本回退到直接下载模式，并在此时替换被下载的二进制文件（如 `xray`、`sing-box`）。

**修复建议：**
- 对于涉及安全代理核心的二进制文件，**严格要求**哈希校验必须通过。如果无法获取校验和，应当终止安装流程，而不是降级到不安全的直接下载模式。
- 可以考虑将校验和硬编码在脚本内，与版本号绑定。

### 2.2 Xray 服务的 Capabilities 被意外剥离
**问题描述：**
在处理 `xray.service` 模板时，脚本使用了 `sed` 强行删除了特定的安全能力配置：
```bash
sed -e 's/\$INSTALL_USER/nobody/g' \
    -e '/\${temp_CapabilityBoundingSet}/d' \
    -e '/\${temp_AmbientCapabilities}/d' \
    -e '/\${temp_NoNewPrivileges}/d' \
```
**安全隐患：**
- 官方 Xray 模板中包含这些变量通常是为了赋予 `nobody` 用户绑定特权端口 ( `< 1024`) 的能力（如 `CAP_NET_BIND_SERVICE`）。
- 脚本将其剥离后，如果用户通过 `--port=443` 或配置试图让 Xray 直接监听特权端口，将会因为权限不足而失败（除非使用 Caddy 作为前置）。这可能导致用户最终被迫将服务改回以 `root` 运行，从而引入新的安全漏洞。

**修复建议：**
- 正确配置 Systemd 的 `AmbientCapabilities=CAP_NET_BIND_SERVICE`，或者不剥离这些变量而是用有效值替换它们。

### 2.3 配置文件权限控制不严
**问题描述：**
脚本通过重定向（`cat > config.json` 或 `echo > config.json`）生成包含高敏感信息（如 `privateKey`，`mldsa65Seed`，`uuid`）的配置文件：
- `/usr/local/etc/xray/config.json`
- `/etc/sing-box/config.json`
- `/usr/local/etc/realm/config.json`

**安全隐患：**
- 在未指定 `umask` 的情况下，这些文件的默认权限通常为 `644` (即其他用户可读)。
- 系统上的任何本地非特权用户或被入侵的低权限服务都可以读取这些私钥和 UUID，从而解密流量或盗用代理。

**修复建议：**
- 在生成配置文件后，使用 `chmod 600 <config_file>` 或预先设置 `umask 077`，确保只有服务运行用户（如 `nobody` 或 `root`）可读取配置文件。

---

## 3. 低危风险及隐私泄漏 (Low Risk / Data Leakage)

### 3.1 敏感信息明文记录到当前目录的日志文件中
**问题描述：**
在 `output_results` 及生成配置文件的环节，脚本将包含私钥的完整 JSON 配置、分享链接等输出，并通过 `tee -a "$LOG_FILE"` 直接记录到当前目录的 `nokey.log` 和 `nokey.url` 文件中：
```bash
cat "$config_path" | tee -a "$LOG_FILE"
```
**安全隐患：**
- 日志文件创建在用户执行脚本的当前目录，且没有任何权限控制，任何有权访问该目录的用户都可以读取包含所有密钥对的日志。
- 这极大地增加了配置泄露的风险。

**修复建议：**
- 从日志文件中过滤掉敏感的 `privateKey`、`seed` 以及分享链接，仅在标准输出 (stdout) 打印。
- 确保 `$LOG_FILE` 在脚本初始化时通过 `chmod 600 "$LOG_FILE"` 限制权限，并存放于安全的目录（如 `/var/log/nokey/`）。

### 3.2 未预期的 Bash 特性导致随机性不足
**问题描述：**
当未指定端口时，部分脚本逻辑依赖于 bash 的 `$RANDOM` 变量：
```bash
port=$(shuf -i 10000-60000 -n 1 2>/dev/null || echo $((RANDOM % 50001 + 10000)))
```
**安全隐患：**
- Bash 的 `$RANDOM` 并非密码学安全的伪随机数生成器。虽然仅用于选择端口号问题不大，但这种做法在安全工具中属于不良模式。

**修复建议：**
- 建议统一使用 `/dev/urandom` 进行任何需要随机性的操作，如生成 `shortid` 时使用的 `head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n'` 就是一种安全的做法。

---

## 总结

`nokey` 脚本在功能实现上非常完善，但在权限收拢和防范本地/网络攻击层面存在几个较为明显的短板。**强烈建议优先修复 "Sing-box 运行用户" 以及 "Alias 动态执行代码" 两个高危问题**，以保证服务器免受远程入侵，并修改文件权限以防止本机的私钥泄漏。

---

## 4. 修复状态 (Remediation Status)

**所有报告中发现的安全漏洞已在最新的代码变更中全面修复：**

- ✅ **[已修复] 移除别名注入**：去除了 `curl | bash` 的危险别名配置，改为将脚本本体自动安装到 `/usr/local/bin/nokey`，并引入了带强制哈希校验的 `--update` 参数。
- ✅ **[已修复] 降低 Sing-box 运行权限**：将 `sing-box.service` 的运行用户从 `root` 降级为 `nobody`，并配置了 `CAP_NET_BIND_SERVICE` 权限以支持绑定特权端口。
- ✅ **[已修复] 移除不安全的下载降级**：重构了 `download_if_sha_differs` 和 Release 校验逻辑，一旦哈希获取或比对失败，安装过程将因安全原因中止，彻底移除了不安全的后备直链下载。
- ✅ **[已修复] 正确配置 Xray 能力**：修正了对 `xray.service` 模板的处理，不再错误地使用 `sed` 剥离能力，而是正确赋予了 `AmbientCapabilities=CAP_NET_BIND_SERVICE` 与 `NoNewPrivileges=true`。
- ✅ **[已修复] 配置文件权限加固**：在生成包含私钥、UUID 信息的配置文件时，严格执行了 `chmod 600`，只允许当前服务所有者读取。
- ✅ **[已修复] 防止日志泄露**：移除了将生成的分享链接及敏感配置文件内容 `tee` 输入到本地未加密日志文件 (`nokey.log`, `nokey.url`) 中的逻辑，并在日志生成时应用了严格权限。
- ✅ **[已修复] 安全的随机数生成**：将不严谨的 bash `$RANDOM` 端口随机化逻辑替换为利用 `/dev/urandom` 进行的安全随机数读取。

**安全总结**：系统的整体抗攻击强度得到了大幅提升，成功消除了可能导致 RCE、服务提权和隐私密钥泄漏的攻击路径。
