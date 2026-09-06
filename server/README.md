# Medicare Track Server

Node.js + Express + TypeScript + Prisma + MySQL backend for Medicare Track.

## Quick Start

1. Copy env file:
   - macOS/Linux: `cp .env.example .env`
   - Windows PowerShell: `Copy-Item .env.example .env`
2. Start MySQL:
   - `docker compose up -d`
3. Install deps:
   - `npm install` (or `npm.cmd install` on Windows if PowerShell execution policy blocks `npm`)
4. Generate Prisma client and migrate:
   - `npm run prisma:generate` (or `npm.cmd run prisma:generate`)
   - `npm run prisma:migrate -- --name init` (or `npm.cmd run prisma:migrate -- --name init`)
5. Seed demo data:
   - `npm run prisma:seed` (or `npm.cmd run prisma:seed`)
6. Run dev server:
   - `npm run dev` (or `npm.cmd run dev`)

Server default: `http://localhost:4000`

Flutter web note:
- Flutter web usually runs on dynamic localhost ports.
- In development, this backend now allows `localhost` and `127.0.0.1` origins automatically.

## Seed Accounts

- Admin: `admin@lifehouse.com` / `password123`
- Caregiver: `sarah.reyes@lifehouse.com` / `password123`
- Family: `ryzamae@gmail.com` / `password123`

## Tests

- `npm test`

Note: integration tests require a reachable MySQL database configured by `DATABASE_URL`.
