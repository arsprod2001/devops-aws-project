// server.js — NetPulse Backend API
// Collecte et expose les métriques réseau pour le dashboard

const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const http = require('http');

const app = express();
app.use(express.json());
app.use(cors());

// ─── Connexion PostgreSQL ──────────────────────────────────────
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'netpulsedb',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'password',
});

// ─── Initialisation des tables ─────────────────────────────────
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS network_events (
      id        SERIAL PRIMARY KEY,
      pod_src   VARCHAR(128),
      pod_dst   VARCHAR(128),
      namespace VARCHAR(64),
      protocol  VARCHAR(16),
      verdict   VARCHAR(16),         -- ALLOW / DROP / AUDIT
      bytes     INTEGER DEFAULT 0,
      latency   FLOAT DEFAULT 0,
      created_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS alerts (
      id         SERIAL PRIMARY KEY,
      severity   VARCHAR(16),        -- critical / warning / info
      title      VARCHAR(255),
      message    TEXT,
      pod        VARCHAR(128),
      resolved   BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS node_metrics (
      id           SERIAL PRIMARY KEY,
      node_name    VARCHAR(64),
      cpu_pct      FLOAT,
      mem_pct      FLOAT,
      net_rx_mbps  FLOAT,
      net_tx_mbps  FLOAT,
      recorded_at  TIMESTAMP DEFAULT NOW()
    );
  `);

  // Données de démonstration si la table est vide
  const { rowCount } = await pool.query('SELECT 1 FROM network_events LIMIT 1');
  if (rowCount === 0) await seedDemoData();
}

async function seedDemoData() {
  const pods = [
    ['frontend', 'backend', 'netpulse', 'HTTP', 'ALLOW'],
    ['backend', 'postgres', 'netpulse', 'TCP', 'ALLOW'],
    ['frontend', 'postgres', 'netpulse', 'TCP', 'DROP'],
    ['prometheus', 'backend', 'monitoring', 'HTTP', 'ALLOW'],
    ['grafana', 'prometheus', 'monitoring', 'HTTP', 'ALLOW'],
    ['cilium-agent', 'backend', 'kube-system', 'ICMP', 'ALLOW'],
    ['unknown-pod', 'backend', 'netpulse', 'TCP', 'DROP'],
  ];
  for (const [src, dst, ns, proto, verdict] of pods) {
    await pool.query(
      `INSERT INTO network_events
         (pod_src, pod_dst, namespace, protocol, verdict, bytes, latency)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [src, dst, ns, proto, verdict,
        Math.floor(Math.random() * 50000) + 1000,
        Math.random() * 50 + 1]
    );
  }

  // Alertes initiales
  await pool.query(`
    INSERT INTO alerts (severity, title, message, pod) VALUES
      ('critical', 'Trafic DROP détecté',   'Le pod unknown-pod tente d''accéder au backend sans autorisation', 'unknown-pod'),
      ('warning',  'Latence élevée',         'La latence backend→postgres dépasse 40ms',                         'backend'),
      ('info',     'Politique réseau active', 'Cilium NetworkPolicy appliquée sur le namespace netpulse',         'cilium-agent')
  `);

  // Métriques nœuds
  for (let i = 0; i < 20; i++) {
    await pool.query(
      `INSERT INTO node_metrics (node_name, cpu_pct, mem_pct, net_rx_mbps, net_tx_mbps, recorded_at)
       VALUES ($1,$2,$3,$4,$5, NOW() - ($6 || ' minutes')::interval)`,
      ['k8s-worker',
        Math.random() * 60 + 10,
        Math.random() * 50 + 30,
        Math.random() * 100,
        Math.random() * 80,
        i * 5]
    );
  }
}

// ─── Routes de santé ───────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), service: 'netpulse-backend' });
});

// ─── Métriques Prometheus (format texte) ──────────────────────
// Prometheus scrape ce endpoint pour les métriques applicatives
app.get('/metrics', async (_req, res) => {
  try {
    const events = await pool.query(
      `SELECT verdict, COUNT(*) as count
       FROM network_events
       WHERE created_at > NOW() - INTERVAL '5 minutes'
       GROUP BY verdict`
    );
    const alertCount = await pool.query(
      `SELECT COUNT(*) FROM alerts WHERE resolved=false`
    );

    let metrics = `# HELP netpulse_network_events_total Total network events by verdict\n`;
    metrics += `# TYPE netpulse_network_events_total counter\n`;
    for (const row of events.rows) {
      metrics += `netpulse_network_events_total{verdict="${row.verdict}"} ${row.count}\n`;
    }
    metrics += `\n# HELP netpulse_active_alerts Active unresolved alerts\n`;
    metrics += `# TYPE netpulse_active_alerts gauge\n`;
    metrics += `netpulse_active_alerts ${alertCount.rows[0].count}\n`;

    res.set('Content-Type', 'text/plain; version=0.0.4');
    res.send(metrics);
  } catch (e) {
    res.status(500).send('# Error generating metrics\n');
  }
});

// ─── API : Flux réseau ─────────────────────────────────────────
app.get('/api/flows', async (req, res) => {
  const { limit = 50, verdict, namespace } = req.query;
  let query = 'SELECT * FROM network_events';
  const params = [];
  const conditions = [];

  if (verdict)   { params.push(verdict);   conditions.push(`verdict=$${params.length}`); }
  if (namespace) { params.push(namespace); conditions.push(`namespace=$${params.length}`); }

  if (conditions.length) query += ' WHERE ' + conditions.join(' AND ');
  query += ' ORDER BY created_at DESC LIMIT $' + (params.length + 1);
  params.push(parseInt(limit));

  const { rows } = await pool.query(query, params);
  res.json(rows);
});

// ─── API : Statistiques réseau ────────────────────────────────
app.get('/api/stats', async (_req, res) => {
  try {
    const [totals, topFlows, verdicts, protocols] = await Promise.all([
      pool.query(`
        SELECT
          COUNT(*)                                          AS total_flows,
          SUM(bytes)                                        AS total_bytes,
          ROUND(AVG(latency)::numeric, 2)                  AS avg_latency,
          COUNT(*) FILTER (WHERE verdict='DROP')            AS dropped,
          COUNT(*) FILTER (WHERE verdict='ALLOW')           AS allowed
        FROM network_events
        WHERE created_at > NOW() - INTERVAL '1 hour'`),
      pool.query(`
        SELECT pod_src, pod_dst, COUNT(*) AS count
        FROM network_events
        GROUP BY pod_src, pod_dst
        ORDER BY count DESC LIMIT 6`),
      pool.query(`
        SELECT verdict, COUNT(*) AS count
        FROM network_events GROUP BY verdict`),
      pool.query(`
        SELECT protocol, COUNT(*) AS count
        FROM network_events GROUP BY protocol ORDER BY count DESC`),
    ]);

    res.json({
      totals:    totals.rows[0],
      top_flows: topFlows.rows,
      verdicts:  verdicts.rows,
      protocols: protocols.rows,
    });
  } catch (e) {
    res.status(500).json({ error: 'Erreur stats' });
  }
});

// ─── API : Métriques nœuds (historique) ──────────────────────
app.get('/api/nodes/metrics', async (_req, res) => {
  const { rows } = await pool.query(`
    SELECT * FROM node_metrics
    ORDER BY recorded_at DESC LIMIT 60
  `);
  res.json(rows);
});

// ─── API : Alertes ────────────────────────────────────────────
app.get('/api/alerts', async (_req, res) => {
  const { rows } = await pool.query(`
    SELECT * FROM alerts ORDER BY created_at DESC
  `);
  res.json(rows);
});

app.post('/api/alerts/:id/resolve', async (req, res) => {
  await pool.query(
    'UPDATE alerts SET resolved=true WHERE id=$1',
    [req.params.id]
  );
  res.json({ ok: true });
});

// Créer une alerte manuellement (utile pour les tests)
app.post('/api/alerts', async (req, res) => {
  const { severity, title, message, pod } = req.body;
  const { rows } = await pool.query(
    'INSERT INTO alerts (severity,title,message,pod) VALUES ($1,$2,$3,$4) RETURNING *',
    [severity, title, message, pod]
  );
  res.status(201).json(rows[0]);
});

// ─── Simulation de nouveaux flux réseau (toutes les 15s) ──────
// Simule l'arrivée de données depuis Hubble en production
function simulateNetworkFlow() {
  const flows = [
    ['frontend', 'backend', 'netpulse', 'HTTP', 'ALLOW'],
    ['backend', 'postgres', 'netpulse', 'TCP', 'ALLOW'],
    ['prometheus', 'backend', 'monitoring', 'HTTP', 'ALLOW'],
    ['unknown-pod', 'backend', 'netpulse', 'TCP', 'DROP'],
    ['frontend', 'backend', 'netpulse', 'HTTP', 'ALLOW'],
  ];
  const [src, dst, ns, proto, verdict] = flows[Math.floor(Math.random() * flows.length)];
  pool.query(
    `INSERT INTO network_events (pod_src,pod_dst,namespace,protocol,verdict,bytes,latency)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [src, dst, ns, proto, verdict,
      Math.floor(Math.random() * 50000) + 500,
      Math.random() * 60 + 1]
  ).catch(() => {});
}

// ─── Démarrage ────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
const server = http.createServer(app);

initDB()
  .then(() => {
    server.listen(PORT, () => {
      console.log(`🚀 NetPulse Backend démarré sur le port ${PORT}`);
      console.log(`📡 Prometheus metrics : http://localhost:${PORT}/metrics`);
      console.log(`🌐 API flows          : http://localhost:${PORT}/api/flows`);
      setInterval(simulateNetworkFlow, 15000);
    });
  })
  .catch((err) => {
    console.error('❌ Erreur initialisation DB:', err);
    process.exit(1);
  });