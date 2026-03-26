#!/usr/bin/env node
const https = require('https');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const os = require('os');

const PORT = 2000;

const server = https.createServer({
  cert: fs.readFileSync(path.join(__dirname, 'certs/cert.pem')),
  key: fs.readFileSync(path.join(__dirname, 'certs/key.pem')),
});

// ─── VirtualHID ───
let vhidProcess = null;
function initVhid() {
  vhidProcess = spawn(path.join(__dirname, 'vhid_key'), [], {
    stdio: ['pipe', 'ignore', 'pipe']
  });
  vhidProcess.stderr.on('data', d => process.stderr.write(d));
  vhidProcess.on('error', e => console.error('[VHID]', e.message));
  vhidProcess.on('close', c => { console.log('[VHID] exited', c); vhidProcess = null; });
}
function keyTap() {
  if (vhidProcess && vhidProcess.stdin.writable) vhidProcess.stdin.write('tap\n');
}

// ─── Audio (persistent sox process) ───
let soxProc = null;
function ensureAudio() {
  if (soxProc && !soxProc.killed) return;
  soxProc = spawn('sox', [
    '-t', 'raw', '-r', '48000', '-e', 'signed-integer', '-b', '16', '-c', '1',
    '-', '-t', 'coreaudio', 'USB Audio Device'
  ], { stdio: ['pipe', 'ignore', 'pipe'] });
  soxProc.stderr.on('data', d => {
    const m = d.toString().trim();
    if (m && !m.startsWith('In:')) console.log('[sox]', m);
  });
  soxProc.on('error', e => { console.error('[sox] error:', e.message); soxProc = null; });
  soxProc.on('close', () => { console.log('[sox] exited, will restart on next audio'); soxProc = null; });
  console.log('[Audio] sox started (persistent)');
}

// ─── HTTP Routes ───
server.on('request', (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  if (req.url === '/' || req.url === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(fs.readFileSync(path.join(__dirname, 'public/index.html')));
    return;
  }
  if (req.url === '/rootCA.pem') {
    const p = path.join(__dirname, 'public/rootCA.pem');
    if (fs.existsSync(p)) {
      res.writeHead(200, { 'Content-Type': 'application/x-x509-ca-cert' });
      res.end(fs.readFileSync(p));
    } else { res.writeHead(404); res.end(); }
    return;
  }
  if (req.url === '/ping') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('pong');
    return;
  }
  if (req.url === '/key/start' && req.method === 'POST') {
    console.log('[Key] TAP start');
    keyTap();
    ensureAudio();
    res.writeHead(200); res.end('ok');
    return;
  }
  if (req.url === '/key/stop' && req.method === 'POST') {
    console.log('[Key] TAP stop');
    keyTap();
    // Don't kill sox — keep it running for next session
    res.writeHead(200); res.end('ok');
    return;
  }
  if (req.url === '/audio' && req.method === 'POST') {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => {
      ensureAudio();
      if (soxProc && soxProc.stdin.writable) {
        soxProc.stdin.write(Buffer.concat(chunks));
      }
      res.writeHead(200); res.end('ok');
    });
    return;
  }
  res.writeHead(404); res.end('Not Found');
});

// ─── Startup ───
function getLocalIP() {
  const nets = os.networkInterfaces();
  for (const n of Object.keys(nets))
    for (const i of nets[n])
      if (i.family === 'IPv4' && !i.internal && i.address.startsWith('192.168'))
        return i.address;
  return 'localhost';
}

process.on('uncaughtException', err => {
  if (err.code === 'EPIPE') return;
  console.error('[Fatal]', err); process.exit(1);
});

if (process.getuid() !== 0) { console.error('sudo node server.js'); process.exit(1); }

console.log('[VHID] Starting...');
initVhid();

const ip = getLocalIP();
server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n✅ Vibe Coding Magic Button started`);
  console.log(`📱 iPhone: https://${ip}:${PORT}`);
  console.log(`🎤 Audio: USB Audio Device`);
  console.log(`⌨️  Key: Left Option/Alt\n`);
});

process.on('SIGINT', () => {
  if (soxProc) { try{soxProc.kill();}catch{} }
  if (vhidProcess) vhidProcess.kill();
  process.exit(0);
});
process.on('SIGTERM', () => process.emit('SIGINT'));
