"use client";
import { useCallback,useEffect,useRef,useState,type ReactNode } from "react";
import Image from "next/image";
import type { Account } from "@/lib/types";
import type { BattlePet,BattleView,Lobby } from "@/lib/duels";
import "./battles.css";

function Popup({title,close,children}:{title:string;close:()=>void;children:ReactNode}){
 const ref=useRef<HTMLDialogElement>(null);
 useEffect(()=>{const previous=document.activeElement as HTMLElement;ref.current?.showModal();return()=>previous?.focus();},[]);
 return <dialog className="pc-dialog pc-battle-dialog" ref={ref} aria-labelledby="battle-title" onCancel={e=>{e.preventDefault();close();}}><div className="pc-dialog-head"><h2 id="battle-title">{title}</h2><button aria-label="배틀 창 닫기" onClick={close}>×</button></div>{children}</dialog>;
}
type Send=(action:string,body?:Record<string,unknown>)=>Promise<boolean>;
export function BattleHub({user,visible}:{user:Account;visible:boolean}){
 const [lobby,setLobby]=useState<Lobby|null>(null),[error,setError]=useState(""),[busy,setBusy]=useState(false),[choose,setChoose]=useState(false),[openId,setOpenId]=useState<string|null>(null);
 const dismissed=useRef(new Set<string>()),pollingBlocked=useRef(false),fetching=useRef(false);
 const working=useRef(false),sequence=useRef(0),retry=useRef(new Map<string,string>()),mounted=useRef(true);
 const refresh=useCallback(async()=>{
  if(working.current||fetching.current)return;
  fetching.current=true;
  const seq=++sequence.current;
  try{const r=await fetch("/api/battle",{cache:"no-store",signal:AbortSignal.timeout(12000)});const data=await r.json();if(!r.ok){if(seq===sequence.current&&r.status>=400&&r.status<500)pollingBlocked.current=true;throw Error(data.error||"배틀을 불러오지 못했어요.");}if(mounted.current&&seq===sequence.current){pollingBlocked.current=false;setLobby(data);setOpenId(current=>current??data.battles.find((b:BattleView)=>b.status==="active"&&!dismissed.current.has(b.id))?.id??null);setError("");}}
  catch(e){if(mounted.current&&seq===sequence.current)setError(e instanceof Error?e.message:"연결을 확인해 주세요.");}
  finally{fetching.current=false;}
 },[]);
 useEffect(()=>{
  mounted.current=true;
  // State updates happen only after the awaited HTTP response.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  void refresh();
  const timer=setInterval(()=>{if(!document.hidden&&!pollingBlocked.current)void refresh();},user.role==="student"?3000:10000);
  const focus=()=>{if(!document.hidden&&!pollingBlocked.current)void refresh();};window.addEventListener("focus",focus);document.addEventListener("visibilitychange",focus);
  return()=>{mounted.current=false;clearInterval(timer);window.removeEventListener("focus",focus);document.removeEventListener("visibilitychange",focus);};
 },[refresh,user.role]);
 async function send(action:string,body:Record<string,unknown>={}){
  if(working.current)return false;working.current=true;sequence.current++;setBusy(true);setError("");
  const key=JSON.stringify({action,...body}),requestId=retry.current.get(key)||crypto.randomUUID();retry.current.set(key,requestId);
  try{const r=await fetch("/api/battle",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({action,...body,requestId}),signal:AbortSignal.timeout(20000)});const data=await r.json();if(!r.ok)throw Error(data.error||"배틀 작업을 처리하지 못했어요.");if(mounted.current){setLobby(data);setOpenId(current=>current??data.battles.find((b:BattleView)=>b.status==="active"&&!dismissed.current.has(b.id))?.id??null);retry.current.delete(key);}return true;}
  catch(e){if(mounted.current)setError(e instanceof Error?e.message:"연결을 확인해 주세요. 같은 행동을 다시 누르면 처리 결과를 확인해요.");return false;}
  finally{working.current=false;if(mounted.current)setBusy(false);}
 }
 const teacher=user.role==="teacher",number=(id:string)=>{const n=lobby?.students.find(s=>s.id===id)?.no;return n===0?"테스트 학생":n===undefined?"학생":`${n}번`;};
 const battle=lobby?.battles.find(b=>b.id===openId);
 const closeBattle=()=>{if(battle)dismissed.current.add(battle.id);setOpenId(null);};
 function cards(incoming:boolean){
  const list=lobby?.battles.filter(b=>(incoming?b.opponent:b.challenger)===user.id)??[];
  return <section className="pc-panel"><div className="pc-battle-section-head"><h2>{incoming?"나에게 걸려 온 배틀":"내가 건 배틀"}</h2>{!incoming&&<button className="pc-primary" disabled={busy||!lobby} onClick={()=>setChoose(true)}>배틀 신청</button>}</div>
   {!list.length&&<p className="pc-subtle">{incoming?"아직 받은 신청이 없어요.":"친구에게 첫 배틀을 신청해 보세요."}</p>}
   {list.map(b=><article className="pc-battle-card" key={b.id}><div><b>{number(incoming?b.challenger:b.opponent)}와 모의 배틀</b><small>{{pending:"승인 대기",accepted:"승인 완료",rejected:"거부됨",active:"배틀 진행 중",finished:"배틀 종료"}[b.status]}</small></div><div className="pc-battle-buttons">
    {incoming&&b.status==="pending"&&<><button disabled={busy} onClick={()=>void send("respond",{battleId:b.id,accept:true})}>승인</button><button disabled={busy} onClick={()=>void send("respond",{battleId:b.id,accept:false})}>거부</button></>}
    {b.status==="accepted"&&<button className="pc-primary" disabled={busy} onClick={async()=>{if(await send("start",{battleId:b.id}))setOpenId(b.id);}}>배틀하기</button>}
    {(b.status==="active"||b.status==="finished")&&<button onClick={()=>setOpenId(b.id)}>{b.status==="active"?"배틀하기":"결과 보기"}</button>}
   </div></article>)}
  </section>;
 }
 return <>
  {visible&&<div className="pc-battle-hub">
   {error&&<p className="pc-notice pc-error" role="alert">{error} <button onClick={()=>void refresh()}>다시 불러오기</button></p>}
   {!teacher&&<><p className="pc-subtle">대표 펫부터 보유 펫 최대 3마리로 대결해요. 실제 펫 체력·스탯과 포인트는 그대로예요.</p><div className="pc-battle-columns">{cards(false)}{cards(true)}</div></>}
   <section className="pc-panel"><h2>우리 반 대회</h2>{teacher&&<TournamentForm busy={busy} send={send}/>}
    {!lobby?<p>불러오는 중…</p>:!lobby.tournaments.length?<p className="pc-subtle">아직 개최된 대회가 없어요.</p>:lobby.tournaments.map(t=><article className="pc-tournament" key={t.id}><h3>{t.name}</h3><span className="pc-pill">참가 가능 펫 {t.petLimit}마리</span><dl><dt>참가 조건</dt><dd>{t.conditions||"제한 없음"}</dd><dt>상품</dt><dd>{t.prize}</dd></dl></article>)}
   </section>
  </div>}
  {choose&&<Popup title="배틀 신청" close={()=>setChoose(false)}><p>배틀할 우리 반 학생 번호를 골라 주세요.</p>{error&&<p role="alert" className="pc-error">{error}</p>}<div className="pc-battle-roster">{lobby?.students.filter(s=>s.id!==user.id).map(s=><button key={s.id} disabled={busy||!s.hasPets||!lobby.students.find(me=>me.id===user.id)?.hasPets} onClick={async()=>{if(await send("challenge",{opponentId:s.id}))setChoose(false);}}>{number(s.id)}{!s.hasPets&&<small>펫 없음</small>}</button>)}</div>{!lobby?.students.find(s=>s.id===user.id)?.hasPets&&<p>내 펫을 먼저 선택해 주세요.</p>}</Popup>}
  {battle&&<Popup title={`${number(battle.challenger)} vs ${number(battle.opponent)}`} close={closeBattle}><BattleWindow key={battle.id} battle={battle} userId={user.id} busy={busy} send={send}/>{error&&<p role="alert" className="pc-error">{error}</p>}<p className="pc-subtle">창을 닫아도 배틀은 유지돼요. 모의 배틀 탭에서 다시 들어올 수 있어요.</p></Popup>}
 </>;
}
function TournamentForm({busy,send}:{busy:boolean;send:Send}){
 const [done,setDone]=useState(false);
 return <form className="pc-tournament-form" onSubmit={async e=>{e.preventDefault();const form=e.currentTarget,f=new FormData(form);setDone(false);if(await send("tournamentCreate",{name:f.get("name"),conditions:f.get("conditions"),petLimit:Number(f.get("petLimit")),prize:f.get("prize")})){form.reset();setDone(true);}}}>
  <label>대회 이름<input name="name" required maxLength={80}/></label><label>참가 조건<textarea name="conditions" maxLength={2000} placeholder="예: 이번 주 활동에 참여한 학생"/></label><p className="pc-subtle">참가 조건은 안내 문구이며 자동으로 제한하지 않아요.</p>
  <label>참가 가능 펫 수<select name="petLimit" defaultValue="3">{[1,2,3].map(n=><option key={n} value={n}>{n}마리</option>)}</select></label><label>상품<textarea name="prize" required maxLength={1000} placeholder="예: 우승자에게 별빛 한입 3개"/></label><button className="pc-primary" disabled={busy}>{busy?"개최 중…":"개최하기"}</button>{done&&<p role="status">우리 반 학생들에게 대회를 알렸어요.</p>}
 </form>;
}
function PetDisplay({pet,label}:{pet:BattlePet;label:string}){
 return <div className="pc-battle-pet"><small>{label}</small><Image src={`/assets/pets/${pet.speciesId}-${pet.stage}.webp`} alt={pet.name} width={220} height={220} unoptimized/><b>{pet.name}</b><small>{pet.types.join(" / ")}</small><progress aria-label={`${label} ${pet.name} 체력`} max={pet.maxHp} value={pet.hp}/><span>{Math.ceil(pet.hp)} / {pet.maxHp} HP</span></div>;
}
function BattleWindow({battle,userId,busy,send}:{battle:BattleView;userId:string;busy:boolean;send:Send}){
 const [menu,setMenu]=useState<"skill"|"switch"|"forfeit"|null>(null);
 const data=battle.data,side=battle.challenger===userId?0:1,other=side===0?1:0;
 const mine=data.teams[side][data.active[side]],enemy=data.teams[other][data.active[other]],ended=battle.status==="finished";
 const forced=mine.hp<=0&&!ended,waiting=data.ready[side],opponentSwitch=enemy.hp<=0&&!ended;
 const canSwitch=data.teams[side].some((p,i)=>i!==data.active[side]&&p.hp>0);
 const disabled=busy||ended||waiting||opponentSwitch;
 const move=async(body:Record<string,unknown>)=>{if(await send("move",{battleId:battle.id,turn:data.turn,...body}))setMenu(null);};
 return <div className="pc-battle-window"><p className="pc-battle-status" role="status">{ended?(data.winner==="draw"?"무승부!":data.winner===side?"승리했어요!":"이번 배틀은 패배했어요."):forced?"펫이 쓰러졌어요. 교체할 펫을 골라 주세요.":opponentSwitch?"상대가 펫을 교체하는 중이에요.":waiting?"상대가 행동을 고르기를 기다려요.":`${data.turn}턴 · 행동을 골라 주세요.`}</p>
  <div className="pc-battle-arena"><PetDisplay pet={mine} label="내 펫"/><span aria-hidden>VS</span><PetDisplay pet={enemy} label="상대 펫"/></div>
  {!ended&&<><div className="pc-battle-controls"><button disabled={disabled||forced} onClick={()=>setMenu("skill")}>기술</button><button disabled={busy||waiting||(!forced&&opponentSwitch)||!canSwitch} onClick={()=>setMenu("switch")}>교체</button><button disabled={busy} onClick={()=>setMenu("forfeit")}>기권</button></div>
   {menu==="skill"&&!forced&&<div className="pc-battle-skills">{mine.skills.map(s=><button key={s.name} disabled={disabled} onClick={()=>void move({kind:"skill",name:s.name})}><b>{s.name}</b><small>{s.type} · {s.category} · 위력 {s.powers.join(" → ")||"—"}</small><small>{s.description}</small></button>)}</div>}
   {(menu==="switch"||forced)&&<div className="pc-battle-skills">{data.teams[side].map((p,i)=><button key={p.id} disabled={busy||p.hp<=0||i===data.active[side]||waiting} onClick={()=>void move({kind:"switch",petId:p.id})}><b>{p.name}</b><small>{Math.ceil(p.hp)} / {p.maxHp} HP {i===data.active[side]?"· 전투 중":""}</small></button>)}</div>}
   {menu==="forfeit"&&<div className="pc-battle-confirm"><p>기권하면 상대가 승리해요. 기권할까요?</p><button disabled={busy} onClick={()=>void move({kind:"forfeit"})}>기권 확정</button><button disabled={busy} onClick={()=>setMenu(null)}>계속 배틀하기</button></div>}
  </>}
  <details className="pc-battle-log" open><summary>전투 기록</summary><ol>{data.logs.map((line,i)=><li key={`${i}-${line}`}>{line}</li>)}</ol></details>
 </div>;
}
