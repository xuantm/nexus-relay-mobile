# Pixel Account Scoped Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Pixel companion app use the production NexusRelay server by default, register through the same NexusRelay account model as iOS/web, and sync only media allowed by the selected device scope.

**Architecture:** The backend owns account and scope enforcement. Pixel receives a revocable device token through authenticated registration or a short-lived pairing flow, then uses only `X-Device-Token` for background sync. Device sync jobs are created only for targets whose `SyncScope` matches the completed media item.

**Tech Stack:** .NET 10 Minimal APIs, MediatR, EF Core/PostgreSQL, xUnit/NSubstitute, Android Kotlin, Jetpack Compose, Retrofit, WorkManager, DataStore, EncryptedSharedPreferences.

---

## Scope Decision

Use folder/account scoped device targets. This is the smallest change that prevents "sync all Nexus data" and still fits current backend entities:

- `AccountUploads`: sync media uploaded by the registered account, regardless of folder.
- `Folder`: sync media uploaded by the registered account only when `MediaItem.FolderId == ScopedFolderId`.

Do not add cross-account shared library sync in this phase. That requires an explicit sharing/permission model and should be a separate project.

Do not make Pixel store the user's password. Use one of these registration paths:

- Preferred for first implementation: Pixel login with username/password, backend returns mobile bearer tokens, Pixel immediately calls register, then stores only the device token.
- Better UX follow-up: Web/iOS creates a pairing code or QR; Pixel redeems code and stores only the device token.

This plan implements the preferred first path and keeps pairing-code work as a clean follow-up task.

## File Structure

### Backend Repo: `G:/workspace/nexus-relay`

- Modify `backend/src/NexusRelay.Backend.Domain/Enums/DeviceSyncScope.cs`
  - New enum for account/folder scope.
- Modify `backend/src/NexusRelay.Backend.Domain/Entities/DeviceSyncTarget.cs`
  - Store `SyncScope` and nullable `ScopedFolderId`.
- Modify `backend/src/NexusRelay.Backend.Application/DTOs/DeviceSyncDtos.cs`
  - Extend register request/response with scope information.
- Modify `backend/src/NexusRelay.Backend.Application/Features/DeviceSync/Commands/RegisterDevice.cs`
  - Pass scope values into service.
- Modify `backend/src/NexusRelay.Backend.Application/Validators/RegisterDeviceValidator.cs`
  - Validate folder scope has a folder id.
- Modify `backend/src/NexusRelay.Backend.Infrastructure/Persistence/Configurations/DeviceSyncTargetConfiguration.cs`
  - Map new columns and index scoped folder.
- Modify `backend/src/NexusRelay.Backend.Infrastructure/Services/DeviceSyncService.cs`
  - Register target with scope and create jobs only when media matches target scope.
- Modify `backend/src/NexusRelay.Backend.Infrastructure/Persistence/Repositories/DeviceSyncRepository.cs`
  - Keep current target retrieval but include scope fields in query results automatically.
- Add EF Core migration under `backend/src/NexusRelay.Backend.Infrastructure/Migrations/`.
- Add `backend/tests/NexusRelay.Backend.Application.Tests/Infrastructure/DeviceSyncServiceScopeTests.cs`
  - Unit tests for scoped job creation.

### Mobile Repo: `G:/workspace/nexus-relay-mobile`

- Modify `android/pixel/app/build.gradle.kts`
  - Add build config default backend URLs.
- Modify `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/DeviceSyncDtos.kt`
  - Add register scope fields.
- Modify `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/NexusRelayApi.kt`
  - Add authenticated login/register support.
- Modify `android/pixel/app/src/main/java/com/nexusrelay/pixel/api/ApiClientFactory.kt`
  - Support auth header interceptor for registration only.
- Modify `android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/AppSettingsStore.kt`
  - Store sync scope labels and selected folder id/name.
- Modify `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt`
  - Remove visible backend URL from release setup, add login and sync scope controls.
- Modify `android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt`
  - Show account/scope summary and keep server address secondary.
- Modify `docs/contracts/device-sync-api.md`
  - Document new fields and production default behavior.
- Modify `docs/architecture/pixel-companion-sync.md`
  - Document account-scoped sync.
- Add/update tests:
  - `android/pixel/app/src/test/java/com/nexusrelay/pixel/api/DeviceSyncDtoTest.kt`
  - `android/pixel/app/src/test/java/com/nexusrelay/pixel/sync/DeviceSyncRepositoryTest.kt`

---

## Milestone 1: Backend Scope Model

### Task 1: Add Device Sync Scope Enum

**Files:**
- Create: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Domain/Enums/DeviceSyncScope.cs`

- [ ] **Step 1: Create enum**

```csharp
namespace NexusRelay.Backend.Domain.Enums;

public enum DeviceSyncScope
{
    AccountUploads,
    Folder
}
```

- [ ] **Step 2: Build backend**

Run from `G:/workspace/nexus-relay`:

```powershell
dotnet build backend/NexusRelay.Backend.slnx
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```powershell
git add backend/src/NexusRelay.Backend.Domain/Enums/DeviceSyncScope.cs
git commit -m "feat: add device sync scope enum"
```

### Task 2: Store Scope On DeviceSyncTarget

**Files:**
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Domain/Entities/DeviceSyncTarget.cs`
- Test: `G:/workspace/nexus-relay/backend/tests/NexusRelay.Backend.Application.Tests/Infrastructure/DeviceSyncServiceScopeTests.cs`

- [ ] **Step 1: Write failing domain/service-level test shell**

Create the test file with a first test that will compile after later service wiring:

```csharp
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NexusRelay.Backend.Application.Configuration;
using NexusRelay.Backend.Application.DTOs;
using NexusRelay.Backend.Application.Interfaces;
using NexusRelay.Backend.Domain.Entities;
using NexusRelay.Backend.Domain.Enums;
using NexusRelay.Backend.Infrastructure.Services;
using NSubstitute;
using Xunit;

namespace NexusRelay.Backend.Application.Tests.Infrastructure;

public sealed class DeviceSyncServiceScopeTests
{
    [Fact]
    public async Task RegisterDeviceAsync_WhenFolderScopeProvided_PersistsTargetScope()
    {
        var repository = Substitute.For<IDeviceSyncRepository>();
        var tokenService = Substitute.For<IDeviceTokenService>();
        var notifier = Substitute.For<IDeviceNotifier>();
        var mediaRepository = Substitute.For<IMediaItemRepository>();
        var googleDrive = Substitute.For<IGoogleDriveService>();
        tokenService.GenerateToken().Returns("raw-token");
        tokenService.HashToken("raw-token").Returns("hashed-token");
        var service = new DeviceSyncService(
            repository,
            tokenService,
            notifier,
            mediaRepository,
            googleDrive,
            Options.Create(new DeviceSyncOptions { Enabled = true }),
            NullLogger<DeviceSyncService>.Instance);

        var userId = Guid.CreateVersion7();
        var folderId = Guid.CreateVersion7();

        await service.RegisterDeviceAsync(
            userId,
            new RegisterDeviceRequest("Pixel", null, true, DeviceSyncScope.Folder, folderId),
            CancellationToken.None);

        await repository.Received(1).AddTargetAsync(
            Arg.Is<DeviceSyncTarget>(target =>
                target.UserId == userId &&
                target.SyncScope == DeviceSyncScope.Folder &&
                target.ScopedFolderId == folderId),
            Arg.Any<CancellationToken>());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from `G:/workspace/nexus-relay`:

```powershell
dotnet test backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj --filter DeviceSyncServiceScopeTests
```

Expected: compile fails because `DeviceSyncTarget.SyncScope`, `ScopedFolderId`, and the new `RegisterDeviceRequest` constructor do not exist yet.

- [ ] **Step 3: Update `DeviceSyncTarget`**

Add properties:

```csharp
public DeviceSyncScope SyncScope { get; private set; }
public Guid? ScopedFolderId { get; private set; }
```

Change `Create` signature:

```csharp
public static DeviceSyncTarget Create(
    Guid userId,
    string name,
    DeviceSyncPlatform platform,
    string deviceTokenHash,
    string? fcmToken,
    bool wifiOnly,
    DeviceSyncScope syncScope = DeviceSyncScope.AccountUploads,
    Guid? scopedFolderId = null)
{
    if (syncScope == DeviceSyncScope.Folder && scopedFolderId is null)
        throw new ArgumentException("Folder scoped device sync requires a scoped folder id.", nameof(scopedFolderId));

    if (syncScope == DeviceSyncScope.AccountUploads && scopedFolderId is not null)
        throw new ArgumentException("Account upload scope must not include a scoped folder id.", nameof(scopedFolderId));

    var now = DateTimeOffset.UtcNow;
    return new DeviceSyncTarget
    {
        Id = Guid.CreateVersion7(),
        UserId = userId,
        Name = name,
        Platform = platform,
        DeviceTokenHash = deviceTokenHash,
        FcmToken = fcmToken,
        Enabled = true,
        WifiOnly = wifiOnly,
        SyncScope = syncScope,
        ScopedFolderId = scopedFolderId,
        CreatedAt = now,
        UpdatedAt = now
    };
}
```

Add update method for FCM/settings:

```csharp
public void UpdateSyncSettings(string name, string? fcmToken, bool wifiOnly, DeviceSyncScope syncScope, Guid? scopedFolderId)
{
    if (syncScope == DeviceSyncScope.Folder && scopedFolderId is null)
        throw new ArgumentException("Folder scoped device sync requires a scoped folder id.", nameof(scopedFolderId));

    if (syncScope == DeviceSyncScope.AccountUploads && scopedFolderId is not null)
        throw new ArgumentException("Account upload scope must not include a scoped folder id.", nameof(scopedFolderId));

    Name = name;
    FcmToken = fcmToken;
    WifiOnly = wifiOnly;
    SyncScope = syncScope;
    ScopedFolderId = scopedFolderId;
    UpdatedAt = DateTimeOffset.UtcNow;
}
```

- [ ] **Step 4: Update DTO**

In `DeviceSyncDtos.cs`, change:

```csharp
public record RegisterDeviceRequest(string DeviceName, string? FcmToken, bool WifiOnly);
public record RegisterDeviceResponse(Guid TargetId, string DeviceToken);
```

to:

```csharp
using NexusRelay.Backend.Domain.Enums;

public record RegisterDeviceRequest(
    string DeviceName,
    string? FcmToken,
    bool WifiOnly,
    DeviceSyncScope SyncScope = DeviceSyncScope.AccountUploads,
    Guid? ScopedFolderId = null);

public record RegisterDeviceResponse(
    Guid TargetId,
    string DeviceToken,
    DeviceSyncScope SyncScope,
    Guid? ScopedFolderId);
```

- [ ] **Step 5: Update register command**

In `RegisterDevice.cs`, change command:

```csharp
public record RegisterDeviceCommand(
    string DeviceName,
    string? FcmToken,
    bool WifiOnly,
    DeviceSyncScope SyncScope,
    Guid? ScopedFolderId) : IRequest<RegisterDeviceResponse>;
```

Change request creation:

```csharp
var registerRequest = new RegisterDeviceRequest(
    request.DeviceName,
    request.FcmToken,
    request.WifiOnly,
    request.SyncScope,
    request.ScopedFolderId);
```

- [ ] **Step 6: Update endpoint mapping**

In `DeviceSyncEndpoints.cs`, change command creation:

```csharp
var command = new RegisterDeviceCommand(
    request.DeviceName,
    request.FcmToken,
    request.WifiOnly,
    request.SyncScope,
    request.ScopedFolderId);
```

- [ ] **Step 7: Update service registration**

In `DeviceSyncService.RegisterDeviceAsync`, change target creation:

```csharp
var target = DeviceSyncTarget.Create(
    userId,
    request.DeviceName,
    platform,
    hashedToken,
    request.FcmToken,
    request.WifiOnly,
    request.SyncScope,
    request.ScopedFolderId);
```

Change response:

```csharp
return new RegisterDeviceResponse(target.Id, rawToken, target.SyncScope, target.ScopedFolderId);
```

- [ ] **Step 8: Run focused test**

```powershell
dotnet test backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj --filter DeviceSyncServiceScopeTests
```

Expected: test passes after all compile errors are fixed.

- [ ] **Step 9: Commit**

```powershell
git add backend/src/NexusRelay.Backend.Domain/Entities/DeviceSyncTarget.cs backend/src/NexusRelay.Backend.Application/DTOs/DeviceSyncDtos.cs backend/src/NexusRelay.Backend.Application/Features/DeviceSync/Commands/RegisterDevice.cs backend/src/NexusRelay.Backend.Api/Endpoints/DeviceSyncEndpoints.cs backend/src/NexusRelay.Backend.Infrastructure/Services/DeviceSyncService.cs backend/tests/NexusRelay.Backend.Application.Tests/Infrastructure/DeviceSyncServiceScopeTests.cs
git commit -m "feat: store device sync target scope"
```

### Task 3: Map Scope Columns And Add Migration

**Files:**
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Infrastructure/Persistence/Configurations/DeviceSyncTargetConfiguration.cs`
- Create: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Infrastructure/Migrations/<timestamp>_AddDeviceSyncTargetScope.cs`

- [ ] **Step 1: Update EF configuration**

Add to `DeviceSyncTargetConfiguration.Configure`:

```csharp
builder.Property(t => t.SyncScope)
    .IsRequired()
    .HasConversion<string>()
    .HasMaxLength(40)
    .HasDefaultValue(DeviceSyncScope.AccountUploads);

builder.Property(t => t.ScopedFolderId);
```

Add relationship/index:

```csharp
builder.HasIndex(t => t.ScopedFolderId);
```

Add import:

```csharp
using NexusRelay.Backend.Domain.Enums;
```

- [ ] **Step 2: Generate migration**

Run from `G:/workspace/nexus-relay/backend`:

```powershell
dotnet ef migrations add AddDeviceSyncTargetScope --project src/NexusRelay.Backend.Infrastructure --startup-project src/NexusRelay.Backend.Api
```

Expected: migration creates `SyncScope` text column with default `AccountUploads` and nullable `ScopedFolderId` column.

- [ ] **Step 3: Build backend**

```powershell
dotnet build G:/workspace/nexus-relay/backend/NexusRelay.Backend.slnx
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```powershell
git add backend/src/NexusRelay.Backend.Infrastructure/Persistence/Configurations/DeviceSyncTargetConfiguration.cs backend/src/NexusRelay.Backend.Infrastructure/Migrations
git commit -m "feat: persist device sync target scope"
```

---

## Milestone 2: Backend Scope Enforcement

### Task 4: Filter Job Creation By Target Scope

**Files:**
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Infrastructure/Services/DeviceSyncService.cs`
- Test: `G:/workspace/nexus-relay/backend/tests/NexusRelay.Backend.Application.Tests/Infrastructure/DeviceSyncServiceScopeTests.cs`

- [ ] **Step 1: Add failing test for folder mismatch**

Append:

```csharp
[Fact]
public async Task CreateJobsForCompletedMediaAsync_WhenFolderScopeDoesNotMatch_DoesNotCreateJob()
{
    var mediaId = Guid.CreateVersion7();
    var userId = Guid.CreateVersion7();
    var mediaFolderId = Guid.CreateVersion7();
    var otherFolderId = Guid.CreateVersion7();
    var target = DeviceSyncTarget.Create(
        userId,
        "Pixel",
        DeviceSyncPlatform.Android,
        "hashed-token",
        null,
        true,
        DeviceSyncScope.Folder,
        otherFolderId);
    var media = MediaItem.Create(mediaFolderId, "photo.jpg", 100, 1, "image/jpeg", MediaType.Image, userId);
    media.MarkRelaying("sha256");
    media.MarkCompleted("drive-file-id");

    var repository = Substitute.For<IDeviceSyncRepository>();
    var tokenService = Substitute.For<IDeviceTokenService>();
    var notifier = Substitute.For<IDeviceNotifier>();
    var mediaRepository = Substitute.For<IMediaItemRepository>();
    var googleDrive = Substitute.For<IGoogleDriveService>();
    mediaRepository.GetByIdAsync(mediaId, Arg.Any<CancellationToken>()).Returns(media);
    repository.GetEnabledTargetsForUserAsync(userId, Arg.Any<CancellationToken>()).Returns([target]);

    var service = new DeviceSyncService(
        repository,
        tokenService,
        notifier,
        mediaRepository,
        googleDrive,
        Options.Create(new DeviceSyncOptions { Enabled = true }),
        NullLogger<DeviceSyncService>.Instance);

    await service.CreateJobsForCompletedMediaAsync(mediaId, CancellationToken.None);

    await repository.DidNotReceiveWithAnyArgs().AddJobAsync(default!, default);
    await notifier.DidNotReceiveWithAnyArgs().SendJobNotificationAsync(default!, default);
}
```

- [ ] **Step 2: Add failing test for folder match**

Append:

```csharp
[Fact]
public async Task CreateJobsForCompletedMediaAsync_WhenFolderScopeMatches_CreatesJob()
{
    var mediaId = Guid.CreateVersion7();
    var userId = Guid.CreateVersion7();
    var folderId = Guid.CreateVersion7();
    var target = DeviceSyncTarget.Create(
        userId,
        "Pixel",
        DeviceSyncPlatform.Android,
        "hashed-token",
        null,
        true,
        DeviceSyncScope.Folder,
        folderId);
    var media = MediaItem.Create(folderId, "photo.jpg", 100, 1, "image/jpeg", MediaType.Image, userId);
    media.MarkRelaying("sha256");
    media.MarkCompleted("drive-file-id");

    var repository = Substitute.For<IDeviceSyncRepository>();
    var tokenService = Substitute.For<IDeviceTokenService>();
    var notifier = Substitute.For<IDeviceNotifier>();
    var mediaRepository = Substitute.For<IMediaItemRepository>();
    var googleDrive = Substitute.For<IGoogleDriveService>();
    mediaRepository.GetByIdAsync(mediaId, Arg.Any<CancellationToken>()).Returns(media);
    repository.GetEnabledTargetsForUserAsync(userId, Arg.Any<CancellationToken>()).Returns([target]);
    repository.GetJobByMediaAndTargetAsync(media.Id, target.Id, Arg.Any<CancellationToken>()).Returns((DeviceSyncJob?)null);
    notifier.SendJobNotificationAsync(Arg.Any<DeviceSyncJob>(), Arg.Any<CancellationToken>()).Returns(false);

    var service = new DeviceSyncService(
        repository,
        tokenService,
        notifier,
        mediaRepository,
        googleDrive,
        Options.Create(new DeviceSyncOptions { Enabled = true }),
        NullLogger<DeviceSyncService>.Instance);

    await service.CreateJobsForCompletedMediaAsync(mediaId, CancellationToken.None);

    await repository.Received(1).AddJobAsync(
        Arg.Is<DeviceSyncJob>(job => job.MediaId == media.Id && job.TargetId == target.Id),
        Arg.Any<CancellationToken>());
}
```

- [ ] **Step 3: Run tests and verify they fail**

```powershell
dotnet test G:/workspace/nexus-relay/backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj --filter DeviceSyncServiceScopeTests
```

Expected: mismatch test fails because current service creates a job for every enabled target.

- [ ] **Step 4: Add helper in `DeviceSyncService`**

Add private method:

```csharp
private static bool TargetAcceptsMedia(DeviceSyncTarget target, MediaItem mediaItem)
{
    if (target.UserId != mediaItem.UploadedByUserId)
        return false;

    return target.SyncScope switch
    {
        DeviceSyncScope.AccountUploads => true,
        DeviceSyncScope.Folder => target.ScopedFolderId.HasValue && mediaItem.FolderId == target.ScopedFolderId,
        _ => false
    };
}
```

- [ ] **Step 5: Use helper during job creation**

Inside `foreach (var target in targets)`, before `GetJobByMediaAndTargetAsync`, add:

```csharp
if (!TargetAcceptsMedia(target, mediaItem))
{
    _logger.LogDebug(
        "Target {TargetId} scope {SyncScope} does not accept media {MediaId}. Skipping.",
        target.Id,
        target.SyncScope,
        mediaItem.Id);
    continue;
}
```

- [ ] **Step 6: Run focused tests**

```powershell
dotnet test G:/workspace/nexus-relay/backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj --filter DeviceSyncServiceScopeTests
```

Expected: all `DeviceSyncServiceScopeTests` pass.

- [ ] **Step 7: Commit**

```powershell
git add backend/src/NexusRelay.Backend.Infrastructure/Services/DeviceSyncService.cs backend/tests/NexusRelay.Backend.Application.Tests/Infrastructure/DeviceSyncServiceScopeTests.cs
git commit -m "feat: enforce device sync target scope"
```

### Task 5: Validate Folder Scope Input

**Files:**
- Modify: `G:/workspace/nexus-relay/backend/src/NexusRelay.Backend.Application/Validators/RegisterDeviceValidator.cs`

- [ ] **Step 1: Update validator**

```csharp
using NexusRelay.Backend.Domain.Enums;
```

Add rules:

```csharp
RuleFor(x => x.ScopedFolderId)
    .NotNull()
    .When(x => x.SyncScope == DeviceSyncScope.Folder)
    .WithMessage("Scoped folder id is required when sync scope is Folder.");

RuleFor(x => x.ScopedFolderId)
    .Null()
    .When(x => x.SyncScope == DeviceSyncScope.AccountUploads)
    .WithMessage("Scoped folder id must be empty when sync scope is AccountUploads.");
```

- [ ] **Step 2: Add validator tests**

Create `G:/workspace/nexus-relay/backend/tests/NexusRelay.Backend.Application.Tests/Features/DeviceSync/RegisterDeviceValidatorTests.cs`:

```csharp
using NexusRelay.Backend.Application.Features.DeviceSync.Commands;
using NexusRelay.Backend.Application.Validators;
using NexusRelay.Backend.Domain.Enums;
using Xunit;

namespace NexusRelay.Backend.Application.Tests.Features.DeviceSync;

public sealed class RegisterDeviceValidatorTests
{
    [Fact]
    public void Validate_WhenFolderScopeMissingFolderId_ReturnsError()
    {
        var validator = new RegisterDeviceValidator();

        var result = validator.Validate(new RegisterDeviceCommand("Pixel", null, true, DeviceSyncScope.Folder, null));

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, error => error.PropertyName == "ScopedFolderId");
    }

    [Fact]
    public void Validate_WhenAccountScopeContainsFolderId_ReturnsError()
    {
        var validator = new RegisterDeviceValidator();

        var result = validator.Validate(new RegisterDeviceCommand("Pixel", null, true, DeviceSyncScope.AccountUploads, Guid.CreateVersion7()));

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, error => error.PropertyName == "ScopedFolderId");
    }

    [Fact]
    public void Validate_WhenFolderScopeHasFolderId_Passes()
    {
        var validator = new RegisterDeviceValidator();

        var result = validator.Validate(new RegisterDeviceCommand("Pixel", null, true, DeviceSyncScope.Folder, Guid.CreateVersion7()));

        Assert.True(result.IsValid);
    }
}
```

- [ ] **Step 3: Run validator tests**

```powershell
dotnet test G:/workspace/nexus-relay/backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj --filter RegisterDeviceValidatorTests
```

Expected: tests pass.

- [ ] **Step 4: Commit**

```powershell
git add backend/src/NexusRelay.Backend.Application/Validators/RegisterDeviceValidator.cs backend/tests/NexusRelay.Backend.Application.Tests/Features/DeviceSync/RegisterDeviceValidatorTests.cs
git commit -m "test: validate device sync registration scope"
```

---

## Milestone 3: Pixel Production URL And Registration UX

### Task 6: Add Build-Time Backend URL Defaults

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/build.gradle.kts`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt`

- [ ] **Step 1: Add BuildConfig fields**

In `android { defaultConfig { ... } }` add:

```kotlin
buildConfigField("String", "DEFAULT_BACKEND_BASE_URL", "\"https://relay.xuantruong.org\"")
```

In `buildTypes { release { ... } }` add:

```kotlin
buildConfigField("Boolean", "SHOW_BACKEND_URL_FIELD", "false")
```

Add a debug build type section:

```kotlin
debug {
    buildConfigField("Boolean", "SHOW_BACKEND_URL_FIELD", "true")
}
```

- [ ] **Step 2: Use default URL in setup**

In `SetupScreen.kt`, change:

```kotlin
var backendUrl by remember { mutableStateOf("https://") }
```

to:

```kotlin
var backendUrl by remember { mutableStateOf(BuildConfig.DEFAULT_BACKEND_BASE_URL) }
```

Wrap backend text field:

```kotlin
if (BuildConfig.SHOW_BACKEND_URL_FIELD) {
    OutlinedTextField(
        value = backendUrl,
        onValueChange = { backendUrl = it },
        label = { Text("Backend URL", color = Color.LightGray) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth()
    )
}
```

- [ ] **Step 3: Build Android app**

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat assembleDebug
```

Expected: debug build succeeds and debug setup still shows URL field.

- [ ] **Step 4: Commit**

```powershell
git add android/pixel/app/build.gradle.kts android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt
git commit -m "feat: default pixel app to production backend"
```

### Task 7: Add Pixel Register Scope DTOs

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/api/DeviceSyncDtos.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/test/java/com/nexusrelay/pixel/api/DeviceSyncDtoTest.kt`

- [ ] **Step 1: Update Kotlin DTOs**

```kotlin
enum class DeviceSyncScope {
    AccountUploads,
    Folder
}

@JsonClass(generateAdapter = true)
data class RegisterDeviceRequest(
    val deviceName: String,
    val fcmToken: String?,
    val wifiOnly: Boolean,
    val syncScope: DeviceSyncScope = DeviceSyncScope.AccountUploads,
    val scopedFolderId: String? = null
)

@JsonClass(generateAdapter = true)
data class RegisterDeviceResponse(
    val targetId: String,
    val deviceToken: String,
    val syncScope: DeviceSyncScope = DeviceSyncScope.AccountUploads,
    val scopedFolderId: String? = null
)
```

- [ ] **Step 2: Add DTO test**

Add to `DeviceSyncDtoTest.kt`:

```kotlin
@Test
fun testRegisterDeviceRequestSerializesFolderScope() {
    val moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()
    val adapter = moshi.adapter(RegisterDeviceRequest::class.java)

    val json = adapter.toJson(
        RegisterDeviceRequest(
            deviceName = "Pixel",
            fcmToken = null,
            wifiOnly = true,
            syncScope = DeviceSyncScope.Folder,
            scopedFolderId = "folder-123"
        )
    )

    assertTrue(json.contains("\"syncScope\":\"Folder\""))
    assertTrue(json.contains("\"scopedFolderId\":\"folder-123\""))
}
```

- [ ] **Step 3: Run Android unit tests**

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest
```

Expected: tests pass.

- [ ] **Step 4: Commit**

```powershell
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/api/DeviceSyncDtos.kt android/pixel/app/src/test/java/com/nexusrelay/pixel/api/DeviceSyncDtoTest.kt
git commit -m "feat: add pixel device sync scope dtos"
```

### Task 8: Add Mobile Auth For Registration

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/api/DeviceSyncDtos.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/api/NexusRelayApi.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/api/ApiClientFactory.kt`

- [ ] **Step 1: Add auth DTOs**

In `DeviceSyncDtos.kt`:

```kotlin
@JsonClass(generateAdapter = true)
data class LoginRequest(
    val username: String,
    val password: String
)

@JsonClass(generateAdapter = true)
data class LoginResponse(
    val token: String,
    val refreshToken: String? = null,
    val username: String? = null
)
```

- [ ] **Step 2: Add auth endpoint and auth register header**

In `NexusRelayApi.kt`:

```kotlin
@POST("api/auth/login")
suspend fun login(
    @Body request: LoginRequest
): LoginResponse
```

Change register method:

```kotlin
@POST("api/device-sync/register")
suspend fun registerDevice(
    @Header("Authorization") authorization: String,
    @Body request: RegisterDeviceRequest
): RegisterDeviceResponse
```

- [ ] **Step 3: Keep unauthenticated client for sync**

No auth header should be added globally to the Retrofit client. Pixel background sync continues to pass `X-Device-Token` per method.

- [ ] **Step 4: Compile**

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat compileDebugKotlin
```

Expected: compile fails until `SetupScreen.kt` is updated in the next task. Do not commit this task separately if compile fails; include it with Task 9.

### Task 9: Update Pixel Setup Screen For Account Registration

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/AppSettingsStore.kt`

- [ ] **Step 1: Add setup state**

In `SetupScreen.kt`:

```kotlin
var username by remember { mutableStateOf("") }
var password by remember { mutableStateOf("") }
var syncScope by remember { mutableStateOf(DeviceSyncScope.AccountUploads) }
var scopedFolderId by remember { mutableStateOf("") }
```

- [ ] **Step 2: Add login fields**

Place above device name:

```kotlin
OutlinedTextField(
    value = username,
    onValueChange = { username = it },
    label = { Text("NexusRelay Username", color = Color.LightGray) },
    singleLine = true,
    modifier = Modifier.fillMaxWidth()
)

OutlinedTextField(
    value = password,
    onValueChange = { password = it },
    label = { Text("NexusRelay Password", color = Color.LightGray) },
    singleLine = true,
    modifier = Modifier.fillMaxWidth(),
    visualTransformation = PasswordVisualTransformation()
)
```

Add import:

```kotlin
import androidx.compose.ui.text.input.PasswordVisualTransformation
```

- [ ] **Step 3: Add scope controls**

Use a simple two-option selector:

```kotlin
SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
    SegmentedButton(
        selected = syncScope == DeviceSyncScope.AccountUploads,
        onClick = { syncScope = DeviceSyncScope.AccountUploads },
        shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
    ) {
        Text("Account")
    }
    SegmentedButton(
        selected = syncScope == DeviceSyncScope.Folder,
        onClick = { syncScope = DeviceSyncScope.Folder },
        shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
    ) {
        Text("Folder")
    }
}

if (syncScope == DeviceSyncScope.Folder) {
    OutlinedTextField(
        value = scopedFolderId,
        onValueChange = { scopedFolderId = it },
        label = { Text("Folder ID", color = Color.LightGray) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth()
    )
}
```

- [ ] **Step 4: Validate setup input**

Replace validation:

```kotlin
if (backendUrl.isBlank() || deviceName.isBlank()) {
    errorMessage = "All fields are required"
    return@Button
}
```

with:

```kotlin
if (backendUrl.isBlank() || deviceName.isBlank() || username.isBlank() || password.isBlank()) {
    errorMessage = "Server, account, and device name are required"
    return@Button
}

if (syncScope == DeviceSyncScope.Folder && scopedFolderId.isBlank()) {
    errorMessage = "Folder ID is required for folder sync"
    return@Button
}
```

- [ ] **Step 5: Login then register**

Change registration call:

```kotlin
val api = ApiClientFactory.create(backendUrl, BuildConfig.DEBUG)
val loginResponse = api.login(LoginRequest(username = username, password = password))
val response = api.registerDevice(
    authorization = "Bearer ${loginResponse.token}",
    request = RegisterDeviceRequest(
        deviceName = deviceName,
        fcmToken = currentFcmToken,
        wifiOnly = wifiOnly,
        syncScope = syncScope,
        scopedFolderId = scopedFolderId.takeIf { syncScope == DeviceSyncScope.Folder && it.isNotBlank() }
    )
)
```

Do not persist `password`. Do not persist `loginResponse.token` unless a later task requires refreshable mobile sessions.

- [ ] **Step 6: Persist scope settings**

In `AppSettingsStore.kt`, add:

```kotlin
val syncScopeFlow: Flow<String?> = context.dataStore.data.map { preferences ->
    preferences[KEY_SYNC_SCOPE]
}

suspend fun saveSyncScope(scope: String) {
    context.dataStore.edit { preferences ->
        preferences[KEY_SYNC_SCOPE] = scope
    }
}

val scopedFolderIdFlow: Flow<String?> = context.dataStore.data.map { preferences ->
    preferences[KEY_SCOPED_FOLDER_ID]
}

suspend fun saveScopedFolderId(folderId: String?) {
    context.dataStore.edit { preferences ->
        if (folderId.isNullOrBlank()) {
            preferences.remove(KEY_SCOPED_FOLDER_ID)
        } else {
            preferences[KEY_SCOPED_FOLDER_ID] = folderId
        }
    }
}
```

Add keys:

```kotlin
private val KEY_SYNC_SCOPE = stringPreferencesKey("sync_scope")
private val KEY_SCOPED_FOLDER_ID = stringPreferencesKey("scoped_folder_id")
```

After saving target id:

```kotlin
appSettingsStore.saveSyncScope(response.syncScope.name)
appSettingsStore.saveScopedFolderId(response.scopedFolderId)
```

- [ ] **Step 7: Compile and test**

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest assembleDebug
```

Expected: unit tests and debug build pass.

- [ ] **Step 8: Commit**

```powershell
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/api/DeviceSyncDtos.kt android/pixel/app/src/main/java/com/nexusrelay/pixel/api/NexusRelayApi.kt android/pixel/app/src/main/java/com/nexusrelay/pixel/api/ApiClientFactory.kt android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/SetupScreen.kt android/pixel/app/src/main/java/com/nexusrelay/pixel/storage/AppSettingsStore.kt
git commit -m "feat: register pixel device with account scope"
```

---

## Milestone 4: Status, Docs, And Verification

### Task 10: Show Scope On Pixel Status Screen

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt`

- [ ] **Step 1: Read scope settings**

Add:

```kotlin
val syncScope by appSettingsStore.syncScopeFlow.collectAsState(initial = "")
val scopedFolderId by appSettingsStore.scopedFolderIdFlow.collectAsState(initial = "")
```

- [ ] **Step 2: Add status row**

In the settings card:

```kotlin
Row(
    modifier = Modifier.fillMaxWidth(),
    horizontalArrangement = Arrangement.SpaceBetween
) {
    Text("Sync Scope", color = Color.LightGray, fontSize = 14.sp)
    val scopeText = when (syncScope) {
        "Folder" -> "Folder ${scopedFolderId?.take(8) ?: ""}"
        "AccountUploads" -> "Account uploads"
        else -> "Account uploads"
    }
    Text(scopeText, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
}
```

- [ ] **Step 3: Build Android app**

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat assembleDebug
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```powershell
git add android/pixel/app/src/main/java/com/nexusrelay/pixel/ui/StatusScreen.kt
git commit -m "feat: show pixel sync scope"
```

### Task 11: Update API Contract And Architecture Docs

**Files:**
- Modify: `G:/workspace/nexus-relay-mobile/docs/contracts/device-sync-api.md`
- Modify: `G:/workspace/nexus-relay-mobile/docs/architecture/pixel-companion-sync.md`
- Modify: `G:/workspace/nexus-relay-mobile/android/pixel/README.md`

- [ ] **Step 1: Update registration contract**

In `device-sync-api.md`, request becomes:

```json
{
  "deviceName": "Pixel XL",
  "fcmToken": "fcm-token-from-firebase",
  "wifiOnly": true,
  "syncScope": "Folder",
  "scopedFolderId": "2f1cbb66-4a8d-4d62-b14d-67d821742958"
}
```

Response becomes:

```json
{
  "targetId": "4d6b0f2e-47b6-49fd-8daa-c87e70307f9f",
  "deviceToken": "raw-device-token-returned-once",
  "syncScope": "Folder",
  "scopedFolderId": "2f1cbb66-4a8d-4d62-b14d-67d821742958"
}
```

Add:

```text
Allowed syncScope values:
- AccountUploads: sync completed media uploaded by the registering account.
- Folder: sync completed media uploaded by the registering account only when the media belongs to scopedFolderId.
```

- [ ] **Step 2: Update architecture doc**

Add this backend rule:

```text
The backend is the source of truth for sync scope. Pixel never receives all jobs and filters locally. DeviceSyncService creates jobs only for targets whose account and scope match the completed media item.
```

- [ ] **Step 3: Update Pixel README**

Add:

```text
Release builds default to https://relay.xuantruong.org. Debug builds keep the backend URL field visible for local testing.
```

- [ ] **Step 4: Commit**

```powershell
git add docs/contracts/device-sync-api.md docs/architecture/pixel-companion-sync.md android/pixel/README.md
git commit -m "docs: document account scoped pixel sync"
```

### Task 12: Full Verification

**Files:**
- No source edits expected.

- [ ] **Step 1: Run backend tests**

```powershell
Set-Location G:/workspace/nexus-relay
dotnet test backend/tests/NexusRelay.Backend.Application.Tests/NexusRelay.Backend.Application.Tests.csproj
```

Expected: all backend tests pass.

- [ ] **Step 2: Build backend**

```powershell
dotnet build backend/NexusRelay.Backend.slnx
```

Expected: build succeeds.

- [ ] **Step 3: Run Android tests**

```powershell
Set-Location G:/workspace/nexus-relay-mobile/android/pixel
./gradlew.bat testDebugUnitTest
```

Expected: unit tests pass.

- [ ] **Step 4: Build Android debug APK**

```powershell
./gradlew.bat assembleDebug
```

Expected: APK builds successfully.

- [ ] **Step 5: Manual smoke test with account scope**

1. Start backend with migrations applied.
2. Install Pixel debug APK.
3. Register Pixel using the NexusRelay account.
4. Select `AccountUploads`.
5. Upload media from that account.
6. Confirm backend creates a job for the Pixel target.
7. Confirm Pixel imports media.
8. Upload media from another account.
9. Confirm no Pixel job is created for the first account's target.

- [ ] **Step 6: Manual smoke test with folder scope**

1. Register or re-register Pixel using `Folder` scope and a selected folder id.
2. Upload media into that folder.
3. Confirm Pixel receives and imports it.
4. Upload media into a different folder with the same account.
5. Confirm no Pixel job is created for the folder-scoped target.

- [ ] **Step 7: Final commit if verification-only doc changes were needed**

```powershell
git status --short
```

Expected: no unexpected source changes. Commit only any intentional doc/test updates.

---

## Follow-Up Plan: Pairing Code UX

After this plan is complete, implement pairing code so Pixel does not need username/password input:

- Backend: `POST /api/device-sync/pairing-codes` authenticated by web/iOS account.
- Backend: `POST /api/device-sync/pairing-codes/redeem` anonymous, accepts code + device metadata, returns device token.
- Frontend/iOS: show QR/code for selected scope.
- Pixel: scan QR or enter short code.

This should be separate because it touches web/iOS UI and has different security concerns: code TTL, one-time redemption, rate limiting, and audit logging.

## Self-Review

- Spec coverage: production default URL, account registration, backend-enforced scope, Pixel status, docs, and verification are covered.
- Open marker scan: no open work markers are present.
- Type consistency: `DeviceSyncScope`, `SyncScope`, and `ScopedFolderId` names are consistent across backend and Android DTOs.
- Scope check: the plan excludes cross-account sharing and QR pairing from first implementation to keep the work testable and shippable.
