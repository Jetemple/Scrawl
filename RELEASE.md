# Release process

Scrawl uses explicit app versions. Merging a normal pull request does **not** publish a release. A release PR must update both `CFBundleShortVersionString` and `CFBundleVersion` in `Config/ScrawlApp-Info.plist`.

## Automated release

The primary release path is `.github/workflows/release.yml`:

1. Create a release branch from the current `master`.
2. Update both plist version fields to the new version.
3. Run the local checks below and open a pull request.
4. Merge the release PR into `master`.
5. The version change starts GitHub Actions, which will:
   - run the test suite;
   - build the arm64 and Intel release binary;
   - sign and notarize the app;
   - publish both `Scrawl-<version>.zip` and `Scrawl-<version>.dmg`;
   - publish a SHA256 file containing both artifact checksums;
   - create the `v<version>` GitHub release with generated notes; and
   - update `Jetemple/homebrew-tap/Casks/scrawl.rb` to point at the ZIP.

Normal code merges do not start the release workflow. A manual dispatch is available for rerunning an intentional release, but it should not be used to republish an old version by accident.

## Release checklist

From a clean checkout:

```bash
VERSION=0.0.16
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Config/ScrawlApp-Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Config/ScrawlApp-Info.plist

swift test
make format-check
make lint
ruby scripts/update-homebrew-cask_test.rb
git diff --check
```

Confirm the two plist values match before opening the PR. The PR should describe the user-facing changes and call out any migration, permission, or model-download implications.

After merging, verify the release run and published assets:

```bash
gh run list --workflow Release --limit 5
gh release view "v$VERSION"
```

Then verify the Homebrew tap points to the same version and ZIP checksum:

```bash
brew update
brew info --cask scrawl
```

## Required repository secrets

| Secret | Value |
|---|---|
| `DEVELOPER_ID_APPLICATION` | Base64-encoded `.p12` for the Developer ID Application certificate |
| `DEVELOPER_ID_PASSWORD` | Password used to export the certificate |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | Apple Developer team ID (`4RUT26EY4D`) |
| `NOTARY_PASSWORD` | App-specific Apple password |
| `HOMEBREW_TAP_TOKEN` | GitHub token with write access to `Jetemple/homebrew-tap` |

The release job validates these secrets before building anything.

## Manual fallback

If GitHub Actions is unavailable, use the tracked install script to build and verify a signed, notarized ZIP locally:

```bash
make build BUILD_ARCHS="arm64 x86_64"
SCRAWL_CODESIGN_IDENTITY="Developer ID Application: Jack Temple (4RUT26EY4D)" \
  SCRAWL_BUILD_ARCHS="arm64 x86_64" SCRAWL_SKIP_BUILD=1 SCRAWL_SKIP_LAUNCH=1 \
  ./scripts/install-app.sh /tmp/scrawl-release

cd /tmp/scrawl-release
ditto -c -k --sequesterRsrc --keepParent Scrawl.app /tmp/Scrawl-<version>.zip
xcrun notarytool submit /tmp/Scrawl-<version>.zip \
  --apple-id <your-apple-id-email> \
  --team-id 4RUT26EY4D \
  --password <app-specific-password> \
  --wait
xcrun stapler staple Scrawl.app
xcrun stapler validate Scrawl.app
rm /tmp/Scrawl-<version>.zip
ditto -c -k --sequesterRsrc --keepParent Scrawl.app /tmp/Scrawl-<version>.zip
codesign --verify --deep --strict --verbose=2 Scrawl.app
spctl -a -t exec -vv Scrawl.app
shasum -a 256 /tmp/Scrawl-<version>.zip
```

Upload the verified ZIP to a manually created `v<version>` release and update the Homebrew cask with its version, URL, and checksum. This fallback does not create the production DMG; prefer the automated workflow for a complete release.
