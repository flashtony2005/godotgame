import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, 'cinderwatch');

function buildThreeClassic() {
  const src = fs.readFileSync(path.join(root, 'vendor', 'three.module.min.js'), 'utf8');
  const i = src.lastIndexOf('export{');
  const j = src.lastIndexOf('}');
  if (i === -1 || j === -1 || j <= i) {
    throw new Error('Could not find export block in three.module.min.js');
  }
  const body = src.slice(0, i);
  const names = src.slice(i + 7, j);
  const pairs = [];
  for (const rawItem of names.split(',')) {
    const item = rawItem.trim();
    if (!item) continue;
    if (item.includes(' as ')) {
      const [local, pub] = item.split(' as ');
      pairs.push(`${pub.trim()}:${local.trim()}`);
    } else {
      pairs.push(`${item}:${item}`);
    }
  }
  const out = `var THREE=(function(){${body}\nreturn {${pairs.join(',')}};})();`;
  if (out.includes('</script')) {
    throw new Error('Unexpected </script sequence in THREE bundle');
  }
  return out;
}

function buildGame() {
  const srcDir = path.join(root, 'src');
  const jsFiles = fs
    .readdirSync(srcDir)
    .filter((f) => f.endsWith('.js'))
    .sort();
  const parts = jsFiles.map((f) => fs.readFileSync(path.join(srcDir, f), 'utf8'));
  const code = `(function(){\n'use strict';\n${parts.join('\n')}\n})();`;
  if (code.includes('</script')) {
    throw new Error('Unexpected </script sequence in game bundle');
  }
  return code;
}

const shell = fs.readFileSync(path.join(root, 'src', 'shell.html'), 'utf8');
const html = shell
  .replace('/*__THREE__*/', () => buildThreeClassic())
  .replace('/*__GAME__*/', () => buildGame());

const outPath = path.join(root, 'index.html');
fs.writeFileSync(outPath, html, 'utf8');
console.log(`built ${Buffer.byteLength(html, 'utf8')} bytes -> ${outPath}`);
