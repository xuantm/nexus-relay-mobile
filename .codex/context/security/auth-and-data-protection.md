---
scope: security/auth-and-data-protection
status: partial
sources:
  - docs/contracts/device-sync-api.md
  - docs/contracts/iphone-upload-api.md
  - docs/architecture/pixel-companion-sync.md
  - docs/architecture/iphone-photos-uploader.md
  - android/pixel/app/src/main/java/com/nexusrelay/pixel/auth/DeviceTokenStore.kt
  - ios/iphone/NexusRelayIPhone/Core/Auth/CookieSessionStore.swift
  - ios/iphone/NexusRelayIPhone/Core/API/HTTPClient.swift
last_verified_commit: c53b326ddc88d1db76b2d958d18eb7daed2e8b28
---

# Auth And Data Protection

## Authentication Flows
| Flow | Client | Credential | Storage | Notes |
|---|---|---|---|---|
| Pixel pairing | Android | temporary pairing code redeemed once | device token in EncryptedSharedPreferences | User password/Google token not stored on Pixel. |
| Pixel job sync | Android | `X-Device-Token` | encrypted device token | Token is revocable and scoped to device sync APIs per contract docs. |
| iPhone Google sign-in | iOS | backend-mediated browser auth callback code | cookie session in Keychain | Uses `ASWebAuthenticationSession`; exchanges code for cookies. |
| iPhone unsafe API calls | iOS | cookies + CSRF token | cookies in Keychain/shared cookie storage; CSRF cached in memory | `HTTPClient` adds `X-NexusRelay-CSRF`. |

## Data Protection
| Asset | Entry point | Trust boundary | Existing control | Gap |
|---|---|---|---|---|
| Pixel device token | pairing response | backend to device | encrypted local storage | ⚠️ Undocumented — verify backend token revocation and expiration policy |
| Pixel FCM payload | push notification | backend/FCM to device | payload contains signal/job id only | ⚠️ Undocumented — verify backend sender excludes sensitive fields |
| Downloaded media | backend stream | backend to Android MediaStore | app imports via MediaStore pending row | ⚠️ Undocumented — verify retention/autodelete policy with product owner |
| iOS session cookies | session exchange/refresh | backend to device | Keychain storage; refresh once on 401 | ⚠️ Undocumented — verify cookie flags and server session expiry |
| PhotoKit asset ids | local device | device-local to app | not exposed in uploaded filenames; fingerprint suffix used | `AssetFingerprinter.generateUploadedFilename` currently needs review for marker behavior |
| Temporary staged uploads | local device | app-private temp dirs | cleanup after upload/failure and stale cleanup | ⚠️ Undocumented — verify file protection class requirements |

## Secret Handling Rules
| Secret | Rule |
|---|---|
| `google-services.json` | local-only, ignored, do not commit |
| Android keystores / `keystore.properties` | ignored, do not commit |
| Firebase service accounts | ignored, do not commit |
| iOS cookies/session material | do not print, copy into docs, or commit |
| provisioning profiles/certificates/App Store Connect credentials | ⚠️ Undocumented — verify storage; do not commit |

## Authorization / Permissions
| Permission/Role/Scope | Enforced at | Applies to | Source |
|---|---|---|---|
| Pixel sync scope | backend pairing/device-sync service | account uploads or folder scope | `docs/contracts/device-sync-api.md` |
| iPhone account approval | backend Google auth flow | Google sign-in users | `SetupViewModel.swift`, manual verification docs |
| Android permissions | OS manifest | internet/network state/post notifications | `AndroidManifest.xml` |
| iOS Photos access | OS permission | selected/full photo library access | `Info.plist`, PhotoKit files |
| iOS background processing | OS entitlement/config | `com.nexusrelay.iphone.sync` | `Info.plist` |

## Gaps / Verify
> ⚠️ Undocumented — verify: compliance/audit logging, backend authorization middleware, token hashing implementation, cookie flags, PII retention, and sensitive log masking are not verifiable in this repo.
