# Notarizing Tabia for direct distribution

Tabia ships **outside the Mac App Store** (Developer-ID, non-sandboxed, so it can download
and run an external UCI engine). For macOS Gatekeeper to open it on other people's Macs
without the "unidentified developer" block, the app must be **signed with a Developer ID
certificate, notarized by Apple, and stapled**. This is a one-time setup, then a single command
per release.

The Hardened Runtime is already enabled and the entitlements are already configured — you only
need the certificate + credentials below.

---

## One-time setup

### 1. Apple Developer Program
You already have a team (`67U3MGM2PW`). Notarization requires an active **Apple Developer
Program** membership ($99/year). No separate service or account beyond that is needed —
notarization itself is free and unlimited.

### 2. Developer ID Application certificate
This is the certificate that signs apps for distribution outside the App Store.

- **Xcode:** Settings → Accounts → select your team → **Manage Certificates…** → **+** →
  **Developer ID Application**. It's created and installed into your login keychain.
- Verify it exists:
  ```sh
  security find-identity -v -p codesigning | grep "Developer ID Application"
  ```
  You should see one line with your name/team.

### 3. An app-specific password
Notary submissions authenticate with an **app-specific password** (not your Apple ID password).

1. Go to <https://appleid.apple.com> → Sign-In and Security → **App-Specific Passwords** → **+**.
2. Name it e.g. `Tabia Notary`, copy the generated password (`xxxx-xxxx-xxxx-xxxx`).

### 4. Store the credentials in the keychain (once)
```sh
xcrun notarytool store-credentials TabiaNotary \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id 67U3MGM2PW \
  --password "xxxx-xxxx-xxxx-xxxx"
```
`TabiaNotary` is the profile name the script expects. That's it for setup.

---

## Every release

```sh
./scripts/notarize.sh
```

It archives (Release) → exports with Developer ID → verifies the signature + Hardened Runtime →
submits to Apple and waits → staples the ticket → runs a final Gatekeeper check. On success you
get a stapled `build/notarize/export/Tabia.app` and `build/notarize/Tabia-notarized.zip` ready
to distribute (put the `.app` in a `.dmg` or ship the zip).

Override the profile name if you used a different one:
```sh
NOTARY_PROFILE=MyProfile ./scripts/notarize.sh
```

---

## Verifying on a clean Mac
On another Mac (or after `xattr -w com.apple.quarantine ...`), the notarized+stapled app should
open with a normal "downloaded from the internet" prompt, **not** the "unidentified developer" /
"cannot be opened" block. Quick check:
```sh
spctl -a -vvv -t exec /path/to/Tabia.app     # → "accepted, source=Notarized Developer ID"
stapler validate /path/to/Tabia.app          # → "The validate action worked!"
```

## ⚠️ The one runtime gotcha to test: the downloaded engine
Tabia downloads Stockfish at runtime. A binary downloaded by the app carries a
`com.apple.quarantine` attribute, and under Hardened Runtime Gatekeeper can refuse to exec it.
Before shipping, **test the full engine download + first analysis on a clean Mac** (this is
launch item #4). If the engine won't launch there, the fix is for the app to either:
  - strip quarantine after download: `xattr -d com.apple.quarantine <engine>`, or
  - ad-hoc re-sign the engine: `codesign --force --sign - <engine>`,
done in `StockfishEngine` right after the download completes. Verify before release.
