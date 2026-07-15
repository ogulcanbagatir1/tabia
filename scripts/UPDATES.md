# Auto-updates with Sparkle

Tabia ships outside the Mac App Store, so updates are delivered with
[Sparkle](https://sparkle-project.org). This is already wired up in the app:

- **Sparkle 2.x** is a Swift Package dependency of the `Tabia` target and the framework is embedded.
- `Info.plist` has **`SUFeedURL`** (the appcast) and **`SUPublicEDKey`** (the update-signing public key).
- Automatic background checks are on (`SUEnableAutomaticChecks`, daily interval).
- The app menu has **Tabia ▸ Check for Updates…** (wired to `UpdaterViewModel`).

You don't need any paid service. The only "hosting" is a place to put two files per release — we
use **GitHub Releases** on `github.com/ogulcanbagatir1/tabia`.

---

## 🔑 The signing key — back it up NOW

`generate_keys` (already run) created an EdDSA key pair:
- **Public key** → in `Info.plist` as `SUPublicEDKey` (`rUx250S0ftxLcCkqx/MeRe8hEw6TTRevWiSpBD4Tbzc=`).
- **Private key** → stored in your **login keychain** (item *"Private key for signing Sparkle updates"*).

**If you lose the private key, you can never ship another update** (users only trust updates signed by
the matching key). Export and store it somewhere safe (password manager):

```sh
# Print the private key so you can save it offline:
"$(find ~/Library/Developer/Xcode/DerivedData -path '*/sparkle/Sparkle/bin/generate_keys' | head -1)" -x sparkle_private_key.txt
#   → writes the private key to sparkle_private_key.txt. Store it safely, then delete the file.
# To restore on a new machine:  generate_keys -f sparkle_private_key.txt
```

---

## Per-release flow

1. **Bump the version.** In the target's build settings (or Info.plist), raise
   `CFBundleShortVersionString` (e.g. 1.0.0 → 1.1.0) and `CFBundleVersion` (must strictly increase —
   Sparkle compares this).

2. **Build, notarize, and generate the appcast — one command:**
   ```sh
   ./scripts/notarize.sh
   ```
   After notarizing + stapling it produces, in `build/notarize/`:
   - `Tabia-<version>.zip` — the stapled app archive
   - `appcast.xml` — the signed update feed (enclosure points at the GitHub release URL, EdDSA-signed)

   (Requires the one-time Developer ID + notary setup in `NOTARIZE.md`, and that you've built once in
   Xcode so SPM fetched Sparkle's `generate_appcast` tool. Override its path with `SPARKLE_BIN=…`.)

3. **Publish the GitHub release.** Create a release tagged **`v<version>`** (e.g. `v1.1.0`) and upload
   **both** files as assets:
   ```sh
   gh release create v1.1.0 \
     "build/notarize/Tabia-1.1.0.zip" \
     "build/notarize/appcast.xml" \
     --title "Tabia 1.1.0" --notes "What's new…"
   ```
   That's it. Running apps check `SUFeedURL`
   (`…/releases/latest/download/appcast.xml`), which always resolves to the newest release's
   `appcast.xml`, see the new version, download the signed zip, verify it, and install.

---

## Notes

- **Feed URL choice.** We use `releases/latest/download/appcast.xml` so no separate web host / GitHub
  Pages is needed. The `--download-url-prefix` in `notarize.sh` must match the release tag
  (`v<version>`); it's derived from the app version automatically.
- **Multi-version appcast (optional).** `generate_appcast` builds the feed from every archive in the
  folder you point it at. For delta updates or to keep old versions listed, keep all
  `Tabia-<version>.zip` files together in one directory and run `generate_appcast` on that directory.
  For simple full updates, the single latest zip is enough.
- **Testing an update.** Build a `v0.9` locally, then a `v1.0`, host the appcast, and confirm the
  0.9 app offers the 1.0 update. Sparkle also has a UI test mode (`SUUpdater` logging).
- **First release.** The very first public build has nothing to update *from*; auto-update starts
  mattering from the second release onward. Ship v1.0 normally (notarized), then use this flow for v1.1+.
