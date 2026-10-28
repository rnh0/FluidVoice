# Building and releasing this fork

Builds run on GitHub-hosted macOS runners. Two workflows:

| Workflow | Trigger | What it does |
|---|---|---|
| `build.yml` | push / PR to `main` | SwiftLint, standalone tests (incl. `Tests/run_fork_build_policy_tests.sh`), `xcodebuild test` (Debug). Unsigned. |
| `release.yml` | tag `v*`, or manual | Release archive with the fork's privacy switches, re-signs with a stable identity, zips, attests provenance, publishes a GitHub Release (tags only). |

Both use `-onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution`, so SwiftPM uses exactly
`Fluid.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. All actions are pinned by commit SHA.
Runner and Xcode: `macos-26` (arm64) with Xcode 26.6. The source of truth for labels and installed Xcode versions is
[actions/runner-images](https://github.com/actions/runner-images) (`README.md` and `images/macos/macos-26-arm64-Readme.md`).
Images keep all minor Xcode releases of their major version and replace only patches, so the minor pin is stable.
The exact version used is printed and written to `build-info.txt`.

The upstream community workflows (issue intake, PR policy, stale, PR archive) were removed; they are meant for
the upstream repository and `pr-policy.yml` ran with write permissions on `pull_request_target`.

## Actions permissions

Settings → Actions → General → "Allow rnh0, and select non-rnh0, actions and reusable workflows":

- Tick "Allow actions created by GitHub" (checkout, cache, upload-artifact, attest-build-provenance).
- Allowlist entries must be `owner/repo@ref` patterns; a bare `owner/repo` matches nothing and the run fails
  with `startup_failure`:

  ```
  dorny/paths-filter@*,
  maxim-lobanov/setup-xcode@*
  ```

- Optionally tick "Require actions to be pinned to a full-length commit SHA"; all workflows here are pinned.

## Signing: why a stable identity

macOS ties Microphone and Accessibility grants to the app's *designated requirement*. With an ad-hoc signature
that requirement is the code hash, which changes every build, so you would re-grant Accessibility after every
update. With a fixed certificate it becomes `identifier "com.FluidApp.app" and certificate root = H"…"`,
which stays the same across builds. The sign step prints the designated requirement so you can compare.

Notarization is not set up. Without it, Gatekeeper blocks the first launch: right-click the app, choose Open, or
use System Settings → Privacy & Security → Open Anyway.

### Option A: self-signed certificate (free)

On any machine with OpenSSL 3:

```bash
openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -keyout key.pem -out cert.pem -subj "/CN=FluidVoice Fork Signing" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
```

```bash
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -name "FluidVoice Fork Signing" -out signing.p12
```

(`-legacy` because macOS `security import` does not read OpenSSL 3's default PKCS#12 encryption.)

### Option B: Apple Development or Developer ID certificate

Export the certificate and private key from Keychain Access as `.p12`. Use the certificate's common name,
e.g. `Apple Development: Name (TEAMID)`, as the identity.

### Repository secrets

Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
|---|---|
| `MACOS_SIGNING_P12_BASE64` | `base64 -i signing.p12` |
| `MACOS_SIGNING_P12_PASSWORD` | the export password |
| `MACOS_SIGNING_IDENTITY` | the certificate common name, e.g. `FluidVoice Fork Signing` |

Then delete `key.pem` and `signing.p12` locally, or keep them offline. Anyone with the key can sign
an app that inherits your Microphone and Accessibility grants.

Tagged releases fail without these secrets. Manual runs fall back to ad-hoc signing with a warning.

## Releasing

```bash
git tag v1.6.13-fork.1 && git push origin v1.6.13-fork.1
```

## Verifying a download

```bash
shasum -a 256 -c FluidVoice-*.zip.sha256
```

```bash
gh attestation verify FluidVoice-*.zip --repo rnh0/FluidVoice
```

Attestations need a public repository, or GitHub Enterprise Cloud for a private one. For a private repo on another
plan, the attest step is skipped unless the repository variable `ENABLE_ATTESTATIONS` is `true`.
`build-info.txt` in each release records the commit, workflow run, Xcode version and signing mode.

## Merging upstream

```bash
git fetch upstream && git checkout -b sync/upstream-$(date +%Y%m%d) && git merge upstream/main
```

Files this fork changes, so expect conflicts there: `Info.plist`, `Fluid.xcodeproj/project.pbxproj`
(`SWIFT_ACTIVE_COMPILATION_CONDITIONS`), `.github/workflows/`, `Analytics/AnalyticsService.swift`,
`SimpleUpdater.swift`, `LLMClient.swift`, `LocalAPI/LocalAPIServer.swift`. After merging, re-run the egress
inventory in `PRIVACY.md` (`grep -rnE "URLSession|URLRequest\(|NWConnection|https?://" Sources`) for new
network code.
