import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const port = Number(process.env.PORT) || 3000;
const host = '0.0.0.0';
const staticDir = path.join(__dirname, 'cinderwatch');

app.use(express.static(staticDir));

app.use((_req, res) => {
  res.sendFile(path.join(staticDir, 'index.html'));
});

app.listen(port, host, () => {
  console.log(`Cinderwatch server listening on http://${host}:${port}`);
});
