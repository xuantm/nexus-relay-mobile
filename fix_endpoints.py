import os

path = '/workspace/nexus-relay/backend/src/NexusRelay.Backend.Api/Endpoints/DeviceSyncEndpoints.cs'

if not os.path.exists(path):
    print(f"Error: {path} does not exist.")
    exit(1)

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Normalize line endings to LF for easier replacement
has_crlf = '\r\n' in content
content = content.replace('\r\n', '\n')

# Verify target strings exist before replacing
targets = [
    '.RequireAuthorization()\n        .WithName("RegisterDevice")',
    '.AllowAnonymous()\n        .WithName("MarkDeviceSyncJobDownloading")',
    '.AllowAnonymous()\n        .WithName("ConfirmDeviceSyncJob")',
    '.AllowAnonymous()\n        .WithName("FailDeviceSyncJob")',
    '        .WithName("RetryDeviceSyncJob")',
    '        .WithName("ReplayDeviceSync")'
]

for t in targets:
    if t not in content:
        print(f"Warning: Target string not found:\n{t}")

# Apply replacements
content = content.replace(
    '.RequireAuthorization()\n        .WithName("RegisterDevice")',
    '.RequireAuthorization()\n        .DisableAntiforgery()\n        .WithName("RegisterDevice")'
)
content = content.replace(
    '.AllowAnonymous()\n        .WithName("MarkDeviceSyncJobDownloading")',
    '.AllowAnonymous()\n        .DisableAntiforgery()\n        .WithName("MarkDeviceSyncJobDownloading")'
)
content = content.replace(
    '.AllowAnonymous()\n        .WithName("ConfirmDeviceSyncJob")',
    '.AllowAnonymous()\n        .DisableAntiforgery()\n        .WithName("ConfirmDeviceSyncJob")'
)
content = content.replace(
    '.AllowAnonymous()\n        .WithName("FailDeviceSyncJob")',
    '.AllowAnonymous()\n        .DisableAntiforgery()\n        .WithName("FailDeviceSyncJob")'
)
content = content.replace(
    '        .WithName("RetryDeviceSyncJob")',
    '        .DisableAntiforgery()\n        .WithName("RetryDeviceSyncJob")'
)
content = content.replace(
    '        .WithName("ReplayDeviceSync")',
    '        .DisableAntiforgery()\n        .WithName("ReplayDeviceSync")'
)

# Restore CRLF if it was present originally
if has_crlf:
    content = content.replace('\n', '\r\n')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("DeviceSyncEndpoints.cs updated successfully!")
