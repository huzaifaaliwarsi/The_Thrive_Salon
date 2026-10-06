# cPanel frontend release

The production API origin is configured in `config/production.json`.
It is public configuration, not a database connection or credential.
Release builds reject missing, HTTP, and loopback/private IPv4 API addresses.
Debug runs continue to use the isolated local backend unless overridden.

## Building for Production

When ready, run from `mobile`:

```powershell
flutter build web --release --no-tree-shake-icons --dart-define-from-file=config/production.json
```

### Why Icons Disappeared & How It's Fixed:
1. **Material Icons Tree-Shaking**:
   - Release builds enable icon tree-shaking by default, which stripped `MaterialIcons-Regular.otf` down to 8 KB (breaking all Material icons).
   - `--no-tree-shake-icons` prevents this.
   - The full 1.64 MB official `MaterialIcons-Regular.otf` is now placed directly in `assets/fonts/` and `web/assets/fonts/`.
   - A Google Fonts Material Icons fallback is integrated in `web/index.html`.

2. **Lucide Icons Font Resolution**:
   - `web/index.html` has explicit `@font-face` rules for both `'Lucide'` and `'packages/lucide_icons/Lucide'`.
   - Pre-packaged font files are placed in `web/assets/packages/lucide_icons/assets/`, `web/assets/fonts/`, and `web/assets/assets/fonts/` to ensure zero 404s under any renderer (CanvasKit or HTML).
   - An explicit `web/assets/FontManifest.json` is provided.

3. **cPanel Server (.htaccess)**:
   - `web/.htaccess` is pre-configured with font MIME types (`font/otf`, `font/ttf`, `font/woff`, `font/woff2`) and `Access-Control-Allow-Origin: *` to prevent CORS and MIME blocking on Apache / LiteSpeed servers.
   - SPA rewrite rules preserve direct access to font assets.

## Deployment Instructions

1. Run the build command above.
2. Upload the entire contents of `build/web` to your cPanel `public_html` (or subdomain document root `thrive.isywarecloud.com`).
3. Ensure `.htaccess` (hidden file) is uploaded as well.
4. Hard-refresh the browser (`Ctrl + F5` or clear browser cache / service worker) to load the new assets.
