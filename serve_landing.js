const http = require('http');
const fs = require('fs');
const path = require('path');

// Serve from the project root so /docs/, /assets/, etc. all resolve correctly.
// The landing page itself is at landing/index.html and is served at /.
const ROOT_DIR = __dirname;
const PORT = 8082;

const MIME = {
  '.html': 'text/html',
  '.css':  'text/css',
  '.js':   'application/javascript',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg':  'image/svg+xml',
  '.ico':  'image/x-icon',
  '.pdf':  'application/pdf',
  '.md':   'text/markdown',
};

http.createServer((req, res) => {
  res.setHeader('Cache-Control', 'no-cache');

  const urlPath = req.url.split('?')[0];

  // Serve landing/index.html for the root URL
  let filePath = urlPath === '/'
    ? path.join(ROOT_DIR, 'landing', 'index.html')
    : path.join(ROOT_DIR, urlPath);

  // Prevent path traversal outside project root
  if (!filePath.startsWith(ROOT_DIR)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  // Directory → try index.html inside it
  if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
    filePath = path.join(filePath, 'index.html');
  }

  // File not found → fall back to landing/index.html
  if (!fs.existsSync(filePath)) {
    filePath = path.join(ROOT_DIR, 'landing', 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const mimeType = MIME[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    res.writeHead(200, { 'Content-Type': mimeType });
    res.end(data);
  });
}).listen(PORT, () => {
  console.log(`Serving project root on http://localhost:${PORT} (landing page at /)`);
});
