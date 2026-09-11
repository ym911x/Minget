# 钥匙串反复授权弹框：改用本地自签名证书

交接说明。执行者：正在跑 1.0.2 修订的对话。

---

## 0. 变更边界

| 项    | 内容                                                   |
| ---- | ---------------------------------------------------- |
| 改什么  | `scripts/build.sh` 的签名段（约 79 行起），可选新增证书生成脚本          |
| 不改什么 | Swift 源码、测试、`Info.plist`、`VERSION`、任何与 1.0.2 修订相关的文件 |
| 前置动作 | 用户手动创建证书（§3.1）与授权私钥（§3.2），执行者无法代劳                    |
| 收尾动作 | 用户手动授权一次钥匙串（§3.5），这是预期行为                             |



---

## 1. 现象

打开 `dist/Minget.app` 后，每次启动或读取余额都弹出系统对话框：

> 「明明有数 · MingeT」想要使用你储存在钥匙串的 "local.usagemonitor.credentials" 中的机密信息。

点「始终允许」无效，下次重建后照旧弹出。

---

## 2. 根因

### 2.1 机制

钥匙串条目的访问控制列表（ACL）记录的是创建该条目时进程的**代码签名指定要求**（designated requirement，简称 DR）。系统在后续访问时比对 DR，一致则放行。

ad-hoc 签名（`codesign --sign -`）没有证书、没有 Team ID，系统无法从中提取稳定身份，DR 只能退化成整个二进制的哈希（cdhash）。二进制一变，DR 就变。

### 2.2 实测证据

环境：macOS 26.6.2 (25G83)，arm64。

| 证据            | 命令                                                                       | 实测输出                                                                 |
| ------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| 本机无任何可用签名证书   | `security find-identity -v -p codesigning`                               | `0 valid identities found`                                           |
| 当前为 ad-hoc 签名 | `codesign -dv --verbose=2 dist/Minget.app`                               | `Signature=adhoc`、`flags=0x2(adhoc)`、`TeamIdentifier=not set`        |
| DR 已退化为代码哈希   | `codesign -d -r- dist/Minget.app`                                        | `# designated => cdhash H"aedb372dfff4c7c523b32b905cc870205f163a32"` |
| 构建脚本使用 ad-hoc | `scripts/build.sh` 签名段                                                   | `codesign --force --sign - "$DIST/$APP_NAME.app"`                    |
| 三个副本哈希互不相同    | `codesign -d -vvv dist/*.app`                                            | `aedb372d…` / `aaf6d6ab…` / `fc52e098…`                              |
| 钥匙串条目         | `security find-generic-password -s local.usagemonitor.credentials`       | `svce=local.usagemonitor.credentials`、`acct=deepseek.api-key`        |
| 条目由该应用创建      | `Sources/UsageMonitorCore/Providers/ProviderCredentialStore.swift:30,54` | service 常量 + `SecItemAdd`，未指定 `kSecAttrAccess`                       |

### 2.3 推理链

1. `scripts/build.sh` 每次 `rm -rf dist/Minget.app` 后重新编译，再 `codesign --force --sign -`。
2. Swift 编译产物字节变化，cdhash 随之变化，DR 随之变化。
3. 钥匙串 ACL 中保存的是上一版 DR。
4. 系统比对失败，判定为「不同的程序」，要求用户重新授权。
5. 「始终允许」写入的是当时那一版 cdhash，下次重建即失效。

三个同 bundle id 的副本（`Minget.app`、`UsageMonitor.app`、`UsageMonitor 2.app`）哈希各异，打开任一个都会触发，且彼此覆盖授权记录，进一步放大问题。

### 2.4 外部依据

Apple 支持文档《如果已更改的应用要求访问您 Mac 上的钥匙串》说明：应用「自从打开后已经被修改」时，钥匙串访问会请求许可；且「如果不能安全地确定应用的身份」，长期授权无法生效。

来源：<https://support.apple.com/zh-cn/guide/keychain-access/kyca17142>

---

## 3. 方案

目标：把 DR 从「cdhash」换成「bundle id + 证书叶子哈希」。证书不变，则 DR 恒定，重建任意多次都能匹配，弹框不再出现。

### 3.1 创建证书（用户手动，约 1 分钟）

**首选：图形界面**

1. 打开「钥匙串访问」：`/System/Library/CoreServices/Applications/Keychain Access.app`
2. 菜单「钥匙串访问 → 证书助理 → 创建证书…」
3. 按下表填写

| 字段   | 值                      |
| ---- | ---------------------- |
| 名称   | `Minget Local Signing` |
| 身份类型 | 自签名根证书                 |
| 证书类型 | 代码签名                   |
| 有效天数 | 3650                   |

1. 创建后出现在「登录 → 我的证书」。私钥 ACL 由证书助理一并配好，通常无需再手工授权。

**备选：命令行**

注意 `/usr/bin/openssl` 是 LibreSSL 3.3.6，不支持 `-addext`，必须用 Homebrew 的 openssl@3。本机已确认存在 `/opt/homebrew/bin/openssl` 3.6.3。

```bash
set -euo pipefail
OPENSSL=/opt/homebrew/bin/openssl
WORK="$(mktemp -d)"
CN="Minget Local Signing"
P12PASS="minget-local"

"$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$CN/O=Minget/C=CN" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

"$OPENSSL" pkcs12 -export -legacy \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$P12PASS"

security import "$WORK/identity.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$P12PASS" \
  -T /usr/bin/codesign -T /usr/bin/security
```

若 `pkcs12 -export -legacy` 报错，去掉 `-legacy` 重试。

### 3.2 授权 codesign 使用私钥（用户手动，需登录密码）

跳过这一步会导致每次 `codesign` 都弹框索要私钥密码。命令行路径必须执行；图形界面路径也建议执行一次。

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "<登录密码>" "$HOME/Library/Keychains/login.keychain-db"
```

### 3.3 可选：让证书受信任

不设也能签名并工作，因为本地构建的 app 没有 quarantine 属性，Gatekeeper 不拦截。设置后 `find-identity -v` 会正常列出该证书，系统其他组件也不会报「无法验证开发者」。

路径：钥匙串访问 → 双击 `Minget Local Signing` → 展开「信任」→「使用此证书时」选**始终信任**（需管理员密码）。

### 3.4 改 scripts/build.sh（执行者）

动手前先确认文件未被 1.0.2 流程改动：重新读取当前内容，不要凭本文件里的行号直接替换。

**现状**

```bash
echo "== codesign (ad-hoc) =="
# Fail closed: a bundle that cannot be signed or verified must not be reported as built.
xattr -cr "$DIST/$APP_NAME.app"
if ! codesign --force --sign - "$DIST/$APP_NAME.app"; then
  echo "error: ad-hoc codesign failed" >&2
  exit 1
fi
```

**改为**

```bash
SIGN_IDENTITY="${MINGET_SIGN_IDENTITY:-Minget Local Signing}"

echo "== codesign ($SIGN_IDENTITY) =="
# Fail closed: a bundle that cannot be signed or verified must not be reported as built.
xattr -cr "$DIST/$APP_NAME.app"

if ! security find-identity -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
  echo "error: signing identity '$SIGN_IDENTITY' not found in keychain" >&2
  echo "       create it first, see docs/versions/1.0.2/SIGNING_HANDOFF.md 3.1" >&2
  exit 1
fi

if ! codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$DIST/$APP_NAME.app"; then
  echo "error: codesign with '$SIGN_IDENTITY' failed" >&2
  exit 1
fi
```

**逐条理由**

| 决定                                 | 理由                                                             |
| ---------------------------------- | -------------------------------------------------------------- |
| 用环境变量 `MINGET_SIGN_IDENTITY` 覆盖默认值 | 保留一键回退到 ad-hoc 的能力：`MINGET_SIGN_IDENTITY=- ./scripts/build.sh` |
| 检查签名身份后才签名                         | 符合 `AGENTS.md` 的 fail closed 原则，缺失身份时以非零退出，不产出误判为「已构建」的包       |
| `find-identity` 不加 `-v`            | 证书未设信任时 `-v`（valid only）会返回空，导致误判。不带 `-v` 才能可靠列出               |
| 不加 `--options runtime`             | 本地自用无需硬化运行时，开启会引入库验证等额外约束，当前没有需要它的场景                           |
| 加 `--timestamp=none`               | 自签名证书无时间戳服务，显式声明避免多余网络请求                                       |
| 保留 `xattr -cr`                     | 清除扩展属性，避免签名后属性变更破坏密封                                           |

### 3.5 首次运行授权一次（预期，不是失败）

换签名后，现有钥匙串条目的 ACL 里没有新证书的 DR，第一次读取仍会弹出对话框。

处理：输入登录密码，点「**始终允许**」。此后重建任意多次都不再弹。

注意：不要删除钥匙串条目来「重置」。删了需要用户重新输入 DeepSeek API Key。保留旧条目，授权一次即可过渡。

### 3.6 清理冗余副本（可选，需用户确认）

`dist/` 下有三个同 bundle id 的副本，会放大触发源：

| 路径                        | 建议                   |
| ------------------------- | -------------------- |
| `dist/Minget.app`         | 保留，这是 `build.sh` 的产出 |
| `dist/UsageMonitor.app`   | 旧的产物名，建议移出或删除        |
| `dist/UsageMonitor 2.app` | 同上                   |

1.0.2 修订正在跑，执行前先向用户确认这两个副本是否还被引用。

---

## 4. 验收标准

| # | 检查           | 命令                                              | 期望                                                                                         |
| - | ------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------ |
| 1 | 签名不再 ad-hoc  | `codesign -dv --verbose=2 dist/Minget.app`      | 出现 `Authority=Minget Local Signing`，不再出现 `Signature=adhoc`                                 |
| 2 | DR 含证书       | `codesign -d -r- dist/Minget.app`               | `designated => identifier "local.usagemonitor.UsageMonitor" and certificate leaf = H"..."` |
| 3 | **DR 跨构建恒定** | 连续构建两次，各跑一次上一条命令                                | 两次输出的 `identifier` 与 `certificate leaf` 哈希完全一致                                             |
| 4 | 结构校验通过       | `codesign --verify --verbose=1 dist/Minget.app` | 通过                                                                                         |
| 5 | 真实弹框消失       | 打开 app → 授权一次 → 重建 → 再打开                        | 第二次不再弹框                                                                                    |

第 3 条是核心证据。cdhash 会变（这是正常的），但 DR 里的 `identifier` 和 `certificate leaf` 不能变。只要这两项稳定，钥匙串就会认。

第 5 条必须在真实界面完成，测试通过不能代替。

---

## 5. 风险与回退

| 风险           | 说明                               | 处理                                                                            |
| ------------ | -------------------------------- | ----------------------------------------------------------------------------- |
| 证书有效期        | 自签名设为 10 年，到期后签名失效               | 到期重新创建证书，重跑 §3.4                                                              |
| 签名时反复索要密码    | 未执行 §3.2                         | 补跑 `set-key-partition-list`                                                   |
| 证书未受信任       | 自签名默认不受信任，`find-identity -v` 返回空 | 执行 §3.3；或保持 build.sh 中不带 `-v` 的检查                                             |
| 与 1.0.2 修订冲突 | `build.sh` 可能正被另一流程修改            | 改前重读文件内容并 `git status`                                                        |
| 回退到 ad-hoc   | —                                | `MINGET_SIGN_IDENTITY=- ./scripts/build.sh`，或 `git checkout scripts/build.sh` |

---

## 6. 明确不做的事

依据 `AGENTS.md` 的凭证与数据处理边界：

- 不改 `Sources/` 下任何 Swift 源码，特别是 `ProviderCredentialStore.swift`
- 不把任何凭证写入源码、`UserDefaults`、日志、测试快照或文档
- 不读取或修改 `~/.codex/auth.json`、浏览器 Cookie 或任何既有会话数据
- 不通过网络请求验证任何 Key
- 不删除现有钥匙串条目
- 不发版、不推送远端

---

## 7. 复核记录

本文档中的实测输出，采集时间 2026-09-11 01:53 至 01:58 (GMT+8)，命令与工作目录：项目根目录。

未执行的动作：未创建证书、未修改 `build.sh`、未触碰钥匙串条目。第 3 节中「自签名证书的 DR 形如 `certificate leaf = H"..."`」为依据代码签名机制的推理结论，需由执行者在 §4 第 2、3 条实测确认。

---

## 8. 执行者补注（1.0.2 对话追加，未改动上文）

采集时间 2026-09-11 02:01 至 02:13 (GMT+8)。用户确认后执行了执行方可以完成的部分。

### 8.1 已完成

| 动作                                                                      | 文件                                 |
| ----------------------------------------------------------------------- | ---------------------------------- |
| 按 §3.4 改造签名段，默认身份 `Minget Local Signing`，保留 `MINGET_SIGN_IDENTITY=-` 回退 | `scripts/build.sh`                 |
| staging 增加删除失败检查，删除被拒时非零退出（原文未要求，理由见 8.5）                               | `scripts/build.sh`                 |
| 新增证书生成脚本（§3.1 命令行路径 + §3.2 可选授权，`--authorize`）                          | `scripts/make-signing-identity.sh` |

实测（原文见 `evidence/logs/08-signing-build-path.txt`）：无证书时默认路径 `exit=1` 并打印指引；`MINGET_SIGN_IDENTITY=-` 回退路径构建与签名校验通过，版本仍为 `1.0.2`。

### 8.1.1 §4 验收结果（证书创建后）

原始输出见 `evidence/logs/09-signed-verification.txt`。

| # | 结果       | 实测                                                                                                                                                                                 |
| - | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | 通过       | `Authority=Minget Local Signing`、`Signature size=1822`、`flags=0x0(none)`                                                                                                           |
| 2 | 通过，措辞需修正 | 实际为 `identifier "local.usagemonitor.UsageMonitor" and certificate root = H"5a48bb2b5305dd0ad0484581f1ce5173061ba395"`。自签名证书自身即根，因此导出 `certificate root` 而非原文预期的 `certificate leaf` |
| 3 | **通过**   | release 与 debug 交替三次，CDHash 由 `e4842fa1…` 变 `0173a4fc…` 再复原，DR 证书哈希始终 `5a48bb2b…`                                                                                                  |
| 4 | 通过       | `codesign --verify --verbose=1` 返回 `valid on disk`，退出码 0                                                                                                                           |
| 5 | **未确认**  | 见 8.4                                                                                                                                                                              |

证书状态：`1) 5A48BB2B5305DD0AD0484581F1CE5173061BA395 "Minget Local Signing" (CSSMERR_TP_NOT_TRUSTED)`。未设信任（§3.3）不影响签名与本地运行；`-v` 仍返回 `0 valid identities found`，印证 §3.4 关于不带 `-v` 的说明。

### 8.2 与 §3.4 的两处偏离

1. 身份存在性检查被前移到 `swift build` 与 staging 之前。§3.4 的位置在 `rm -rf dist/Minget.app` 之后，身份缺失会在包被删除重建后才失败，留下未签名的包并浪费一次完整编译。前移后失败路径零副作用，已实测：失败前后 DR、mtime、二进制大小逐字段一致。
2. staging 增加 `rm -rf` 后的存在性检查。理由与实测见 8.5。

### 8.3 一处事实修正（§2.3 第 2 条）

原文写作「Swift 编译产物字节变化，cdhash 随之变化」，把变化归因于「重建」这一动作。实测表明源码未变时连续重建，cdhash 保持 `aedb372dfff4c7c523b32b905cc870205f163a32` 不变，二进制大小也一致，release 构建在本机可复现。

准确表述：cdhash 随二进制内容变化。因此 ad-hoc 症状在代码改动后出现，而仅在源码未变时重复构建不会改变 DR。这解释了「每次重建后照旧弹框」的实际观感（重建通常伴随改代码），也说明三个同 bundle id 副本之所以互相覆盖授权记录，是因为它们构建自不同版本的源码，cdhash 各不相同（`aedb372d…` / `aaf6d6ab…` / `fc52e098…`）。原文结论不受影响。

### 8.4 仍未完成

§3.5 真实界面点一次「始终允许」与 §4 第 5 条（重建后不再弹框）需用户确认。

证书创建后连续启动三次签名包，`applicationDidFinishLaunching` 到 `viewmodel start` 的间隔为 12 秒、15 秒、11 秒，与 ad-hoc 时期同量级，未因换签名而缩短。若阻塞确实是本文档 §1 的对话框在等待应答，首次授权后应显著缩短。当前无法区分「弹框仍出现、ACL 尚未授权」与「阻塞与弹框无关」两种情况，判别只需在真实界面观察启动时是否弹框。

### 8.5 一次真实的 staging 事故

同一回合内多次构建后，`rm -rf dist/Minget.app` 被执行环境的安全限制拒绝，而 §3.4 的写法没有检查删除结果，脚本继续 `mkdir` 与 `cp`，把上一次 debug 构建的二进制留在 `dist/Minget.app` 并以退出码 0 打印 `built:`。已加入删除后的存在性检查，并把受损包移动到 `/tmp/minget-broken/`（未删除）。详见 `evidence/logs/10-staging-fail-closed.txt` 与 `IMPLEMENTATION_REPORT.md` 第 9.6 节。

### 8.6 附带推断的当前状态

`applicationDidFinishLaunching` 到 `viewmodel start` 之间的阻塞，原先推断是本文档 §1 的对话框在等待应答。代码依据是 `ProviderRefreshEngine.swift:117` 的 `reader.isConfigured` 在 `AppContainer()` 构造期间读取钥匙串。换成证书后延迟未变，因此该推断**尚未被证实**。详见 `IMPLEMENTATION_REPORT.md` 第 10 节。
