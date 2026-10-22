# Validation

NiceTouch is an experimental developer preview. Automated checks cover rule creation and runtime logic; physical trackpad and login-session checks remain open.

## Latest local results

2026-10-22–23, Apple Silicon development Mac, macOS 26:

| Check | Result |
| --- | --- |
| `swift test` | 115 tests passed, zero failures. |
| `swift run ModelProbe --check-cases` | Ten live Apple Intelligence cases passed, including ChatGPT/Codex C-drawing rules. |
| `zsh Scripts/build-app.sh` | Release build, ad-hoc signing and packaged resource checks passed. |
| Generation cancellation | In the packaged app, Cancel discarded a live Apple request without a preview/error banner; a subsequent local request produced a valid conflict-checked preview. Editing the command removed that preview and its Save control. |
| C-rule preview | A library suggestion generated a valid one-finger C / Open Codex rule, displayed its C trace and installed-app status, and allowed explicit saving. The test preview was discarded. |
| Save/reload workflow | AppState integration tests save a reviewed definition to a temporary rules file and reload it in a fresh state instance; conflicts and corrupt-file writes remain blocked. |
| Rule conflict preview | A Chrome next-tab rule overlapping an enabled previous-tab rule named the existing assignment and disabled Save. |
| Menu-bar lifecycle | Closing the main window left the process running in accessory mode; reopening displayed the window. |
| Login Items settings | The packaged app reported the registered state from macOS. A full logout/login cycle remains unverified. |

The latest live model checks covered five complete commands with expected app, gesture, zone and action, plus five incomplete, unsupported or contradictory commands that required clarification. Complete-rule generation took about 12–36 seconds in that run. These timings describe rule authoring, not gesture execution, and are not a performance guarantee.

## Automated coverage

- Strict rule parsing, semantic constraints, duplicate keys, app/zone conflicts and collection integrity.
- AppState preview/save/reload integration, conflicting disabled-rule activation and corrupt-file preservation using temporary stores.
- Generation-to-preview/save integration using isolated preferences and a controlled provider that ignores cancellation: editing commands, selecting saved rules, explicit cancellation, preview invalidation and subsequent requests.
- A failed custom local worker clears its ready status. Cancellation avoids repair banners and waits for the provider to finish before another request can start.
- Synthetic touch trajectories, ambiguous matching and persistence failures.
- Runtime integration through injected capture/permission/action services: Fn gating, C launches, app switches, cooldown, permission revocation and capture ownership. These tests send no real keyboard input or app launches.
- Queued native-style frames cannot cross Pause/Start sessions. Removing the session fence makes the regression test dispatch an old gesture; restoring it prevents that dispatch.
- Fn sequence admission, late presses and cancellation.
- Source-intent checks, selected-provider routing and bounded repair.
- All 12 prompt suggestions validate against their stated intent; search/category filtering and conflicting launch suggestions have coverage.
- C recognition from synthetic paths in either stroke direction, noise/scale variation, bounded dense traces, invalid input, extra fingers and rejection of circles/mirrored letters.
- Guided Apple C output and API C-launch replies through full authoring validation.
- API request privacy, malformed replies, redirects and endpoint credential isolation.
- Startup prompt persistence, registration/disable behavior, approval/error states, unpackaged launches and login-event detection.

API tests use a stub transport and fake credentials. Startup tests use a login-item fixture and do not register services. Custom MLX adapter tests cover loading, unloading, unavailable state and context forwarding; they do not establish compatibility with every model or dependency version.

## Reproduce the checks

From the repository root:

```sh
swift test
zsh Scripts/build-app.sh
```

On a Mac with Apple Intelligence ready:

```sh
swift run ModelProbe --check-cases
```

For a custom MLX model, install the optional dependencies described in the README and the smoke-test dependency, then pass your local model directory:

```sh
.venv/bin/python -m pip install jsonschema
.venv/bin/python Scripts/check-model.py /absolute/path/to/model
```

This smoke check calls the local worker; it does not execute keyboard actions or change saved rules. Model quality can cause a check to fail even when the worker loads.

The library UI was checked for search, category filtering, empty results and selecting a prompt without saving a rule. C drawings require physical trackpad verification; synthetic recognition results do not establish hardware accuracy.

## Hardware and release checklist

Record the Mac model, macOS version, build revision and observed behavior when reporting results. Use sample rules and redact personal information.

- [ ] Accessibility approval and fixed keyboard actions in Chrome/Safari.
- [ ] Physical Fn admission, late-press rejection and release cancellation.
- [ ] One-finger C recognition and ChatGPT/Codex app launching with Fn held.
- [ ] Three/four-finger gestures and edge zones on a built-in trackpad.
- [ ] One action per gesture and cancellation after switching apps.
- [ ] Pause/sleep stopping input and manual restart after wake.
- [ ] Release-build recognition-to-key-event latency.
- [ ] Private touch ABI on each supported macOS version.
- [ ] Light appearance and older supported macOS versions.
- [ ] Live strict JSON-schema API compatibility with a configured provider.
- [ ] Full logout/login cycle: hidden startup, visible menu-bar item and window reopening.

The private trackpad API can change across macOS versions. This repository does not provide a notarized distribution release.
