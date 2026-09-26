const express = require('express');
const os = require('os');
const client = require('prom-client');
const app = express();
const port = process.env.PORT || 8080;
const version = process.env.APP_VERSION || '1.0';

client.collectDefaultMetrics({ prefix: 'devops_app_' });
const httpRequests = new client.Counter({ name: 'devops_app_http_requests_total', help: 'Toplam HTTP istek sayısı', labelNames: ['method', 'route', 'status'] });
const httpDuration = new client.Histogram({ name: 'devops_app_http_request_duration_seconds', help: 'HTTP istek süresi', labelNames: ['method', 'route', 'status'], buckets: [0.05, 0.1, 0.25, 0.4, 0.5, 0.75, 1] });

app.use((req, res, next) => {
  if (req.path === '/metrics') return next();
  const started = process.hrtime.bigint();
  res.on('finish', () => {
    const seconds = Number(process.hrtime.bigint() - started) / 1e9;
    const labels = { method: req.method, route: req.path, status: String(res.statusCode) };
    httpRequests.inc(labels);
    httpDuration.observe(labels, seconds);
  });
  next();
});

app.get('/', (_req, res) => res.json({ application: 'devops-app', version, pod: process.env.POD_NAME || os.hostname() }));
app.get('/healthz', (_req, res) => res.json({ status: 'UP', version, pod: process.env.POD_NAME || os.hostname() }));
app.get('/config', (_req, res) => res.json({ message: process.env.APP_MESSAGE || 'not-set', secretLoaded: Boolean(process.env.APP_API_KEY) }));
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});
app.get('/work', (req, res) => {
  const ms = Math.min(Math.max(Number(req.query.ms || 100), 1), 1000);
  const end = Date.now() + ms;
  while (Date.now() < end) Math.sqrt(Math.random());
  res.json({ workedMs: ms, pod: process.env.POD_NAME || os.hostname() });
});
app.listen(port, '0.0.0.0', () => console.log(`devops-app:${version} on ${port}`));
