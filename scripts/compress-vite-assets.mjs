import {
  brotliCompressSync,
  constants as zlibConstants,
  gzipSync,
} from 'node:zlib';
import {
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { extname, join } from 'node:path';

const assetsDir = process.argv[2] || 'public/vite/assets';
const minBytes = 1024;
const compressibleExtensions = new Set(['.css', '.js', '.json', '.svg']);
const ignoredExtensions = new Set(['.br', '.gz', '.map']);

const writeIfChanged = (filePath, contents) => {
  if (existsSync(filePath)) {
    const existing = readFileSync(filePath);
    if (Buffer.compare(existing, contents) === 0) {
      return false;
    }
  }

  writeFileSync(filePath, contents);
  return true;
};

const walk = dir => {
  const entries = readdirSync(dir, { withFileTypes: true });
  return entries.flatMap(entry => {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      return walk(fullPath);
    }

    return entry.isFile() ? [fullPath] : [];
  });
};

const shouldCompress = filePath => {
  const extension = extname(filePath);
  if (
    ignoredExtensions.has(extension) ||
    !compressibleExtensions.has(extension)
  ) {
    return false;
  }

  return statSync(filePath).size > minBytes;
};

if (!existsSync(assetsDir)) {
  console.log(`[compress-vite-assets] Skipping: ${assetsDir} does not exist`);
  process.exit(0);
}

let filesCompressed = 0;
let filesWritten = 0;

for (const filePath of walk(assetsDir)) {
  if (!shouldCompress(filePath)) {
    continue;
  }

  const source = readFileSync(filePath);
  const brotli = brotliCompressSync(source, {
    params: {
      [zlibConstants.BROTLI_PARAM_QUALITY]: 9,
    },
  });
  const gzip = gzipSync(source, { level: 9 });

  filesCompressed += 1;
  if (writeIfChanged(`${filePath}.br`, brotli)) {
    filesWritten += 1;
  }
  if (writeIfChanged(`${filePath}.gz`, gzip)) {
    filesWritten += 1;
  }
}

console.log(
  `[compress-vite-assets] Compressed ${filesCompressed} assets, wrote ${filesWritten} files`
);
