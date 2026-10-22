# Validation

NiceTouch is an experimental developer preview. Automated checks cover rule creation and runtime logic; physical trackpad and login-session checks remain open.

## Latest local results

2026-10-22, Apple Silicon development Mac, macOS 26:

| Check | Result |
| --- | --- |
| `swift test` | 76 tests passed, zero failures. |
| `swift run ModelProbe --check-cases` | Eight live Apple Intelligence cases passed. |
| `zsh Scripts/build-app.sh` | Release build, ad-hoc signing and packaged resource checks passed. |
| Rule conflict preview | A Chrome next-tab rule overlapping an enabled previous-tab rule named the existing assignment and disabled Save. |
| Menu-bar lifecycle | Closing the main window left the process running in accessory mode; reopening displayed the window. |
| Login Items settings | The packaged app reported the registered state from macOS. A full logout/login cycle remains unverified. |

The live model checks covered three complete commands with expected app, gesture, zone and action, plus five incomplete, unsupported or contradictory commands that required clarification. Complete-rule generation took about 11–20 seconds in that run. These timings describe rule authoring, not gesture execution, and are not a performance guarantee.

## Automated coverage

- Strict rule parsing, semantic constraints, duplicate keys, app/zone conflicts and collection integrity.
- Synthetic touch trajectories, ambiguous matching and persistence failures.
- Fn sequence admission, late presses and cancellation.
- Source-intent checks, selected-provider routing and bounded repair.
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

## Hardware and release checklist

Record the Mac model, macOS version, build revision and observed behavior when reporting results. Use sample rules and redact personal information.

- [ ] Accessibility approval and fixed keyboard actions in Chrome/Safari.
- [ ] Physical Fn admission, late-press rejection and release cancellation.
- [ ] Three/four-finger gestures and edge zones on a built-in trackpad.
- [ ] One action per gesture and cancellation after switching apps.
- [ ] Pause/sleep stopping input and manual restart after wake.
- [ ] Release-build recognition-to-key-event latency.
- [ ] Private touch ABI on each supported macOS version.
- [ ] Light appearance and older supported macOS versions.
- [ ] Live strict JSON-schema API compatibility with a configured provider.
- [ ] Full logout/login cycle: hidden startup, visible menu-bar item and window reopening.

The private trackpad API can change across macOS versions. This repository does not provide a notarized distribution release.
