# Provider endpoints, authentication and field evidence

Scope: v1.1 (Codex account identity, DeepSeek balance, 智谱 GLM account funds).

This file records, for each interface the app touches, what was **actually verified** and
what is still **assumed**. Evidence levels are explicit so a reader can tell a documented
public API from an unverified console interface. All examples are redacted: no credential,
no key, no session value, no account address.

| Level | Meaning |
|---|---|
| **A — verified on this machine** | Observed live against the running local service, with the observation reproducible by a test in this repository. |
| **B — official public documentation** | Published by the provider as a public, documented API. Field names taken from that documentation; not re-verified with a live key in this round. |
| **C — candidate, unverified** | Endpoint path or shape is a best-effort candidate. The app does **not** display anything derived from it until it is confirmed. |

---

## 1. Codex (local `codex app-server`)

### 1.1 `account/rateLimits/read` — Level A

- Transport: stdio JSON-RPC over one long-lived `codex app-server` child process.
- Verified previously (`docs/archive/v1.0/requirements/PROJECT_SPEC.md`, v1.0 Round 1 至 Round 3 报告，以及 `artifacts/protocol-schema/`)。
- Normalised into `UsageSnapshot`; the raw response is discarded immediately.

### 1.2 `account/read` — Level A (method and params), Level B (response shape)

| Item | Value | Evidence |
|---|---|---|
| Method | `account/read` | `artifacts/protocol-schema/codex_app_server_protocol.v2.schemas.json` |
| Params | `{"refreshToken": false}` | `artifacts/protocol-schema/v2/GetAccountParams.json` — `refreshToken` is optional and defaults to a non-refreshing read; passing `false` explicitly means the app never triggers a token refresh |
| Response | `{"account": {...} \| null, "requiresOpenaiAuth": bool}` | `artifacts/protocol-schema/v2/GetAccountResponse.json` |
| Account variants | `type: "chatgpt"` → `email: string\|null`, `planType: string`; `type: "apiKey"`; `type: "amazonBedrock"` | same schema |

Verification performed in this round:

- A test launches a real child process speaking the newline-delimited protocol and asserts
  the client sent `account/read` with `"refreshToken": false`
  (`CodexAccountTests.testAccountReadIsSentWithRefreshTokenFalse`). Level A for the request.
- Parsing is covered for `chatgpt`, `apiKey`, unknown types, null email and a missing
  account object. Level B for the response shape: taken from the schema bundled in
  `artifacts/protocol-schema/`, not from a live signed-in machine in this round.

Handling rules:

- Identity is supplementary. A failed identity read never fails the usage read.
- The panel shows `账号信息暂不可用` when no identity could be established. No address is
  hard-coded anywhere in the source, tests or documentation.
- `CodexAccount.debugSummary` deliberately omits the email, so lifecycle logs can never
  carry an account address.

### 1.3 Cache attribution

- Business cache entries are stored per account (`UsageCache.save(_:accountID:)`).
- The v1.0 unattributed store (`UsageMonitor.lastSnapshot.v1`) is only reachable when no
  account is known at all. When an account is known, a different account's entry is never
  returned, and the v1.0 store is never presented as that account's data.
- The last known account identifier is remembered so a later failure can still serve that
  account's own numbers. An identifier is stored, never a credential.

---

## 2. DeepSeek

### 2.1 `GET https://api.deepseek.com/user/balance` — Level B

| Item | Value |
|---|---|
| Method | `GET` |
| Base URL | `https://api.deepseek.com` |
| Path | `/user/balance` |
| Auth | `Authorization: Bearer <API key>` |
| Success body | `{"is_available": bool, "balance_infos": [...]}` |
| Entry fields | `currency: string`, `total_balance: string`, `granted_balance: string`, `topped_up_balance: string` |
| Amount type | decimal **strings** (e.g. `"110.00"`) |

Evidence: DeepSeek's published API documentation for "Get User Balance". This is a public,
documented API rather than a console interface, which is why it is Level B: the shape was
not re-confirmed with a live key during this round, and is verified instead through
injectable-network tests.

Implementation rules:

- Amounts are parsed as `Decimal` from the provider's own text. No `Double` conversion, no
  rounding, no currency conversion, no summation across currencies.
- Each `balance_infos` entry becomes its own row. Multiple currencies stay separate rows.
- HTTP 200 with an error object is a business failure, never a balance.
- HTTP 200 whose payload lacks a parsable `total_balance` is `unexpectedResponse`, never 0.
- 401/403 → `invalidCredential`, which suspends automatic refresh until reconnect.
- The client's path allow-list contains exactly `["/user/balance"]`, and a second,
  independent rule blocks any path that looks like a model endpoint. The API key is
  therefore usable only for this read; no model call can be made with it, by construction.

### 2.2 Key storage

- macOS Keychain generic password, service `local.usagemonitor.credentials`, account
  `deepseek.api-key`. Not synchronised to other devices.
- Never written to `UserDefaults`, logs, snapshots, source or documentation.

---

## 3. 智谱 GLM (bigmodel.cn)

### Evidence levels specific to this section

The generic Level A/B/C table above still applies. Since Round 7 the display gate is a
**per-endpoint strict schema** (`GLMSchema` in `GLMProvider.swift`) instead of one global
boolean. A schema is added to `GLMContract.confirmedSchemas` only as a reviewed decision,
with its envelope, field paths, types and amount constraints pinned by tests in
`GLMProviderTests`. Evidence today comes from third-party implementations plus the user's
real probe — it is **not** official documentation, so both schemas are marked accordingly.

### 3.1 `GET https://open.bigmodel.cn/api/paas/v4/balance` — third-party implementations; **availability unverified (未证实)** (schema `apiBalanceV1`)

- Used by multiple independent open-source implementations with a plain API key
  (dsh-usage-stats `lib/balance.js`, TokenLedger). No official public documentation was
  available to this project; nothing here may be called an official contract.
- **Round 8 evidence status: 未证实, in both directions.** HTTP 200 answers, top-level
  `code/data/msg/success` shapes, synthetic tests and third-party declarations do not
  prove the route works for the user's account; a single rejected key would not prove it
  dead either. No removal decision is made without that evidence. The console session
  path is the app's primary route for GLM.
- Auth: `Authorization: Bearer <key>` (both historical spellings probed read-only).
- Confirmed schema (pinned by tests): `{"code": 200 | "200" | "success" | 0,
  "success": true?, "data": {"total_balance": number|string, "available_balance":
  number|string, "currency": string?}}`.
- Amounts decode exactly to `Decimal` from the number's source text or the decimal string;
  never through a `Double`. A present-but-invalid amount is a failure, never 0.
- `currency` is used only when the response names one; otherwise the amount displays with
  a 币种未确认 note. No default currency is ever invented.
- This is the primary read path for a plain API key, with the console report endpoint as a
  one-shot fallback when the answer matches no known shape.

### 3.2 `GET https://open.bigmodel.cn/api/biz/account/query-customer-account-report` — user probe partially confirmed (schema `consoleReportV1`)

| Item | Status |
|---|---|
| Path | user's real probe answered HTTP 200; nested shape from independent implementations, pending user confirmation |
| Auth header | console session (`Cookie` from the captured session) |
| Top-level shape | **user-confirmed, and only this**: HTTP 200 with top-level `code`, `data`, `msg`, `success`. The screenshot does **not** evidence authentication success, nested money fields, units or balances (REVIEW round 7 correction) |
| Nested shape | **pending**: `data.balance` object with `balance`, `availableBalance`, `rechargeAmount`, `giveAmount`, `totalSpendAmount`, `frozenBalance` |
| Currency | **unconfirmed** — displayed with 币种未确认 when absent |
| Auth mechanism beyond cookies | **unknown** — if the balance resource needs more than cookies, it is identified by observation, not guessed |

Confirmed schema (pinned by tests): envelope business-success (`code` numeric 200/0 or
string `"200"`/`"success"`, `success != false`) plus a `data.balance` object whose
`balance` (总额) / `availableBalance` (可用) parse strictly; `rechargeAmount` (累计充值),
`giveAmount` (累计赠送), `totalSpendAmount` (累计消费), `frozenBalance` (冻结金额) are
carried as labelled amounts with their original semantics, never mapped onto the DeepSeek
充值/赠费 fields.

When a business-successful response matches no known shape on every attempted endpoint,
the read reports `structureUnsupported` and the panel shows a **redacted structure
summary** — JSON paths and types only, depth ≤ 3, count ≤ 24, never values, array
contents, upstream messages, keys or cookies — so a new real shape can be pinned for the
next revision (pinned by `GLMProviderTests`).

### 3.3 Console data-source observer (Round 8 instrument)

The app-owned login webview injects `GLMConsoleResponseObserver.userScriptSource`, which
wraps `window.fetch` and `XMLHttpRequest` **in that page** and reports, for every JSON
response the console page itself loads: the URL path (query/fragment stripped), the HTTP
method, the request header **names** (never values) and a redacted path/type summary
(depth ≤ 3, ≤ 24 entries, no values). Redaction happens inside the page; the Swift side
re-validates every message and drops anything not matching the redacted shape. The panel
shows these summaries under the GLM section, so the real balance resource and its header
mechanism can be pinned from evidence in the next revision. Tests execute the shipped
script itself in JavaScriptCore and assert the redaction.

### 3.4 Connect flow, observations and the periodic cycle

- Saving either credential triggers its read/probe immediately and publishes the
  observation; the user never has to press 探测一次 to find out whether a fresh
  credential works.
- The selected connection kind (API key or console session) is **persisted** as a
  non-secret mode choice, so a restart keeps using the selected console connection
  instead of silently switching back to an old stored key. Cache identities are derived
  from the credential actually used: `apikey-<fingerprint>` for key reads,
  `console-<capture-millis>` for session reads, so session-derived money can never land
  in a key's cache entry and a relogin reads under its own new identity.
- Observations carry the **real** HTTP status (401/403 → `invalidCredential`, other
  non-2xx → `serverError(status:)`), business code, top-level key names and the redacted
  structure summary. A hard-expired console session is never replayed (HTTP status 0).
- With a confirmed schema, a successful read joins the normal periodic 5-minute cycle;
  an authentication failure suspends automatic retry until the credential is saved again.
- **No balance is ever estimated, converted or fabricated.**

### 3.2 Official console session connection

Only used when the API key is not accepted.

| Item | Rule |
|---|---|
| Webview | `WKWebView` with this app's own `WKWebsiteDataStore.nonPersistent()` |
| Existing browser cookies | never read, never imported; no shared cookie store is consulted |
| Navigation | https on `bigmodel.cn`, `open.bigmodel.cn` or a subdomain only; everything else is cancelled (`GLMConsoleSessionPolicy.isNavigationAllowed`) |
| Captured session | only cookies whose domain is an official host are kept, name/value/domain/expiry only |
| Storage | macOS Keychain, account `glm.console-session` |
| Expiry | earliest hard cookie expiry; expired → prompt to reconnect and stop automatic retry |
| Disconnect | deletes the keychain entry and clears the in-memory copy; the app-owned web data store holds nothing persistent |
| Third parties | the captured session is never sent anywhere except `open.bigmodel.cn` (enforced by the client's origin guard) |
| Model calls | none; the console session is never used to drive a model request |
| Read-only probe | while the contract is unconfirmed, `GLMReading.probe()` may issue one read-only request to the candidate endpoint with the captured cookies; the answer is recorded as an observation (real HTTP status — 401/403 are credential rejections — business code, top-level key names) and never displayed. A hard-expired session is not replayed. The probe runs immediately when the session is saved, not only on an explicit request. |

### 3.3 GLM key storage

- macOS Keychain, account `glm.api-key`, same service name as above.

---

## 4. Cross-cutting transport rules

- **Authenticated requests never follow a cross-domain redirect.** A redirect whose origin
  (scheme, host, port) differs from the request's origin is refused and reported as
  `crossDomainRedirectBlocked`. A scheme change counts as a different origin. The refusal
  is recorded **per request/task**: one refused redirect can never reclassify a later,
  unrelated request's network failure as a blocked redirect (pinned by
  `ProviderRequestGuardTests.testAnUnrelatedNetworkFailureIsNotMisclassifiedAfterARefusal`).
- **Requests may only leave for the configured origin.** A path that resolves to another
  host is refused before any I/O.
- **Model endpoints are unreachable.** Any path containing a model-inference fragment
  (`chat/completions`, `completions`, `responses`, `embeddings`, `messages`, …) is refused
  regardless of the allow-list. This is asserted by
  `ProviderRequestGuardTests.testModelEndpointsAreBlocked` and by a transport-level
  assertion that no recorded request from any provider flow hits such a path.
- **Ephemeral sessions.** No cookie jar, no URL cache, cookies not accepted from the server
  side of provider requests.
- **Fixed failure categories only.** Upstream bodies, headers and messages never reach
  errors, logs, tests or the UI; only numeric statuses and codes survive.
- **Credential placement.** Keys and console sessions live in the macOS Keychain only.
  Business caches hold identifiers and amounts, never credentials.

---

## 5. Verification summary for this round

| Interface | Level | How it was checked |
|---|---|---|
| Codex `account/read` request | A | Real child process fixture asserting the wire params |
| Codex `account/read` response | B | Bundled protocol schema |
| Codex `account/rateLimits/read` | A | Previously verified; unchanged |
| DeepSeek `user/balance` | B | Public documentation + injectable-network tests |
| GLM `v4/balance` (apiBalanceV1) | third-party + user-pending | Strict schema pinned by `GLMProviderTests`; injectable-network tests |
| GLM `query-customer-account-report` (consoleReportV1) | user probe partial | Top-level shape user-confirmed (HTTP 200 + code/data/msg/success only); nested schema pinned by tests, pending real shape |
| GLM console data-source observer | A | Shipped script executed in JavaScriptCore; redaction, query-stripping and caps pinned by tests |
| GLM structure summary | A | Redaction, depth and cap pinned by tests |
| GLM console session policy | A | Pure-logic tests for host, cookie, expiry and cleanup rules |
| Redirect guard | A | Unit tests on the pure rule and on the `URLSession` delegate |

Items that still need a real machine and real credentials are listed in
`docs/archive/v1.0/history/reports/ROUND_4_REPORT.md`。


## 2026-09-10 Codex correction: official console frontend evidence

Primary source inspected directly: https://static.bigmodel.cn/wd-paas-front/js/app.3e959761.js (linked by https://bigmodel.cn/ at inspection time).
This is deployed official frontend code, not a published stable API contract and not a live account response.

- The console HTTP client uses same-origin /api; account-report is a GET under /biz/account/query-customer-account-report. Session reads now target https://bigmodel.cn/api/biz/account/query-customer-account-report. API-key compatibility remains separate on open.bigmodel.cn.
- Module 5f87 reads the login token from the cookie identified by module 22a6 as bigmodel_token_production. The request interceptor copies this token directly to Authorization (without adding Bearer) and includes Bigmodel-Organization and Bigmodel-Project from the page's own localStorage. These values are collected exclusively from the app-owned login context and stored inside its Keychain session. No global browser storage is used.
- Account-report code accesses the six monetary fields directly under data, not an extra balance object. The header renders financeData.balance with yuan currency notation. The corrected flat report parser preserves Decimal and identifies this domestic console contract as CNY. Legacy nested fixtures remain supported but are not evidence of the live format.
- Organization/project context is optional and survives session storage. Ordinary API-key feasibility remains unverified; no conclusion of impossibility is claimed.
- Endpoint/headers/field structure are source-verified. Successful authentication, real balance agreement and session longevity still require the user's app-owned login and live test.
