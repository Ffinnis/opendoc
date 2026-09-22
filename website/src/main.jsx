import React from 'react';
import { createRoot, hydrateRoot } from 'react-dom/client';
import App from './App.jsx';

const root = document.getElementById('root');
if (root.hasChildNodes()) hydrateRoot(root, <App />);
else createRoot(root).render(<App />);
