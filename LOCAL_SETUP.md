# Local development

Open **http://localhost:8081**. Local owner login: `owner@local.test` / `LocalSalon123!`.

Start after restarting Windows:

```powershell
cd "D:\Isysware works\Thrive-Salon-main"
powershell -ExecutionPolicy Bypass -File .\start-local.ps1
```

Rebuild frontend/backend after source changes (restart the backend process if already running):

The local script builds Flutter in debug mode so the localhost API is accepted by the development configuration. Release builds require a public HTTPS API.

```powershell
powershell -ExecutionPolicy Bypass -File .\start-local.ps1 -Rebuild
```

For live backend development, stop the running backend and run `npm.cmd run dev` in `backend`.
For Flutter hot reload use `flutter.bat run -d web-server --web-hostname=127.0.0.1 --web-port=8081 --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:3000` in `mobile`.

## Isolation

- PostgreSQL 18 uses a separate cluster in `.local/postgres`, listening only on `127.0.0.1:55432`.
- Existing system PostgreSQL service and live database are not used.
- Backend `.env` contains a generated local database password and independent JWT secret.
- Non-production backend and Drizzle commands reject any other database host, port, name, or user.
- `backend/scripts/setup-local.cjs` imports only into the fixed local database and refuses to reimport an initialized database.
- Original SQL files are unchanged. Local import removes obsolete PostgreSQL settings and old server ownership/grants.
- Only the local copy receives UUID defaults, a separate owner account, extended subscription, and disabled device settings.
- The local web server blocks network API requests to production through its Content Security Policy.
- Secrets, SQL backups, and the local cluster are ignored by Git.

## Recovered files

`backend/src/db/schema.ts` reconstructs the backup's columns and API relations. `backend/src/index.ts` mounts the existing API modules. The schema recovery helper can regenerate column/relational definitions from the original dump; database constraints remain preserved in the imported SQL. Avoid `db:push` for restoring this database: use the local import script.

Windows Flutter package setup may report missing symlink support for native desktop plugins. The web build uses `--no-pub` after packages have been resolved; no global Developer Mode setting is changed.

The installed Flutter version makes `IconData` final. A project-local copy of `lucide_icons` retains the original icons/font/license and uses direct `IconData` constants so the app compiles without modifying the global package cache.

This is a local development setup. No production deployment has been performed.
