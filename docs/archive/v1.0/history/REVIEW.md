# Review log

Status: Round 1 pending. Live app-server preflight PASS; app, tests, UI comparison not yet implemented or verified. Maximum 5 rounds.

## Round 1 orchestration adjustment
Initial Claude invocation spent approximately 8 minutes in pre-implementation reasoning without writing code. Codex interrupted that owned process, retained its transcript, and resumed the same implementation round with medium effort and a bounded first coding step. This is not a completed review round.

User explicitly requested waiting for Claude Code to finish. Current resumed invocation will not be interrupted for latency.

## 2026-09-09 10:11 +08:00: user-requested readiness review

Decision: NOT READY FOR FORMAL REVIEW; Round 1 remains in progress. This checkpoint does not consume another implementation round.
Evidence: Claude PID 10967 alive; resumed transcript updated at 10:11:46. ROUND_1_REPORT.md, README.md and scripts/build.sh absent. Sources/UsageMonitorApp/main.swift still empty placeholder. CLI currently a Python-fixture debugging program, not production smoke diagnostic. Latest observed debug run timed out awaiting initialize (3 seconds).

Provisional findings to recheck after Claude finishes:
1. UsageService.swift:103-125 resets restart budget each fetch, allowing repeated automatic restart pairs across scheduled fetches. A persistent failure circuit breaker is needed.
2. UsageParser.swift:119 converts arbitrary finite Double to Int without bounds/exactness checking; out-of-range values may trap and fractional duration can misclassify. Line 154 accepts Bool as 0/1 despite rejecting null semantics; invalid percentages must remain unavailable.
3. JSONRPCTransportTests.swift:178-179 assert id inside resultObject, but fixture emits id at the response envelope. Validate response.id.
4. Transport integration remains under active debugging; re-run full suite only after source is stable. No independent build/test PASS is awarded here.

Per user cost preference: no background polling or premature full tests. Leave Claude running without interruption; await completion notification/user request before formal review.

## REVIEW ROUND 1 (2026-09-09 14:35 +08:00, independent Codex review)

Build: PASS. scripts/build.sh exit 0; release app signed and plist valid. artifacts/codex-review-1-build.log.
Tests: PASS for existing 54 tests, exit 0. artifacts/codex-review-1-tests.log. Additional reviewer probes FAIL; suite coverage is incomplete.
Runtime: PARTIAL, app launched PID 55892 with child 55896. CUA twice timed out (-10005), so visible menu/panel/manual refresh not verified.
Real Usage: PASS. Production CLI 14:35:13 returned 5H remaining 92%, weekly 80%; resets 2026-09-09 19:33:56 +08:00 and 2026-09-15 14:29:26 +08:00. Owned CLI child 55793 cleanup verified. artifacts/codex-review-1-live.log. This does not replace official UI comparison.
Security: FAIL for unrestricted remote error text entering diagnostics; no direct auth-file access or third-party usage upload found in source inspection.
Acceptance: FAIL.
Decision: REVISION REQUIRED. Project NOT COMPLETE.

Blocking Issues:
1. [P1] UsageParser.swift:119 (also numeric error-code conversions): finite out-of-range Double is converted with Int and traps. Independent subprocess with duration=1e100 exits -5 with Swift fatal error. Reject values outside integer range, fractional/nonpositive durations, booleans; do not merely catch thrown errors because this is a trap. Probe also confirms true becomes remaining=99 and duration=300.9 becomes fiveHour. Evidence artifacts/ReviewProbe.swift, codex-review-1-probes.log, codex-review-1-overflow.log.
2. [P1] UsageService.swift:103-125: restart count resets each fetch. Three consecutive failing automatic fetches instantiated SIX clients in independent fake-client probe. Stop automatic launches after initial attempt plus one restart in a continuous failure episode; explicit manual retry may reset budget. Add multi-fetch regression tests, keep cached data visible.
3. [P1] UsageService.swift:133-158 and UsageViewModel.swift:70/102: stop races acquire/start, and detached task is not cancelled or joined. Deterministic semaphore probe called stop while start was paused, then released start: client remained running after stop returned. Serialize lifecycle and block late publication/restart; stop/cancel in-flight work and clean a late child. Test stop during initial start, restart delay, and read, not only idle quit.
4. [P2] UsageParser.swift:74: legacy limitId is never validated. Independent input rateLimits.limitId=other with 300-min primary is accepted as Codex. Respect bucket identity; never use foreign legacy or fallback past an explicitly unavailable preferred codex bucket. Add regression cases for empty/null codex plus legacy.
5. [P2] JSONRPCClient.swift error normalization -> UsageService.swift:116 / UsageViewModel.swift:111-112 / CLI:67: arbitrary server error message is copied into debugSummary and logs, despite lifecycle-only logging promise. Use fixed error categories/codes and redact sensitive details before storage/display. Verify with synthetic token/header sentinel, never real credentials.
6. Official Usage UI comparison and visible application UI remain unverified. Previous official UI access restriction remains; user screenshot or user-led logged-in browser required. Do not claim PASS based on same backend twice.

Non-blocking Issues:
- CLI prints PASS/exits 0 even when cache roundtrip or cleanup fails; build.sh masks codesign verification failures. Make diagnostics fail closed so exit codes can serve as evidence.
- Report/comment asserts DispatchQueue sync barriers never work, but no isolated proof establishes that causal claim. Remove or qualify unverified explanation; retain observed transport hang and tested fix only.
- View model can label isLive=false/error=nil cache as live; make source authoritative and add view-model test.

Scope review: native macOS MVP, no extra cloud/iPhone implementation. Reviewer's probe is QA only; implementation remains Claude Code's responsibility. Prior incorrect nested-id assertions were fixed in final tests.

Round 2 task: fix code blockers 1-5, supporting diagnostic/cache issues and regression tests. Preserve UI comparison as pending. Complete build/test, real smoke and lifecycle verification, write ROUND_2_REPORT.md. Do not lower DoD.

## REVIEW ROUND 2 (2026-09-09 15:25 +08:00)

Scope: macOS MVP preserved. Round 2 report and terminal completed marker verified; Claude process finished.
Build: PASS. Independently ran scripts/build.sh; signature/plist passed. artifacts/codex-review-2-build.log.
Tests: PASS existing 86 tests (0 failures). artifacts/codex-review-2-tests.log. Additional reviewer probe reveals remaining lifecycle/retry gaps.
Runtime: PARTIAL. Production CLI passes; visible app/manual refresh and official Usage comparison remain unverified. Previous CUA timeouts/restriction not bypassed.
Real Usage: PASS. Independent 15:25:25 fetch: 5H remaining 77%, weekly 78%; resets 2026-09-09 19:33:56 +08:00 and 2026-09-15 14:29:27 +08:00. CLI child PID 67306 gone/reaped. artifacts/codex-review-2-live.log.
Security: PASS for reviewed production error paths: remote messages converted to fixed categories, diagnostics redacted, no direct credential access found.
Acceptance: FAIL.
Decision: REVISION REQUIRED. Project NOT COMPLETE.

Verified fixes:
- Independent adapted probe rejects bool, fractional duration and foreign legacy bucket; duration=1e100 exits 0 without trap.
- Three consecutive handshake/read failures now create 2 clients (was 6).
- After allowing in-flight start to finish, late client is stopped.
- Error categories, source-authoritative display and fail-closed build/CLI evidence improved.
Evidence: artifacts/ReviewProbeRound2.swift and artifacts/codex-review-2-probes.log. This is Codex's own rerun, not just Claude's claims.

Remaining blocking code issues:
1. [P1] UsageService.swift:176 calls acquireClient BEFORE the do/catch handling restart budget. When start() throws appServerStartupFailed, no circuit breaker is opened. Independent three-fetch launch-failure probe produced 3 attempts, breaker=false. Include factory/start/handshake/read failures in one bounded recovery state machine; classify nonrestartable failures separately. Add tests for start throw and factory throw across multiple scheduled fetches. Also remove the newly introduced automatic 600-second budget reset: the plan permits only one automatic restart and explicit manual retry; unlimited new episodes every 10 minutes still violate that bound. Use injected clock test over multiple cooldown intervals to verify no unrequested launches.
2. [P1] UsageService.stop and UsageViewModel.stop do not drain/join in-flight work. Probe prints fetch finished when stop returned=false. Existing test releases the blocked start AFTER stop and waits for fetchDone, so it proves eventual cleanup only. Production JSONRPCClient.start runs Process.run at line 88 before publishing self.process at 94; stop in that interval sees nil, while app termination may exit before late cleanup executes. Cancel alone does not stop a synchronous detached fetch. Implement a shutdown-completion protocol: transport serializes launch/stop, app defers termination until cleanup/in-flight work is quiescent (bounded, without deadlocking main actor). Regression test should model parent termination immediately after shutdown completion with a real owned child; verify no survivor. Do not claim an observed production orphan: confirmed evidence is missing quiescence plus identified production race window.
3. Official UI comparison and visible menu/panel/manual-refresh acceptance still open; needs user screenshot or permitted live UI access. Do not treat two backend calls as UI comparison.

Non-blocking:
- Compiling core directly for reviewer probe emits UsageParser.swift:87 Any? -> Any warning; eliminate optional coercion explicitly. Standard incremental package build did not emit this warning, so do not conflate the two observations.
- Correct comments claiming stop joins work until it actually does.

Round 3: narrowly fix the two lifecycle/retry blockers and warning, preserve verified behavior, rerun full suite/build/live smoke once. Maximum rounds remains 5. No Codex polling while Claude implements.

## REVIEW ROUND 3 (2026-09-09 16:16 +08:00)

Build: PASS. Independent scripts/build.sh exit 0; signing and plist validated. artifacts/codex-review-3-build.log.
Tests: PASS. Independent swift test: 95 tests, 0 failures, exit 0. artifacts/codex-review-3-tests.log. Direct swiftc reviewer probe compiles without warnings. Source hashes captured in artifacts/codex-review-3-source-hashes.json.
Runtime: PASS for actual launch, production fetching, scheduled refresh and normal termination. Visible menu/panel/manual-click acceptance still pending.
Real Usage: PASS. Independent production CLI fetched at 16:15:07 +08:00: 5H remaining 64%, weekly 76%; resets 2026-09-09 19:33:56 +08:00 and 2026-09-15 14:29:26 +08:00. Child 74038 reaped. artifacts/codex-review-3-live.log.
Security: PASS within reviewed source/test scope; prior fixed-category error and credential boundaries retained. No claim of a formal security audit.
Process: PASS tested paths. App PID 74017 ran with single observed child 74031; exited 0 on SIGTERM and child no longer exists. App log contains successful startup fetch at 16:15:06 and timer fetch at 16:16:06. Intermediate fetches at 16:15:43/45 also occurred; their UI trigger was not independently observed and is not counted as manual-button acceptance. artifacts/codex-review-3-app.log.
Acceptance: FAIL / pending user-visible checks.
Decision: REVISION REQUIRED for outstanding acceptance evidence only; no Round 4 coding task dispatched.

Previous blocking code findings verified resolved in tested scenarios:
- Independent artifacts/ReviewProbeRound3.swift rejects bool/fractional/foreign-bucket cases and runs overflow mode without trap.
- Three handshake/read failures create 2 clients; three start failures also create 2 clients with breaker=true.
- Shutdown probe now reports fetch finished when stop returned=true and late client running=false.
- Source confirms factory/start are inside recovery handler; clock never automatically resets budget; launchLock serializes process creation and stop; service waits for in-flight work before normal completion.
- Suite includes failure budget/time-advance and actual child shutdown regressions. Evidence: artifacts/codex-review-3-probes.log.

Blocking Issues (acceptance evidence):
1. Visible menu title/panel layout and manual Refresh button behavior have not been independently observed. Prior CUA calls timed out; logs alone do not satisfy visual acceptance.
2. Same-account official Usage UI comparison of 5H, weekly and resets remains unperformed. Need user screenshots from official Usage and app panel close in time, or permitted live UI access. Prior app-access restriction must not be bypassed.

Non-blocking limitations:
- Shutdown is bounded; pathological OS/process-launch stalls and the forced timeout branch are not proven orphan-free. No survivor occurred in the tested normal/in-flight paths. Do not broaden those results into an all-failures guarantee.
- Some tests named launch-race start the transport synchronously before stopping, so their name overstates coverage; launch serialization was also reviewed directly and service-level concurrent tests pass.

Project state: IMPLEMENTATION REVIEW PASSED FOR TESTED SCOPE; FINAL DECISION NOT COMPLETE pending the two acceptance checks. Rounds used: 3/5. Do not run extra coding rounds merely to fill the budget. Respect user preference: no Claude waiting/polling model calls.


## Round 7 independent review (2026-09-10)

Decision: REVISION REQUIRED. Existing suite passes; GLM real-account acceptance remains pending.
Independent verification: `swift test`: 243 tests, 0 failures, 6.714 seconds; `swift build -c release`: PASS; existing dist/UsageMonitor.app codesign verification: PASS. Logs: /tmp/usagemonitor-review7-tests.log and /tmp/usagemonitor-review7-build.log. No real credentials read; no live balance request or focus reproduction performed by reviewer.

Required findings for Claude Code:

1. [P1] Persist credential selection and derive cache identity from the credential actually used. ProviderReadings.swift:70,147-153,218,341: preferredProbeCredential is memory-only, so saving a console session after an unsuccessful API Key works only until restart. A new reader defaults to API Key whenever both exist. readWithSession calls accountIdentifier(), which also prefers the stored API Key, assigning session-derived money to the wrong credential cache. Persist a non-secret connection-mode choice and use a session-specific identity when using the session. Add reconstruction tests with both credentials present, including distinct fixture accounts and failed requests after switching modes.

2. [P2] Classify authentication business errors. GLMProvider.swift:280-284 maps every HTTP-200 error code to businessError; ProviderFailure.isAuthenticationFailure accepts only invalidCredential. Thus HTTP-200 code 401/403 is not reported as invalid credentials and does not suspend polling. The report claims this is implemented. Introduce an evidence-backed mapping for known authentication business codes, preserve unknown codes as businessError, and test engine suspension plus reconnect recovery.

3. [P2] Preserve available-only amount semantics. GLMProvider.swift:429-433 and 498-503 copy available into total and set available=nil when only available exists. DecimalFormatting.swift:49 then labels it 总额. Do not invent a total from an available-only response; model missing total explicitly or retain an explicit primary amount kind. Cover both endpoint schemas and cache/formatting behavior.

4. [P2] Reject present-null fields as required by the declared strict contract. GLMProvider.swift Payload optional amount properties use synthesized decodeIfPresent, so null is treated as missing. A response with total_balance=100 and available_balance=null currently succeeds and substitutes total as the main balance, contrary to ROUND_7_REPORT's claim that present-null amounts fail. Distinguish absent from explicit null in decoding. Test mixed valid/null fields; the existing all-null-only test does not cover this case.

Confirmed useful changes: successful local saves clear and collapse form; feedback lives outside the form; GLM numbers use direct Decimal decoding; release compilation and existing tests pass. Input focus change is source-reviewed only, not a demonstrated UI fix.

Evidence correction: the previous Round 7 task overstated the screenshot. It proves HTTP 200 and top-level code/data/msg/success only, not successful authentication, nested money fields, units, or balances. Third-party snippets and synthetic tests are not independent proof of this account's endpoint contract. Real GLM balance and unit comparison against its console remains an explicit acceptance requirement.


## Round 8 independent review (2026-09-10)

Decision: REVISION REQUIRED; console balance integration NOT ACCEPTED.
Independent commands: swift test PASS (259 tests, 0 failures, 7.170 seconds); swift build -c release PASS; codesign --verify dist/UsageMonitor.app PASS. Logs /tmp/usagemonitor-review8-tests.log and /tmp/usagemonitor-review8-build.log. No real credentials read, no live console login or balance comparison performed.

Previous findings: connection mode now persisted and session cache identity separated; numeric/string 401/403 business errors classified; available-only semantics retained; present-null amount fields rejected. These fixes pass existing tests. Authentication-code evidence remains limited to the explicitly mapped values.

Required revisions:
1. [P1] ConsoleWebView.swift captureCookies is called only from navigation-response policy, before document execution. Login completed by fetch/XHR and SPA route changes can set authenticated cookies without another document navigation. There is no cookie-store observer or final fresh capture; ProviderViews.swift 完成连接 saves the old capturedSession and closes even if save fails. Add cookie-store observation or an awaited fresh getAllCookies at completion, propagate storage failure and keep the window open on failure. Test cookies changing after initial document load and completion saving the latest session. This is a source-established failure scenario, not a claim about the live site's currently observed login flow.
2. [P1] ProviderRefreshEngine.swift:189-205,234-242,288-309: invalidateAttribution clears identity but leaves the old in-flight task. Reconnect reuses that task; its eventual result unconditionally writes the old accountID and money back. Add a per-provider credential generation and discard outdated success/failure/cache writes; a new credential must start its own read. Test delayed account A request followed by saving session B, then A completing after B. Cancellation alone is insufficient if transport ignores cancellation.
3. [P2] GLMConsoleResponseObserver.swift sanitizePath retains URL fragments on absolute URLs without a query and can retain userinfo. Script/Swift path and field-name validation cannot support the report's blanket claim that arbitrary messages cannot leak values. Normalize with URLComponents removing query, fragment, user and password; restrict observation to relevant official resources and bound/sanitize field paths, URL paths and header names before message posting, not just after. Test a synthetic absolute URL with a fragment sentinel and ensure it is absent. Do not log real data to test this.

Core acceptance gap: new fetch/XHR observer supplies path/type metadata only. readWithSession still uses the pre-existing fixed account-report endpoint and Cookie header; no observed real endpoint/field/unit evidence, additional-auth adaptation or DOM balance reader has been delivered. Report section 1.2 admits this, so implementation-complete must not imply the user's console-balance objective is complete. After code defects are fixed, one user login in the app-owned window and examination of relevant redacted diagnostics is needed, followed by actual adapter completion and same-account balance/unit comparison. Diagnostics-only delivery is partial progress.

API configuration remains present. This does not violate the conditional deletion instruction by itself: no evidence establishes API impossibility. Continue prioritizing the console path and do not spend another round guessing API endpoints. No implementation changes or Claude invocation were made during this review.


## Round 8 follow-up status review (2026-09-10, after report section 9)

Decision: NOT COMPLETE. Independent swift test: 268 tests, 0 failures (8.945 seconds); release compilation and existing bundle signature verification PASS. Logs: /tmp/usagemonitor-review8b-tests.log and /tmp/usagemonitor-review8b-build.log.
Cookie completion now awaits a fresh app-owned store capture and retains the login window on save failure. URL sanitization and credential generation checks have been added. These are meaningful implementation improvements.
Remaining code issue [P1]: ProviderRefreshEngine.swift:313-330 checks generation under one lock then releases it before acquiring another lock to write state, and writes cache outside that lock. A credential change/disconnect between check and write still permits stale state/cache publication; failure branches have the same check-then-record gap. Validate generation and apply state/cache effects atomically with credential invalidation, and guard returned results/publication appropriately. Existing tests cover A completing after B but do not force a change between validation and commit.
Core requirement remains unfulfilled: readWithSession still reads the fixed account-report endpoint; observations only expose metadata. ROUND_8_REPORT.md section 9.5 explicitly says real endpoint/field/unit validation and any necessary auth/DOM adaptation are pending. A live app-owned console login and same-account balance comparison are required; no live balance evidence was obtained in this review. API Key configuration remains; impossibility not established. Do not describe diagnostic readiness as completed GLM balance integration.


## Codex direct revision / Round 9 (2026-09-10)

At the user's explicit request Codex implemented application fixes directly.
Verified official deployed frontend source and documented it in PROVIDER_ENDPOINTS.md: console token must populate Authorization, console uses same-origin bigmodel.cn, and report monetary fields live directly under data. Added organization/project context from the app-owned WebView and leading-dot cookie-domain handling. Updated flat report parser and CNY evidence. API compatibility retained collapsed; no unsupported claim that all API-key approaches are impossible.

The generation race is fixed with one synchronous critical section spanning validation, state and cache commit; disconnect and report snapshots share its lock. A deterministic timestamp-hook/disconnect regression verifies stale cache cannot reappear. Success feedback is derived from current engine state. Invalid empty results are rejected before changing success/cache state.

Final independent command results: swift test PASS, 274 tests, 0 failures (9.289 seconds); scripts/build.sh PASS including ad-hoc signing and plist verification; no warning/error entries in final logs. Logs: /tmp/codex-round9-test.log and /tmp/codex-round9-build.log. Replaced only the verified running UsageMonitor process with rebuilt dist/UsageMonitor.app via graceful termination and open. Other agent processes not touched.

Status: code and fixture integration VERIFIED; real GLM monetary comparison and interactive focus behavior NOT VERIFIED. Native app inspection through computer-use timed out. New app is opened for user login. No real credentials printed or read by review tools. Need user to complete login in app-owned console and compare live balance; do not claim final real-account acceptance before that result.


## User live GLM evidence and panel cleanup (2026-09-10)
User screenshots confirm connected state and displayed GLM balance 22.29921165 CNY, recharge 50, spend 27.70078835. This confirms the real connection/display path; independent console comparison and long-term session validity remain unverified. Fixed excessive diagnostic content by putting console observations inside a collapsed Advanced Diagnostics disclosure with bounded scroll height, and removed the duplicate updated footer. Build/signature/plist checks passed; rebuilt app restarted. No money precision change.
