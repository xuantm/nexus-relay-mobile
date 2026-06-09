# iPhone Upload API Contract

This contract is consumed by the future iPhone Photos uploader app and implemented by the existing NexusRelay backend.

The iPhone app uploads to NexusRelay. It does not call Pixel APIs and it does not call Google Drive APIs.

## Auth

The current backend login endpoint sets HttpOnly cookies and returns a browser-shaped response. The iPhone app should use cookie-based auth for MVP.

All unsafe HTTP requests (POST, PUT, DELETE) require a CSRF request token passed in the `X-NexusRelay-CSRF` header, and the `nexus_csrf` cookie. The token is obtained via the `/api/auth/csrf` endpoint.

Later, the backend should consider introducing a mobile-specific bearer-token auth endpoint (e.g., OAuth2 or API tokens) to eliminate cookie and CSRF complexities for native clients.

### CSRF Token

```http
GET /api/auth/csrf
```

Response body:

```json
{
  "token": "CfDJ8M..."
}
```

Response cookies:

```text
nexus_csrf=<token>; HttpOnly
```

### Login

```http
POST /api/auth/login
X-NexusRelay-CSRF: CfDJ8M...
Content-Type: application/json
```

Request:

```json
{
  "username": "xuan",
  "password": "password"
}
```

Response body:

```json
{
  "id": "3a3fa2f3-2953-4a8e-8d55-6689cb299e90",
  "username": "xuan",
  "email": "xuan@example.com",
  "role": "Admin"
}
```

Response cookies:

```text
access_token=<jwt>; HttpOnly
refresh_token=<refresh-token>; HttpOnly
```

The app stores cookies/session material in Keychain and attaches them to authenticated requests.

### Refresh

```http
POST /api/auth/refresh
X-NexusRelay-CSRF: CfDJ8M...
Cookie: access_token=<jwt>; refresh_token=<refresh-token>; nexus_csrf=<token>
```

Expected response:

```text
200 OK
```

The backend refreshes auth cookies. If refresh fails, the app pauses uploads and asks the user to log in again.

### Current User

```http
GET /api/auth/me
Cookie: access_token=<jwt>
```

Expected response:

```json
{
  "id": "3a3fa2f3-2953-4a8e-8d55-6689cb299e90",
  "username": "xuan",
  "role": "Admin"
}
```

## Folder APIs

The iPhone app uploads into one configured NexusRelay folder.

### List Root Folders

```http
GET /api/folders
Cookie: access_token=<jwt>
```

Response:

```json
[
  {
    "id": "1f16e90d-6ddb-43fc-8e30-61a71e2e5005",
    "name": "iPhone Uploads",
    "parentId": null,
    "googleDriveFolderId": "drive-folder-id",
    "createdAt": "2026-06-05T00:00:00Z",
    "childCount": 0,
    "mediaCount": 12
  }
]
```

### Create Folder

```http
POST /api/folders
X-NexusRelay-CSRF: CfDJ8M...
Cookie: access_token=<jwt>; nexus_csrf=<token>
Content-Type: application/json
```

Request:

```json
{
  "name": "iPhone Uploads",
  "parentId": null
}
```

Response:

```text
201 Created
```

Body is a `FolderDto`.

### List Folder Media For Reconciliation

```http
GET /api/folders/{folderId}/media?mediaPageSize=60
Cookie: access_token=<jwt>
```

Response body (FolderContentDto):

```json
{
  "folder": {
    "id": "1f16e90d-6ddb-43fc-8e30-61a71e2e5005",
    "name": "iPhone Uploads"
  },
  "subFolders": [],
  "mediaItems": [
    {
      "id": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
      "fileName": "IMG_1001__nr-a3f91c0d8e74b210.HEIC",
      "size": 4820131,
      "mimeType": "image/heic",
      "status": "Completed",
      "uploadStatus": "Uploaded"
    }
  ],
  "media": {
    "items": [
      {
        "id": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
        "fileName": "IMG_1001__nr-a3f91c0d8e74b210.HEIC",
        "size": 4820131,
        "mimeType": "image/heic",
        "status": "Completed",
        "uploadStatus": "Uploaded"
      }
    ],
    "pageSize": 60,
    "hasMore": false,
    "nextCursor": null
  }
}
```

The iPhone app parses media filenames from either `mediaItems` or `media.items` containing:

```text
__nr-<16-hex-fingerprint>
```

and marks matching local assets as already uploaded.

For the iPhone app, the shared `uploadStatus` is a user-facing projection:

- `Pending`
- `Uploading`
- `Uploaded`
- `Failed`

The app keeps its richer internal ledger states locally and maps them onto this display/API shape.

## Upload APIs

Use the same upload behavior as the web app:

```text
Stream upload <= 90 MB
Chunked upload > 90 MB
Chunk size = 30 MB
```

### Stream Upload

```http
POST /api/upload/stream
X-NexusRelay-CSRF: CfDJ8M...
Cookie: access_token=<jwt>; nexus_csrf=<token>
x-file-name: IMG_1001__nr-a3f91c0d8e74b210.HEIC
x-folder-id: 1f16e90d-6ddb-43fc-8e30-61a71e2e5005
x-file-size: 4820131
Content-Type: image/heic

<file bytes>
```
Note: `x-file-name` should be URL-percent-encoded when sent in headers (e.g. `IMG_1001__nr-a3f91c0d8e74b210.HEIC` is already URL-safe, but others might have spaces or special characters).

Response:

```json
{
  "uploadId": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1"
}
```

For stream uploads, this response means the backend accepted the upload and started/completed its backend-side handling. Pixel delivery still depends on the backend marking the media item `Completed`.

### Initialize Chunked Upload

```http
POST /api/upload/init
X-NexusRelay-CSRF: CfDJ8M...
Cookie: access_token=<jwt>; nexus_csrf=<token>
Content-Type: application/json
```

Request:

```json
{
  "folderId": "1f16e90d-6ddb-43fc-8e30-61a71e2e5005",
  "fileName": "IMG_2001__nr-bd02941f22ac9170.MOV",
  "totalSize": 285212672,
  "totalChunks": 10
}
```

Response:

```json
{
  "uploadId": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1"
}
```

### Upload Chunk

```http
POST /api/upload/chunk
X-NexusRelay-CSRF: CfDJ8M...
Cookie: access_token=<jwt>; nexus_csrf=<token>
x-upload-id: 94aa00ac-219a-4d65-8ff4-11ffc7a042e1
x-chunk-index: 0
x-chunk-size: 31457280
Content-Type: application/octet-stream

<chunk bytes>
```

Response:

```json
{
  "uploadId": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
  "chunkIndex": 0,
  "status": "received"
}
```

### Complete Chunked Upload

```http
POST /api/upload/complete
X-NexusRelay-CSRF: CfDJ8M...
Cookie: access_token=<jwt>; nexus_csrf=<token>
Content-Type: application/json
```

Request:

```json
{
  "uploadId": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
  "fileHash": "sha256-hex-or-null"
}
```

Response:

```json
{
  "uploadId": "94aa00ac-219a-4d65-8ff4-11ffc7a042e1",
  "status": "relaying"
}
```

## Filename Fingerprint Contract

The app should upload filenames with a NexusRelay marker:

```text
<original-name-without-extension>__nr-<16-hex-fingerprint>.<extension>
```

The marker is client-generated and backend-agnostic. It allows the app to reconcile already-uploaded assets using existing folder media APIs, without adding mobile-specific backend endpoints.

Rules:

- Keep the original extension when available.
- Sanitize `/`, `\`, quotes, CR, and LF from names.
- Never put the raw Photos `localIdentifier` in the filename.
- If the original filename already contains `__nr-`, append the new marker at the end of the base name.

## Expected Auth Failure Handling

For any authenticated API call:

```text
401 Unauthorized -> call /api/auth/refresh -> retry original request once
refresh fails -> pause queue and show login required
```

The app should not retry a request indefinitely after auth failure.
