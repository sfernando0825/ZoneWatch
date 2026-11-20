# api

Cloudflare Worker (TypeScript, Hono) and D1 database for crowd reports. Built in Phase 4 (8 to 19 Feb 2027).

It stays inside Cloudflare's free tier (100,000 Worker requests a day) until usage grows. Cloudflare API tokens are never committed; local secrets go in `.dev.vars`, which is ignored.
