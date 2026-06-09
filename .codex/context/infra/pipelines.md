---
scope: infra/pipelines
status: verified
sources:
  - .github/workflows/ios-iphone-ci.yml
  - .github/workflows/ios-iphone-release.yml
  - ios/iphone/README.md
  - android/pixel/README.md
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# CI/CD Pipelines

## GitHub Actions
| Workflow | Trigger | Runner | Steps | Artifacts |
|---|---|---|---|---|
| `iOS iPhone CI` | PRs touching `ios/iphone/**` or iOS workflows; pushes to `main`, `develop`, `feature/**`; manual dispatch | `macos-15` | checkout, select Xcode 16.4, install XcodeGen, generate project, show destinations, test, build | test/build `.xcresult` bundles |
| `iOS iPhone Release Artifact` | tags `ios-iphone-v*`; manual dispatch | `macos-15` | checkout, select Xcode 16.4, install XcodeGen, generate project, build simulator app, archive unsigned device build, package | simulator app zip, unsigned `.xcarchive` zip |

## Pipeline Facts
| Fact | Source |
|---|---|
| iOS CI uses `ios/iphone` as working directory. | `.github/workflows/ios-iphone-ci.yml` |
| CI destination is `platform=iOS Simulator,name=iPhone 16,OS=latest`. | `.github/workflows/ios-iphone-ci.yml` |
| Release workflow disables code signing for simulator build and device archive. | `.github/workflows/ios-iphone-release.yml` |
| Android README documents local build/test/install, but no Android workflow exists. | `android/pixel/README.md`, `.github/workflows` scan |

## Gaps / Verify
> ⚠️ Undocumented — verify: Android CI, Android release signing, iOS TestFlight/App Store delivery, backend deployment, infrastructure-as-code, environment promotion, and production rollback docs were not found.

> ⚠️ Undocumented — verify: `ios/iphone/docs/manual-verification.md` references `/.github/workflows/ios-iphone.yml`, but actual workflow files are `ios-iphone-ci.yml` and `ios-iphone-release.yml`.
