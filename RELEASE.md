# Release Process

## Manual release (current)

1. Build, sign, and notarize:

```bash
make build
SCRAWL_CODESIGN_IDENTITY="Developer ID Application: Jack Temple (4RUT26EY4D)" \
  SCRAWL_SKIP_BUILD=1 ./scripts/install-app.sh /tmp/scrawl-release

cd /tmp/scrawl-release
ditto -c -k --sequesterRsrc --keepParent Scrawl.app /tmp/Scrawl-<version>.zip

xcrun notarytool submit /tmp/Scrawl-<version>.zip \
  --apple-id temple2697@gmail.com \
  --team-id 4RUT26EY4D \
  --password <app-specific-password> \
  --wait

xcrun stapler staple /tmp/scrawl-release/Scrawl.app

# Re-zip after stapling
cd /tmp/scrawl-release
rm /tmp/Scrawl-<version>.zip
ditto -c -k --sequesterRsrc --keepParent Scrawl.app /tmp/Scrawl-<version>.zip

# Verify signature and Gatekeeper acceptance before uploading
codesign --verify --deep --strict --verbose=2 /tmp/scrawl-release/Scrawl.app
spctl -a -t exec -vv /tmp/scrawl-release/Scrawl.app

shasum -a 256 /tmp/Scrawl-<version>.zip
```

2. Create GitHub release at https://github.com/Jetemple/Scrawl/releases/new
   - Tag: `v<version>`
   - Upload `/tmp/Scrawl-<version>.zip`

3. Update homebrew tap:
   - Edit `Casks/scrawl.rb` in `Jetemple/homebrew-tap`
   - Set new `version` and `sha256`
   - Push to main

## Automated release (TODO)

Add a GitHub Action that runs on tag push. Requires these repo secrets:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_APPLICATION` | Base64-encoded `.p12` of the Developer ID Application cert. Export from Keychain Access → right-click cert → Export → `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_ID` | `temple2697@gmail.com` |
| `APPLE_TEAM_ID` | `4RUT26EY4D` |
| `NOTARY_PASSWORD` | App-specific password from https://appleid.apple.com/account/manage |
| `HOMEBREW_TAP_TOKEN` | GitHub personal access token with repo access to `Jetemple/homebrew-tap` |
