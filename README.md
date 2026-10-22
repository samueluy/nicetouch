# NiceTouch

An open-source macOS app that lets you configure your trackpad by simply telling it what to do.

Type “When I swipe three fingers left in Chrome, switch to the previous tab.” Review the generated rule, save it, then hold Fn and swipe. NiceTouch uses AI to help you create rules and a local gesture engine to run them.

Native SwiftUI · Apple Intelligence by default · Optional MLX or API models · MIT licensed

**Status: experimental developer preview.** You can build the app from source today. Trackpad capture uses a private macOS API, and physical gesture testing remains a release gate. There is no notarized installer yet. See the [verification log](Docs/VALIDATION.md) for tested behavior and outstanding checks.

[Get started](#installation) · [Try a command](#sample-commands) · [Explore the architecture](#architecture) · [Contribute](#contributing)

## Features

- **Browse prompt suggestions.** Search 12 editable examples for opening apps, browser tabs and editing. Choose a prompt, then review the generated rule.
- **Describe a gesture in plain English.** Specify the app, finger count, motion and action. Review the structured result before saving.
- **Use Apple's on-device model by default.** On an eligible Mac, create rules without installing Python or choosing separate model weights.
- **Choose your model.** Load a custom local MLX model or configure an API endpoint that supports strict JSON-schema Chat Completions.
- **Hold Fn to activate gestures.** Fn is required by default. Press it before touching the trackpad and keep it held through release. You can opt out in settings.
- **Scope rules to an app or all apps.** Use the full trackpad or a left, right, top or bottom edge zone.
- **Catch conflicts before saving.** Assigning the same gesture to previous tab and next tab in the same app blocks the second rule. NiceTouch names the existing assignment.
- **Keep saved gestures independent of AI.** After saving, gesture matching uses local rules without model calls or a network connection.
- **Inspect the rules.** View the JSON, pause capture from the menu bar, and keep your configuration in a local file.
- **Keep NiceTouch in the menu bar.** Closing the window keeps it running without a Dock icon. Opt in to Open at login from the first-launch prompt or Settings.

## Installation

### Requirements

| Component | Requirement |
| --- | --- |
| App | macOS 14 or later; built-in Mac trackpad |
| Development | Xcode 26 or later, selected as the active developer tools |
| Packaged build | Apple Silicon; the build script targets arm64 |
| Default AI provider | macOS 26 or later, eligible hardware, Apple Intelligence enabled and its model ready |
| Custom local AI | Apple Silicon, Python environment, MLX dependencies and compatible model files |
| Keyboard actions | Accessibility access granted to NiceTouch |

The app's macOS 14 minimum does not mean Apple Intelligence is available on macOS 14. Choose a compatible alternative provider when Apple's model is unavailable. Intel support is unverified; selecting an API does not establish trackpad or build compatibility on Intel.

### Build from source

Clone the repository and enter the project directory:

```sh
git clone https://github.com/samueluy/nicetouch.git
cd nicetouch
swift test
zsh Scripts/build-app.sh
open dist/NiceTouch.app
```

The script builds an arm64 app, bundles its resources and applies an ad-hoc signature for local development. It does not create a notarized distribution release. You can also open `Package.swift` in Xcode and run the `NiceTouch` executable scheme, or use `swift run NiceTouch`.

### Create your first rule

1. Open **Model settings**. Keep **Apple Intelligence** selected if the status says ready, or configure another provider below.
2. Open Chrome, then enter: “When I swipe three fingers left in Chrome, switch to the previous tab.” Keeping the target app open helps local providers resolve its bundle ID.
3. Select **Create preview**. Check the app, fingers, direction, zone and action, then select **Save gesture**. The three first-launch examples start disabled.
4. Before testing keyboard actions, place the app at a stable path and grant it access in **System Settings → Privacy & Security → Accessibility**. Changing its path or signature may require granting access again.
5. Disable overlapping macOS gestures in **System Settings → Trackpad**, enable your rule and select **Start gestures**.
6. Hold **Fn / Globe** before placing your fingers on the trackpad. Keep it held until you lift them. Select **Pause gestures** to stop capture.

Pressing Fn midway does not activate an ongoing gesture. Releasing it cancels the sequence. Fn controls NiceTouch actions; it does not disable macOS gestures. Capture pauses on sleep and needs a manual restart after wake.

### Open at login and close behavior

On the first interactive launch of the packaged app, NiceTouch asks whether to open when you log in. Choose **Open at login** or **Not now**. Change the choice in **Model settings → Startup**. If macOS requests approval, use the provided link to **System Settings → General → Login Items**.

Login launches keep the window hidden and show the menu-bar item. Closing the window keeps NiceTouch running; choose **Open NiceTouch** from the menu-bar item to return. Choose **Quit NiceTouch** to stop the app. Gesture capture starts paused, including after login. Open at login requires the packaged `.app` at a stable location and is unavailable through `swift run`.

## Sample commands

Select **Browse suggestions** beside **New gesture** to open the prompt library. Search by app, action or gesture, or filter by Apps, Browser tabs and Editing. **Use prompt** fills the editor; it does not generate, save or enable a rule.

Try one rule at a time and check for overlap with enabled rules:

> Open ChatGPT when I draw a C.

> Open Codex when I draw a C with one finger in all apps.

> When I swipe three fingers left in Chrome, switch to the previous tab.

> When I swipe three fingers right in Chrome, switch to the next tab.

> When I tap four fingers in the top zone in Safari, reopen the closed tab.

> When I swipe four fingers up in all apps, copy.

> When I swipe four fingers down in all apps, paste.

> When I tap three fingers in Safari, undo.

Supported gestures are three- or four-finger swipes and short taps, plus one-finger C drawings. Hold Fn before drawing, leave the C opening on the right, then lift your finger. Either stroke direction is supported. C drawings use a fixed local template matcher; other letters are unsupported and physical recognition still needs hardware tuning. The ChatGPT and Codex C suggestions share a trigger, so choose one or change its scope/gesture. Swipe directions are left, right, up and down. Edge zones use the starting finger centroid in the outer quarter of the trackpad. Direction follows physical motion, independent of natural scrolling.

Supported actions are `previousTab`, `nextTab`, `closeTab`, `reopenTab`, `copy`, `paste`, `undo`, `redo`, `openChatGPT` and `openCodex`. Keyboard actions use fixed Mac shortcuts, so behavior can vary by app. The two app actions open installed macOS applications through fixed bundle identifiers; they do not open a website or accept arbitrary executable paths. If the app is missing, the preview and runtime report it. App-opening commands default to all apps when no source app is named. It does not run scripts, shell commands or model-generated code. Incomplete or contradictory requests ask for clarification; English is the current command-validation language.

## Local AI and model choices

AI runs during rule creation. You review the result before saving. The gesture engine reads saved rules and runs fixed shortcuts or app launches without consulting a model.

### Apple Intelligence: default

NiceTouch uses the on-device `SystemLanguageModel` through Apple's [Foundation Models framework](https://developer.apple.com/documentation/foundationmodels). Enable Apple Intelligence in System Settings and let macOS finish preparing its model. NiceTouch does not bundle or ask you to upload model weights.

The app reports whether the model is ready, disabled or unavailable. It does not switch providers on failure. Model generation can take seconds; it is separate from gesture execution.

### Custom local model: optional

Choose **Custom local model** in settings to run an MLX model from a folder on your Mac. The app communicates with a bundled Python worker over stdin/stdout and uses Outlines for constrained JSON generation.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

Use Python 3.11 or later; the pinned environment was tested with Python 3.13 on macOS 26. Dependency wheels may impose newer requirements than the native app.

Obtain a compatible MLX model and check its license. For example, this command downloads weights from Hugging Face during setup:

```sh
.venv/bin/hf download mlx-community/Qwen2.5-1.5B-Instruct-4bit \
  --local-dir models/Qwen2.5-1.5B-Instruct-4bit
```

Select the virtual environment and model folder in settings, then **Load model**. The folder needs configuration, tokenizer and weights. The worker uses offline mode during inference, disables telemetry and disallows remote tokenizer code. Model quality and compatibility vary; review generated rules.

### API: optional

Choose **API**, enter the base URL and exact model ID, then save your key in Keychain. The endpoint must support OpenAI-compatible Chat Completions with strict JSON-schema output; generic chat compatibility alone is insufficient.

Remote endpoints require HTTPS. HTTP is allowed for loopback servers on your Mac. You can disable the key requirement for a server that does not need authentication. API readiness checks configuration, not connectivity or model compatibility. Provider fees and data policies apply.

### Why Apple Silicon is recommended

Apple Silicon is the current development target, and the packaging script builds for arm64. Apple's on-device AI requires eligible hardware; check [Apple's availability requirements](https://support.apple.com/en-ie/121115) for your Mac. The custom model backend uses [MLX](https://github.com/ml-explore/mlx), which Apple designed for machine learning on Apple Silicon. MLX can use shared CPU/GPU memory without copying arrays between separate memory pools.

More available memory gives you room for larger custom models. NiceTouch does not publish a minimum RAM claim or gesture-latency benchmark yet.

## Privacy

| Mode | Data used for rule creation |
| --- | --- |
| Apple Intelligence | Command, rule instructions and running-app context go to the on-device system model. |
| Custom local MLX | Command, rule instructions and running-app context go to the local Python worker. |
| API | Command, rule instructions/schema and possible repair feedback go to your configured endpoint. NiceTouch excludes the running-app list, saved rules and gesture activity. |
| Saved gesture execution | The local engine matches touch input against saved rules. It makes no AI or network requests. |

NiceTouch has no analytics or account requirement. It stores API credentials in macOS Keychain, scoped to the endpoint. Preferences hold provider settings, not API keys. API redirects fail without forwarding credentials. Cloud inference requires an explicit provider selection.

NiceTouch stores rules at:

```text
~/Library/Application Support/NiceTouch/rules.json
```

The rule store validates the collection and uses atomic writes. If a file is corrupt, NiceTouch preserves it and blocks saving until you resolve the error. Rules do not sync to a cloud service. Local files remain subject to your Mac's access and backup settings.

## JSON rule examples

A rule targets an exact app bundle identifier or `"*"` for all apps:

```json
{
  "version": 1,
  "name": "Previous tab",
  "app": "com.google.Chrome",
  "gesture": {
    "kind": "swipe",
    "fingers": 3,
    "direction": "left",
    "zone": "anywhere"
  },
  "action": "previousTab"
}
```

Taps use `"direction": "none"`. This rule reopens a tab with a four-finger tap at the top edge in Safari:

```json
{
  "version": 1,
  "name": "Reopen closed tab",
  "app": "com.apple.Safari",
  "gesture": {
    "kind": "tap",
    "fingers": 4,
    "direction": "none",
    "zone": "top"
  },
  "action": "reopenTab"
}
```

A one-finger C can open ChatGPT from any app:

```json
{
  "version": 1,
  "name": "Open ChatGPT",
  "app": "*",
  "gesture": {
    "kind": "drawC",
    "fingers": 1,
    "direction": "none",
    "zone": "anywhere"
  },
  "action": "openChatGPT"
}
```

These are rule definitions. The persisted collection wraps each definition with an `id` and `enabled` flag, as shown in [Samples/rules.json](Samples/rules.json). The [JSON Schema](Schema/rule.schema.json) defines the format. Fn activation is an app setting, not a rule field. There is no JSON import UI yet.

Enabled rules conflict when their gesture, app scope and zones overlap, regardless of action. Global rules overlap app-specific rules; perpendicular edge zones overlap at corners. Different directions and opposite edges can coexist. If the runtime still finds ambiguous matches, it sends no action.

## Architecture

```text
CREATE A RULE
Command → selected model → strict JSON + intent checks
        → preview + conflict checks → explicit save → local rule store

RUN A GESTURE
Built-in trackpad → C bridge → Fn sequence gate → gesture recognizer
                  → app + zone matching → fixed shortcut or app launch
```

| Module | Responsibility |
| --- | --- |
| `NiceTouch` | SwiftUI/AppKit interface, preview workflow, local MLX process and runtime coordination. |
| `NiceTouchModels` | Apple Intelligence, MLX adapter, API transport, Keychain credentials and bounded rule repair. |
| `NiceTouchCore` | Rule types, parsing, validation, conflicts, persistence, Fn gating and trajectory recognition. |
| `TrackpadBridge` | Small C adapter that loads private MultitouchSupport functions and filters for built-in trackpads. |

All providers pass through Swift validation. Source checks guard against substituted actions, app scopes and invented gesture details. One repair attempt uses the selected provider; further validation failures expose raw output for review. These checks cannot prove that a model understood every phrasing.

The runtime uses an in-memory rule snapshot. Capture callbacks carry a session token so queued frames from before Pause cannot reach a restarted engine. It performs no model calls, JSON parsing or disk reads while matching gestures. The implementation limits execution to one action per touch sequence, applies a cooldown and cancels execution if the active app changes. Physical verification remains outstanding.

## Known limitations

- **Private macOS API:** trackpad capture may break with OS updates. The current approach is unsuitable for Mac App Store distribution.
- **Hardware testing:** Accessibility approval, physical Fn behavior, gesture recognition and shortcut delivery still need end-to-end verification. There is no measured release latency claim.
- **Built-in trackpads only:** external Magic Trackpads and Intel Macs are unverified or unsupported by the current implementation.
- **System gesture overlap:** NiceTouch observes input and does not consume macOS gestures. Disable conflicting system mappings before testing.
- **Limited vocabulary:** gesture types, finger counts and actions form a fixed set. C is the only supported drawn letter, and app launch targets are limited to ChatGPT and Codex. English source validation can reject phrasing that a model understands. Multilingual command support is unverified.
- **Provider compatibility:** API tests use a stub transport; live third-party endpoints need verification. Custom model behavior depends on weights and Python dependencies.
- **Distribution:** the local app uses ad-hoc signing. Developer ID signing, notarization and an installer remain future work. Light appearance and older supported macOS versions need further checks.

## Roadmap

These are proposed directions, not release commitments:

- [ ] Verify Fn, gesture recognition and shortcuts on real hardware across supported macOS versions.
- [ ] Measure recognition-to-shortcut latency and tune thresholds from recorded touch traces.
- [ ] Add trackpad reconnect handling and investigate external Magic Trackpads.
- [x] Add an opt-in login prompt and hidden menu-bar startup.
- [ ] Add rule import/export with validation.
- [ ] Expand accessibility coverage, command phrasing and localization.
- [ ] Document tested model/server combinations and improve provider diagnostics.
- [ ] Evaluate an in-process MLX Swift backend.
- [ ] Prepare Developer ID signing, notarization and release artifacts.

## Contributing

Start with a focused change. For larger features or runtime changes, open an issue describing the use case and proposed behavior before implementation. Small documentation fixes can go straight to a pull request.

1. Fork the project and create a branch for your change.
2. Build from the project root and run `swift test`.
3. Add regression coverage for changes to parsing, conflict handling, gesture recognition or provider behavior. Use synthetic touch traces and mocked API replies where possible.
4. For UI changes, include before/after screenshots. For hardware fixes, include your Mac model, macOS version, reproduction steps and observed result.
5. Open a focused pull request explaining the problem, the behavior after your change and your validation. State any checks you could not run.

Keep AI out of the gesture execution path. Preserve explicit provider selection, preview-before-save and strict rule validation. Avoid adding API keys, downloaded weights, private rule files or personal app lists to commits.

### Good first contributions

- Contribute light/dark screenshots using the bundled sample rules and remove personal information from captures.
- Add regression cases for zone overlap, incomplete commands or ambiguous action wording.
- Improve VoiceOver labels, keyboard navigation and focus handling in settings.
- Document a tested API endpoint/model combination using redacted configuration and reproducible steps.
- Report built-in trackpad behavior with a small synthetic trace that reproduces a recognizer bug.
- Improve setup errors and troubleshooting for missing Python dependencies or incomplete model folders.

Read the [verification log](Docs/VALIDATION.md) before claiming hardware support. You can work on core tests and documentation without granting Accessibility access. Use `swift run ModelProbe --check-cases` to exercise live Apple Intelligence on an eligible Mac.

## License

[MIT](LICENSE). Model weights and third-party dependencies have their own licenses.
