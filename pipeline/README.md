# pipeline

Python jobs that build the signed South Australia camera dataset. Built in Phase 2 (14 Dec 2026 to 8 Jan 2027).

Planned contents:

- `sources/`: one parser per government source (SAPOL fixed and weekly mobile lists, data.sa.gov.au location codes, SA phone camera sites).
- `schema/`: the camera dataset JSON schema, shared with the iOS tests.
- A daily GitHub Actions job that validates, signs (Ed25519) and publishes the dataset to Cloudflare R2.

The signing key is never committed. It lives in GitHub Actions secrets.
