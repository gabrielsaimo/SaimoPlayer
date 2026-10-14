// Grava a abertura quadro a quadro no Chrome sem janela: node gravar.mjs <largura> <altura> <fps> <pasta>
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
const [W, H, FPS, PASTA] = [+process.argv[2], +process.argv[3], +process.argv[4], process.argv[5]];
mkdirSync(PASTA, { recursive: true });
const porta = 9333 + Math.floor(Math.random() * 500);
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ['--headless=new', `--remote-debugging-port=${porta}`, '--user-data-dir=' + PASTA + '/.perfil', '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });
const espera = ms => new Promise(r => setTimeout(r, ms));
let alvo;
for (let i = 0; i < 50 && !alvo; i++) { await espera(200); try { alvo = (await (await fetch(`http://127.0.0.1:${porta}/json`)).json()).find(t => t.type === 'page'); } catch {} }
const ws = new WebSocket(alvo.webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id = 0; const pend = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } };
const cdp = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await cdp('Page.enable');
await cdp('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
await cdp('Page.navigate', { url: 'file://' + process.cwd() + '/abertura-saimo.html?gravar' });
await espera(2500);
const DUR = 4.6, N = Math.round(DUR * FPS);
for (let f = 0; f <= N; f++) {
  await cdp('Runtime.evaluate', { expression: `quadroEm(${f / FPS})` });
  const r = await cdp('Page.captureScreenshot', { format: 'png' });
  writeFileSync(`${PASTA}/q${String(f).padStart(4, '0')}.png`, Buffer.from(r.result.data, 'base64'));
}
ws.close(); chrome.kill();
console.log('quadros', N + 1);
