# Round 6 report — DeepSeek Key 保存无反馈修订（已执行）

Status: implementation complete. All numbers below come from real commands run in this
round's environment. Nothing was committed or pushed. The 212 tests from Round 5 are all
preserved (219 total now, no old test deleted or renamed).

## 1. 根因（与任务描述一致，已在源码证实）

- `AppContainer` 用 `UsageViewModel(service:providerEngine:)` 构建 model，**没有传
  `credentials`**（Round 5 之前的可选参数，默认 nil）。
- `UsageViewModel.saveDeepSeekKey` 第一行 `guard let credentials else { return }` 静默返回：
  正式包里点"保存"什么都不发生——不存钥匙串、不验证、无任何界面反馈。
- Round 5 的 GLM 保存路径改成了经 engine reader（`GLMReading.storeAPIKey`），所以 GLM 不受
  影响；DeepSeek 仍走旧的 `credentials` 路径。既有应用接线测试都显式传了内存 store，
  因此恰好绕开了这条生产路径。

## 2. 修复

### 2.1 删除静默失败路径，单一保存路径（任务 1）

- `DeepSeekReading` 新增 `storeAPIKey(_:)`（与 `GLMReading.storeAPIKey` 同构）：Key 的写入
  由 reading 自己负责，仍只进 Keychain（`ProviderCredentialStoring`）。
- `UsageViewModel` 彻底删除 `credentials` 依赖与 `saveDeepSeekKey` 里的
  `guard let credentials else { return }`。`providerEngine` 从可选改为**必传**：没有引擎的
  view model 连保存路径都不存在，这类构造在编译期就不可能发生。
- `AppContainer` 是唯一的生产组合根；`saveDeepSeekKey` 经 `engine.reading(for: .deepseek)
  as? DeepSeekReading` 调用 `storeAPIKey`。若该转型失败（生产接线不可能发生），反馈状态置
  `.saveFailed` 并返回 false——**任何路径都不再静默**。
- `AppContainer` 新增 `transport:` 注入参数（默认 `URLSessionProviderTransport()`，生产行为
  不变），让组合根测试能用进程内传输跑**同一条**生产组合路径。

### 2.2 明确的用户反馈状态（任务 2、3、4）

新增 `CredentialFeedback`（固定词汇、可比较、无任何动态文本），按平台保存在
`UsageViewModel.credentialFeedback: [ProviderPlatform: CredentialFeedback]`（`@Published`）：

| 状态 | 固定文本 |
|---|---|
| `saving` | 正在保存… |
| `verifying` | 已保存，正在验证余额… |
| `connected` | 已连接，余额已验证 |
| `invalidCredential` | Key 无效或已被拒绝，请检查后重试 |
| `saveFailed` | 保存失败：本机钥匙串写入未成功，请重试 |
| `savedUnverified` | Key 已保存在本机，暂时无法验证余额（网络或服务不可用） |
| `awaitingContract` | 已保存；接口口径尚未确认，未显示余额（GLM 专用） |
| `deleted` | 已删除，未连接 |

- 反馈在**按钮点击的同步路径**上就出现（保存开始即 `saving` → 钥匙串成功即 `verifying`），
  验证结束后由完成的 `ProviderReport` 映射到终态。
- `DeepSeekSettingsView` / `GLMSettingsView` 新增 `CredentialFeedbackView` 一行显示；
  注意力状态（保存失败/Key 无效/暂无法验证）用醒目色。
- **输入框清空规则**：`saveDeepSeekKey`/`saveGLMAPIKey` 返回 Bool，视图只在返回 true
  （钥匙串写入成功）时清空输入；失败保留输入允许重试。
- **Keychain 错误不写敏感内容**：错误细节只进固定词汇日志（`"credential save failed"`），
  界面显示上表的固定文本，无系统返回文本、无 Key 内容。

### 2.3 保存后立即验证（任务 5）

- DeepSeek 保存成功 → `engine.reconnect(.deepseek)` → 只读 `GET /user/balance`（Bearer），
  不涉及任何模型接口（路径守卫 + 测试断言双重保证）。
- 401/403 → `.invalidCredential`（面板连接状态 `authSuspended`，自动重试暂停）。
- 断网/超时/服务错误 → `.savedUnverified`（Key 已在本机，验证未完成；之前的成功值照旧
  以 stale 显示，绝不归零）。
- 成功 → `.connected`，余额与"最近更新时间"照常显示。
- GLM 保存/会话连接沿用 Round 5 的只读探测流程，并接入同一反馈状态机（干净探测 + 合同
  未确认 → `.awaitingContract`）。

### 2.4 删除 Key（任务 6）

`deleteDeepSeekKey` / `disconnectGLM` / `disconnectDeepSeek` → `engine.disconnect`：
删凭证、清该平台余额缓存、清认证暂停状态（`states[platform] = nil`），界面显示
"已删除，未连接"。测试覆盖了"401 暂停后删除 → 暂停与缓存同时消失"。

## 3. 测试（219 条，实际执行）

新增 7 条（`Tests/UsageMonitorAppTests/ProductionWiringTests.swift`）：

| 测试 | 覆盖 |
|---|---|
| `testSavingADeepSeekKeyThroughTheProductionRootStoresItAndVerifies` | **组合根回归测试**：真实 `AppContainer` + 注入的内存 store 与进程内传输。断言：保存返回 true；Key 到达容器的 store（旧接线下为 nil，本测试即捕获 `credentials == nil` 静默返回）；反馈终态 `.connected`；余额 CNY 110.00 上屏；验证请求只打 `api.deepseek.com/user/balance` 且带 Bearer，绝无模型路径 |
| `testSavingAKeyImmediatelyEntersTheVerifyingState` | 点击后同步进入"已保存，正在验证"，随后终态 `.connected` |
| `testAKeychainSaveFailureIsReportedAndStopsBeforeAnyNetworkCall` | 钥匙串写入失败 → 返回 false、`.saveFailed` 上屏、零网络请求 |
| `testARejectedKeyIsReportedAsInvalid` | 401 → `.invalidCredential`（明确区分于网络问题），连接状态 `authSuspended` |
| `testANetworkFailureKeepsTheKeySavedAndSaysSo` | 断网 → Key 仍在、`.savedUnverified`、不显示任何金额 |
| `testDeleteClearsCredentialCacheSuspensionAndReportsIt` | 401 暂停后删除 → `.deleted`、凭证消失、缓存清空、暂停解除、面板 `notConfigured` |
| `testSavingAGLMKeyEndsInTheAwaitingContractState` | GLM 干净探测 → `.awaitingContract`，金额仍不显示 |

既有 `GLMConnectWiringTests` / `StatusItemWiringTests` 随新签名更新构造方式（engine 必传、
无 credentials 参数），断言语义未变。

```
命令：swift test
结果：Executed 219 tests, with 0 failures (0 unexpected) in 6.492s
     Test Suite 'All tests' passed
退出码：0；编译 0 error / 0 warning（release 重建亦 0 warning）
```

## 4. 构建结果（实际执行）

```
命令：./scripts/build.sh
结果：swift build (release) complete，0 warning；codesign --force --sign - 成功；
     codesign --verify 通过；plutil -lint Info.plist OK
退出码：0
产物：dist/UsageMonitor.app（Contents/MacOS/UsageMonitor + UsageMonitorCLI，2026-09-10 08:52 重建）
```

## 5. 启动与退出清理检查（实际执行）

```
命令（要点）：
  dist/UsageMonitor.app/Contents/MacOS/UsageMonitor &
  ps 确认子进程（恰好一个 codex app-server，ppid == app PID）
  kill -TERM <app>
结果：
  - 应用启动正常，仅创建一个自有 codex 子进程；
  - SIGTERM 后约 500ms 内退出；
  - 子进程被回收，无孤儿；其他应用的 codex 进程未受影响。
```

## 6. 用户实机复测步骤

1. **保存有反馈**：打开面板 → DeepSeek"连接" → 输入真实 Key → 点保存：输入框应立即清空，
   下方出现"已保存，正在验证余额…"，随后变为"已连接，余额已验证"或"Key 无效或已被拒绝"。
2. **保存失败可重试**：如遇钥匙串异常，应显示"保存失败：本机钥匙串写入未成功，请重试"，
   且输入框保留原内容（可再点保存）。
3. **断网验证**：断开网络后保存 Key，应显示"Key 已保存在本机，暂时无法验证余额（网络或
   服务不可用）"；恢复网络后点"全部刷新"应变"已连接"。
4. **无效 Key**：输入一个格式正确但无效的 Key，应显示"Key 无效或已被拒绝，请检查后重试"，
   面板状态为"需要重新连接"。
5. **删除**：点"删除 Key"应显示"已删除，未连接"，余额数字立即消失；再存同一 Key 应重新验证。
6. **退出清理**：退出应用后菜单栏图标立即消失，重新启动位置不变。

## 7. 已知问题

1. GLM 合同门槛不变：`GLMContract.confirmed` 为空，GLM 余额在设计上不显示；保存后的
   探测观测（HTTP 状态/业务码/字段名）照常发布，供确认口径使用。
2. 菜单栏几何、刘海遮挡等实机项沿用 Round 4/5 报告的待验证清单。

## 8. 本轮实际执行的命令

```bash
swift build               # PASS（迭代中多次，最终 0 error / 0 warning）
swift build --build-tests # PASS
swift test                # PASS：219 tests, 0 failures, exit 0（两次确认）
./scripts/build.sh        # PASS：dist/UsageMonitor.app 重建、签名校验通过、0 warning
dist/UsageMonitor.app/Contents/MacOS/UsageMonitor   # 启动检查：SIGTERM 后退出，子进程无孤儿
```

未执行、也不应在本环境执行：`git commit` / `git push`；未读取或打印任何真实 Key、全局
认证配置或现有浏览器 Cookie；测试全部使用内存 store 与进程内传输，不触碰真实钥匙串。
