const express = require('express');
const os = require('os');
const app = express();
const port = process.env.PORT || 8080;
const version = process.env.APP_VERSION || '1.0';

app.get('/', (_req, res) => res.json({ application: 'devops-app', version, pod: process.env.POD_NAME || os.hostname() }));
app.get('/healthz', (_req, res) => res.json({ status: 'UP', version, pod: process.env.POD_NAME || os.hostname() }));
app.get('/config', (_req, res) => res.json({ message: process.env.APP_MESSAGE || 'not-set', secretLoaded: Boolean(process.env.APP_API_KEY) }));
app.get('/work', (req, res) => {
  const ms = Math.min(Math.max(Number(req.query.ms || 100), 1), 1000);
  const end = Date.now() + ms;
  while (Date.now() < end) Math.sqrt(Math.random());
  res.json({ workedMs: ms, pod: process.env.POD_NAME || os.hostname() });
});
app.listen(port, '0.0.0.0', () => console.log(`devops-app:${version} on ${port}`));
