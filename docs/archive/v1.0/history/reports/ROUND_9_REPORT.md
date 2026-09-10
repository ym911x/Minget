# Codex direct revision, 2026-09-10

Implemented directly by Codex at user request; no Claude invocation.

## Root cause and repair

Official deployed frontend source supplied evidence missing from earlier rounds. Actual console requests use same-origin bigmodel.cn, copy the login cookie token into Authorization and include the selected organization/project. Monetary values are directly under data. Prior code replayed only Cookie to open.bigmodel.cn and expected data.balance to be an object. Corrected all three, preserving existing API-key compatibility as a collapsed secondary entry. No proof of API impossibility is claimed.

App-owned cookie capture now also persists the two explicit account-context keys from its own WebView. Leading-dot cookie domains are normalized. No existing browser data, global authentication, model requests or third-party credential forwarding are used. The request still passes the existing origin and endpoint guard.

Fixed stale-result race: synchronous commit holds one recursive lock across generation validation, state changes, cache writes and result creation. Disconnect/cache removal and report snapshots use the same lock. Failure commits are similarly guarded; superseded refresh return values are checked again. Credential changes clear the full old state and retire the prior request slot. ViewModel derives completed feedback from current engine state.

Control console login is now the first connection action; unverified API Key compatibility is collapsed. Successful GLM balances no longer show the low-level probe summary by default.

## Verification

Added official-flat-schema Decimal/CNY tests, null and business-error rejection, token-header/context Keychain serialization tests, encoded control-character rejection, a production ViewModel connection test from session to displayed balance, and a commit/disconnect regression test. All use synthetic credentials and values.

Final results: 274 tests passed, 0 failures (9.289 seconds); scripts/build.sh passed including signature/plist checks. Final logs contain no compiler warnings or errors. Rebuilt app was opened after gracefully stopping the verified old UsageMonitor process. Computer-use inspection timed out, so UI focus and real account balance are pending. Build artifact: dist/UsageMonitor.app.

## Remaining user verification

Live login and real-account balance have NOT been claimed as verified. Open the rebuilt app, use GLM → 连接 → 控制台登录, finish login and then 完成连接. Compare the displayed CNY amount with the same console account. If the server refuses authentication or changes structure, the app reports failure rather than inventing a balance. API Key is not needed for this console flow.
