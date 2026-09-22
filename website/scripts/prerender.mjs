import { readFile, writeFile } from 'node:fs/promises';
import { createServer } from 'vite';
import React from 'react';
import { renderToString } from 'react-dom/server';

// Deliver actual content before JavaScript loads, then hydrate the controls.
const server = await createServer({ server: { middlewareMode: true }, appType: 'custom' });
try {
  const { default: App } = await server.ssrLoadModule('/src/App.jsx');
  const html = await readFile('dist/index.html', 'utf8');
  const content = renderToString(React.createElement(App));
  await writeFile('dist/index.html', html.replace('<div id="root"></div>', `<div id="root">${content}</div>`));
  console.log('Prerendered landing page HTML.');
} finally {
  await server.close();
}
