import { defineConfig } from "vite";
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".woff2": "font/woff2",
};

function serveGleamDocs() {
  const docsDir = path.resolve(__dirname, "build/dev/docs/rototem_web");
  const distDocsDir = path.resolve(__dirname, "dist/docs");

  function ensureDocs() {
    if (!fs.existsSync(path.join(docsDir, "index.html"))) {
      try {
        execSync("gleam docs build", { stdio: "ignore" });
      } catch (err) {
        console.warn("[serveGleamDocs] Failed to build gleam docs automatically:", err.message);
      }
    }
  }

  function handleDocsRequest(req, res, next, baseDir) {
    const url = new URL(req.url, "http://localhost");
    let pathname = url.pathname;

    // Redirect /docs to /docs/ so relative assets (./css/..., ./js/...) resolve accurately
    if (pathname === "/docs") {
      res.writeHead(301, { Location: "/docs/" });
      res.end();
      return;
    }

    if (pathname.startsWith("/docs/")) {
      ensureDocs();
      let relPath = pathname.slice("/docs/".length);
      if (!relPath || relPath === "/" || relPath.endsWith("/")) {
        relPath = path.join(relPath, "index.html");
      }

      let filePath = path.join(baseDir, relPath);

      // Prevent directory traversal
      if (!filePath.startsWith(baseDir)) {
        res.writeHead(403);
        res.end("Forbidden");
        return;
      }

      // If directory requested, look for index.html
      if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
        filePath = path.join(filePath, "index.html");
      }

      if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
        const ext = path.extname(filePath).toLowerCase();
        const contentType = MIME_TYPES[ext] || "application/octet-stream";
        res.writeHead(200, {
          "Content-Type": contentType,
          "Cross-Origin-Opener-Policy": "same-origin",
          "Cross-Origin-Embedder-Policy": "require-corp",
        });
        fs.createReadStream(filePath).pipe(res);
        return;
      }
    }

    next();
  }

  return {
    name: "serve-gleam-docs",
    configureServer(server) {
      ensureDocs();
      server.middlewares.use((req, res, next) => {
        handleDocsRequest(req, res, next, docsDir);
      });
    },
    configurePreviewServer(server) {
      server.middlewares.use((req, res, next) => {
        const targetDir = fs.existsSync(distDocsDir) ? distDocsDir : docsDir;
        handleDocsRequest(req, res, next, targetDir);
      });
    },
  };
}

export default defineConfig({
  base: "./",
  plugins: [serveGleamDocs()],
  server: {
    host: "0.0.0.0",
    port: 3000,
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp"
    }
  },
  preview: {
    host: "0.0.0.0",
    port: 3000,
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp"
    }
  }
});

