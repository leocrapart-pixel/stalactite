// Minimal static file server for the built app.
const http = require("http");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "web");
const port = Number(process.env.PORT || 4173);
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css", ".svg": "image/svg+xml", ".json": "application/json" };

http
  .createServer((req, res) => {
    const url = decodeURIComponent((req.url || "/").split("?")[0]);
    // app.js is built into web/; main.js lives in js/ so the Elm sources and
    // the shim stay together.
    const candidates = [
      path.join(root, url === "/" ? "index.html" : url),
      path.join(__dirname, "js", path.basename(url)),
    ];
    const file = candidates.find((f) => f.startsWith(root) || f.startsWith(path.join(__dirname, "js")));
    if (!file) { res.writeHead(403).end("forbidden"); return; }
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404).end("not found"); return; }
      res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream", "cache-control": "no-store" });
      res.end(data);
    });
  })
  .listen(port, "127.0.0.1", () => console.log("stalactite on http://127.0.0.1:" + port + "/"));
