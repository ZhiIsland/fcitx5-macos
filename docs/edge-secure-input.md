# Edge and stale Secure Input

This fork adds an Edge-specific workaround for normal text fields that remain
stuck in English while macOS Secure Input is still enabled for Edge. It does not
disable Secure Input or change `AllowInputMethodForPassword`.

## How it works

For `com.microsoft.edgemac`, when Secure Input belongs to the client app, check
the current native accessibility focus on each event instead of treating every
field in the browser as a password field. Read only the application/field roles,
subrole, owning process, and focus metadata. Do not read field values, selected
text, or the document to make this decision.

Only a recognized plain text field, text area, or search field releases Fcitx's
password mode. A secure text field, unknown role, inaccessible browser, timeout,
focus mismatch, or missing Accessibility permission retains password mode.
Nothing is cached across key events. Password-only system apps and applications
other than Edge keep their existing behavior.

Reading the application role also asks Chromium to activate native web
accessibility, as implemented by `BrowserCrApplication::accessibilityRole`.
No browser extension, cloud service, browser debugging port, or key logger is
required by the workaround.

## Build and checks

The patch can be applied to upstream 0.4.1. Follow the repository build guide,
with key logging explicitly disabled:

```sh
./scripts/patch.sh
cmake -B build/arm64 -G Ninja -DCMAKE_BUILD_TYPE=Debug -DKEY_LOGGING=OFF
cmake --build build/arm64
ctest --test-dir build/arm64 --output-on-failure
```

`SecureInputSwift` checks the stale-input focus sequence, actual password field
classification, inaccessible/missing metadata, unknown subroles, password-only
apps, and another app owning Secure Input.

For native browser checks, serve `tests/secure-input.html` from a loopback HTTP
server in a separate, temporary Edge profile. Use actual native mouse focus:
DevTools focus alone can leave the macOS address bar focused. Check password,
plain text, multiline, password again, and search. Repeat with Secure Input
staying enabled. An inaccessible field must stay protected until its metadata
becomes available. Close only the test browser and the local server afterward.

## Installation and limitations

System installation is the manual sudo step described in `AGENTS.md`. Back up
the existing app before replacing it, then restart Fcitx5 using its menu.

In System Settings > Privacy & Security > Accessibility, allow the installed
`/Library/Input Methods/Fcitx5.app`. The workaround falls back to the existing
behavior without this permission. Custom signing or replacing an existing app
can require granting the permission again. Leave **Allow input method in password
fields** disabled.

The workaround is scoped to Edge's stable bundle identifier. It depends on
Edge reporting truthful and timely accessibility metadata; custom controls or
an unresponsive accessibility tree can still require restarting the browser.
Native field probes and regression tests do not replace an installed IME typing
test. Before using the custom build daily, verify Chinese input and Shift
switching in a normal field and ASCII-only behavior in a dummy password field.
Do not use a real password for testing.

Reinstall the backed-up app and restart Fcitx5 to roll back. Rime schemes and
user dictionaries are outside the app bundle and are not modified by this patch.
