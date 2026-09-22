import { access, mkdir, writeFile } from 'node:fs/promises';

// Fetch original Fontshare files for this site's own use. Font binaries are
// excluded from source control; contributors obtain their copy from Fontshare.
const directory = new URL('../public/fonts/', import.meta.url);
const weights = [400, 500, 700];
const present = await Promise.all(weights.map(weight => access(new URL(`satoshi-${weight}.woff2`, directory)).then(() => true, () => false)));
if (present.every(Boolean)) process.exit(0);
const response = await fetch('https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700&display=swap');
if (!response.ok) throw new Error(`Fontshare stylesheet: HTTP ${response.status}`);
const css = await response.text();
await mkdir(directory, { recursive: true });
for (const [index, weight] of weights.entries()) {
  if (present[index]) continue;
  const block = css.split('@font-face').find(face => new RegExp(`font-weight:\\s*${weight}\\s*;`).test(face));
  const path = block?.match(/url\(['"]?(\/\/[^)'"\s]+\.woff2)/)?.[1];
  if (!path) throw new Error(`Fontshare did not return Satoshi ${weight}`);
  const font = await fetch(`https:${path}`);
  if (!font.ok) throw new Error(`Fontshare font: HTTP ${font.status}`);
  const bytes = Buffer.from(await font.arrayBuffer());
  if (bytes.subarray(0, 4).toString() !== 'wOF2') throw new Error('Fontshare returned an invalid WOFF2 file');
  await writeFile(new URL(`satoshi-${weight}.woff2`, directory), bytes);
}
console.log('Prepared original Satoshi webfonts from Fontshare.');
