// Run: node tests/minigames-preview.mjs, then open the printed URL.
// Uses only mock responses; never connects to the classroom database.
import { createServer } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const html = `<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>미니게임 렌더링 검증</title><link rel="icon" href="data:,">
<style>*{box-sizing:border-box}body{margin:0}main{padding:20px}#games{display:flex;flex-wrap:wrap;gap:24px}section{width:520px;max-width:100%}</style>
<main class="petclass"><h1>미니게임 렌더링 검증</h1><button id="check">자동 흐름 검사</button><p id="status" role="status">테스트 응답 사용 · 운영 포인트 차감 없음</p><div id="games"></div></main>
<script type="module">
import React from 'react';
import { createRoot } from 'react-dom/client';
import { ClawGame, GachaGame } from '/app/minigames.tsx';
import '/app/petclass.css';
const config = {price:700,prizes:[{name:'간식',weight:60},{name:'특별 선물',weight:30},{name:'꽝',weight:10}],active:true};
const calls = [], errors = [];
window.addEventListener('error', event => errors.push(event.message));
window.addEventListener('unhandledrejection', event => errors.push(String(event.reason)));
const api = async (action, data) => { calls.push({action,data}); return {play:{id:'preview',game:data.game||'claw',status:action==='gameResult'||data.game==='gacha'?'won':'pending',result:'간식'}}; };
const h = React.createElement;
createRoot(document.querySelector('#games')).render(h(React.Fragment,null,
  h('section',{id:'claw'},h('h2',null,'뽑기'),h(ClawGame,{config,balance:10000,api})),
  h('section',{id:'gacha'},h('h2',null,'랜덤박스'),h(GachaGame,{config,balance:10000,api}))));
const waitFor = async predicate => { const deadline=performance.now()+12000; while(!predicate()){ if(performance.now()>deadline)throw Error('화면 전환 시간 초과'); await new Promise(resolve=>setTimeout(resolve,100)); } };
const button = (game,text) => [...document.querySelectorAll('#'+game+' button')].find(el=>el.textContent.includes(text));
document.querySelector('#check').onclick = async event => {
  event.target.disabled=true; const status=document.querySelector('#status'); status.textContent='검사 중';
  try {
    await waitFor(()=>document.querySelectorAll('canvas').length===2);
    button('gacha','START').click(); await waitFor(()=>button('gacha','캡슐 열기')); button('gacha','캡슐 열기').click();
    await waitFor(()=>button('gacha','한 번 더')); button('gacha','한 번 더').click();
    await waitFor(()=>button('gacha','START')); button('gacha','START').click(); await waitFor(()=>button('gacha','캡슐 열기')); button('gacha','캡슐 열기').click();
    await waitFor(()=>button('gacha','한 번 더'));
    button('claw','내고 시작').click(); await waitFor(()=>button('claw','내리기')); button('claw','내리기').click(); await waitFor(()=>button('claw','한 번 더'));
    if(calls.filter(call=>call.action==='gamePlay').length!==3||calls.filter(call=>call.action==='gameResult').length!==1)throw Error('중복 또는 누락된 API 호출');
    if(errors.length)throw Error(errors.join('; '));
    if(document.documentElement.scrollWidth>innerWidth)throw Error('가로 넘침');
    status.textContent='PASS · 캔버스 2개 · 캡슐 재시작 · 집게 결과 · API 호출 수 · 가로 넘침';
  } catch(error) { status.textContent='FAIL · '+error.message; throw error; }
};
</script></html>`;
const preview = { name: 'minigames-preview', configureServer(server) { server.middlewares.use(async (req, res, next) => {
  if (req.url !== '/') return next();
  try { res.setHeader('Content-Type', 'text/html'); res.end(await server.transformIndexHtml('/', html)); }
  catch (error) { next(error); }
}); } };
const server = await createServer({ configFile: false, root, plugins: [react(), preview], server: { host: '127.0.0.1', port: 3018, strictPort: true } });
await server.listen();
console.log('미니게임 검증: http://127.0.0.1:3018/');
