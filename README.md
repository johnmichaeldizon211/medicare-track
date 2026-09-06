# Medicare Track

Flutter frontend + Node.js/Express backend + MySQL database.

## Run Full Stack (Windows PowerShell)

1. Start MySQL (Docker):
```powershell
cd server
docker compose up -d
```

2. Backend setup and run:
```powershell
cd server
Copy-Item .env.example .env -ErrorAction SilentlyContinue
npm.cmd install
npm.cmd run prisma:generate
npm.cmd run prisma:migrate -- --name init
npm.cmd run prisma:seed
npm.cmd run dev
```

3. In a new terminal, run Flutter app:
```powershell
flutter pub get
flutter run -d chrome
```

## Default URLs

- Backend: `http://localhost:4000`
- Flutter web: dynamic localhost port (auto-allowed by backend in development)

## Seed Accounts

- Admin: `admin@lifehouse.com` / `password123`
- Caregiver: `sarah.reyes@lifehouse.com` / `password123`
- Family: `ryzamae@gmail.com` / `password123`
