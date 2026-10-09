const express = require('express');
const path = require('path');
const app = express();
const webRoot = path.resolve(__dirname, '../../mobile/build/web');

app.use((_req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
  next();
});

app.use(express.static(webRoot, { etag: false, maxAge: 0, lastModified: false }));
app.get('/{*path}', (_req, res) => {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
  res.sendFile(path.join(webRoot, 'index.html'));
});

const PORT = 8081;
app.listen(PORT, '0.0.0.0', () => console.log(`Local frontend running on: http://localhost:${PORT}`));
