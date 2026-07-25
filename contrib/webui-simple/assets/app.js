const apiBase = `${window.location.origin}/api`;
const hostname = window.location.hostname || 'localhost';
const poolPort = 3333;
const stratumUrl = `stratum+tcp://${hostname}:${poolPort}`;

const $ = (id) => document.getElementById(id);
const fmtNumber = (value) => {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return '—';
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(Number(value));
};
const fmtHashrate = (value) => {
  const n = Number(value);
  if (!Number.isFinite(n)) return '—';
  const units = ['H/s', 'KH/s', 'MH/s', 'GH/s', 'TH/s', 'PH/s'];
  let scaled = n;
  let i = 0;
  while (scaled >= 1000 && i < units.length - 1) { scaled /= 1000; i += 1; }
  return `${scaled.toFixed(scaled >= 100 ? 0 : scaled >= 10 ? 1 : 2)} ${units[i]}`;
};
const setText = (id, value) => { const el = $(id); if (el) el.textContent = value ?? '—'; };
const setStatus = (text, cls) => {
  const el = $('api-status');
  el.textContent = text;
  el.className = `status-pill ${cls || ''}`;
};

function normalizePools(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.pools)) return payload.pools;
  if (Array.isArray(payload?.result)) return payload.result;
  return [];
}

function pickMflexPool(pools) {
  return pools.find((pool) => String(pool.id || '').toLowerCase() === 'mflex')
      || pools.find((pool) => String(pool.coin?.type || pool.coin?.name || '').toLowerCase().includes('multiflex'))
      || pools[0];
}

async function loadPool() {
  setStatus('Checking API…', 'warn');
  const res = await fetch(`${apiBase}/pools`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`API returned HTTP ${res.status}`);
  const payload = await res.json();
  const pool = pickMflexPool(normalizePools(payload));
  if (!pool) throw new Error('No pool returned by API');

  setText('pool-id', pool.id || 'mflex');
  setText('network', pool.coin?.name || pool.coin?.type || 'Multiflex');
  setText('pool-hashrate', fmtHashrate(pool.poolStats?.poolHashrate || pool.poolStats?.hashrate || pool.hashrate));
  setText('miners', fmtNumber(pool.poolStats?.connectedMiners || pool.connectedMiners || pool.miners));
  setText('workers', fmtNumber(pool.poolStats?.connectedWorkers || pool.connectedWorkers || pool.workers));
  setText('difficulty', fmtNumber(pool.networkStats?.networkDifficulty || pool.networkStats?.difficulty || pool.difficulty));
  setText('blocks-found', fmtNumber(pool.totalBlocks || pool.poolStats?.totalBlocks));
  setText('last-block', pool.lastPoolBlockTime || pool.poolStats?.lastPoolBlockTime || '—');
  setText('payment-threshold', pool.paymentProcessing?.minimumPayment || pool.paymentProcessing?.minimumPaymentToPaymentId || '—');
  setText('min-payout', pool.paymentProcessing?.minimumPayment || '—');
  setStatus('API online', 'ok');
}

function setupInteractions() {
  $('stratum').value = stratumUrl;
  $('stratum-link').href = '#connect';
  $('copy-stratum').addEventListener('click', async () => {
    await navigator.clipboard.writeText(stratumUrl);
    $('copy-stratum').textContent = 'Copied';
    setTimeout(() => { $('copy-stratum').textContent = 'Copy'; }, 1200);
  });
  $('miner-form').addEventListener('submit', (event) => {
    event.preventDefault();
    const address = $('miner-address').value.trim();
    if (!address) return;
    window.open(`${apiBase}/pools/mflex/miners/${encodeURIComponent(address)}`, '_blank', 'noopener');
  });
}

setupInteractions();
loadPool().catch((error) => {
  console.error(error);
  setStatus('API unavailable', 'bad');
});
setInterval(() => loadPool().catch(() => setStatus('API unavailable', 'bad')), 30000);
