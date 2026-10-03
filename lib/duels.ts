import { createFighter, resolveTurn, type Fighter, type TurnChoice } from "./battle";
import { evolutionName, getSpecies } from "./catalog";
import { FarmError } from "./domain";
import type { Account, Pet } from "./types";

export type BattlePet = Fighter & { speciesId: string; stage: number; name: string };
export type Command = { kind: "skill"; name: string } | { kind: "switch"; petId: string };
export type Duel = {
 teams: [BattlePet[], BattlePet[]]; active: [number, number]; choices: [Command | null, Command | null];
 turn: number; winner: 0 | 1 | "draw" | null; logs: string[];
};
export type BattleView = { id: string; challenger: string; opponent: string; status: "pending" | "accepted" | "rejected" | "active" | "finished"; version: number; createdAt: string; data: Omit<Duel,"choices"> & {ready: [boolean,boolean]} };
export type Tournament = { id: string; name: string; conditions: string; petLimit: number; prize: string; createdAt: string };
export type Lobby = { user: Account; students: {id:string;no:number;hasPets:boolean}[]; battles: BattleView[]; tournaments: Tournament[] };
function resetEffects(pet: BattlePet) {
 for (const key of Object.keys(pet.ranks) as (keyof Fighter["ranks"])[]) pet.ranks[key] = 0;
 pet.guard=false;pet.reflect=false;pet.recharge=false;delete pet.dot;delete pet.previousSkill;
}
export function startDuel(pets: [Pet[],Pet[]]): Duel {
 const teams = pets.map(list => {
  if (!list.length || list.length>3) throw new FarmError("두 학생 모두 1~3마리의 펫이 필요해요.");
  return [...list].sort((a,b)=>Number(b.representative)-Number(a.representative)).map(pet => {
   if (!getSpecies(pet.speciesId)) throw new FarmError("등록되지 않은 펫입니다.");
   return {...createFighter(pet),speciesId:pet.speciesId,stage:pet.stage,name:evolutionName(pet.speciesId,pet.stage)};
  });
 }) as Duel["teams"];
 return {teams,active:[0,0],choices:[null,null],turn:1,winner:null,logs:["모의 배틀 시작! 대표 펫이 먼저 나와요."]};
}
export function advanceDuel(source:Duel,side:0|1,body:Record<string,unknown>,random:()=>number=Math.random):Duel {
 const duel=structuredClone(source),other=side===0?1:0;
 if(duel.winner!==null)throw new FarmError("이미 끝난 배틀이에요.",409);
 if(body.kind==="forfeit"){duel.winner=other;duel.choices=[null,null];duel.logs.push(`${side+1}팀이 기권했어요.`);return duel;}
 if(body.turn!==duel.turn)throw new FarmError("이미 처리된 턴이에요. 새로 불러와 주세요.",409);
 const team=duel.teams[side],current=team[duel.active[side]];
 let command:Command;
 if(body.kind==="skill"){
  if(current.hp<=0)throw new FarmError("쓰러진 펫을 먼저 교체해 주세요.");
  if(typeof body.name!=="string"||!current.skills.some(s=>s.name===body.name))throw new FarmError("배우지 않은 기술이에요.");
  command={kind:"skill",name:body.name};
 }else if(body.kind==="switch"){
  const index=team.findIndex(p=>p.id===body.petId);
  if(index<0||index===duel.active[side]||team[index].hp<=0)throw new FarmError("교체 가능한 펫을 골라 주세요.");
  if(current.hp<=0){resetEffects(current);duel.active[side]=index;duel.logs.push(`${team[index].name}(으)로 교체했어요.`);return duel;}
  command={kind:"switch",petId:team[index].id};
 }else throw new FarmError("기술·교체·기권 중 골라 주세요.");
 if(duel.teams[other][duel.active[other]].hp<=0)throw new FarmError("상대가 펫을 교체하는 중이에요.",409);
 if(duel.choices[side])throw new FarmError("이미 행동을 골랐어요. 상대를 기다려 주세요.",409);
 duel.choices[side]=command;
 if(!duel.choices.every(Boolean))return duel;
 const oldActive=[...duel.active];
 const moves=duel.choices.map((choice,i)=>{
  if(choice!.kind==="skill")return choice!.name;
  const id=(choice as Extract<Command,{kind:"switch"}>).petId;
  const index=duel.teams[i].findIndex(p=>p.id===id);
  duel.active[i]=index;
  return {switchTo:duel.teams[i][index]};
 }) as [TurnChoice,TurnChoice];
 const result=resolveTurn([duel.teams[0][oldActive[0]],duel.teams[1][oldActive[1]]],moves,random);
 for(const i of [0,1] as const){
  if(oldActive[i]!==duel.active[i])resetEffects(duel.teams[i][oldActive[i]]);
  Object.assign(duel.teams[i][duel.active[i]],result.fighters[i]);
 }
 const names=new Map(duel.teams.flat().map(p=>[p.id,p.name]));
 const messages=result.events.map(e=>{
  const name=names.get(e.actor)||"펫";
  if(e.kind==="hit")return `${name} · ${e.skill} → ${names.get(e.target!)} ${e.damage?.toFixed(1)} 피해${e.critical?" (치명타)":""}${e.absoluteDefense?" (절대방어)":""}${e.reflected?" (반사)":""}`;
  if(e.kind==="miss")return `${name} · ${e.skill} 빗나감`;
  if(e.kind==="failed")return `${name} · ${e.skill} 연속 사용 실패`;
  if(e.kind==="recharge")return `${name} 쉬는 중`;
  if(e.kind==="switch")return `${name}(으)로 교체`;
  if(e.kind==="dot"||e.kind==="recoil")return `${name} · ${e.kind==="dot"?"낙조":"반동"} ${e.damage?.toFixed(1)} 피해`;
  return `${name} · ${e.skill} 사용`;
 });
 duel.logs.push(`${duel.turn}턴`,...messages);duel.logs=duel.logs.slice(-100);
 const alive=duel.teams.map(team=>team.some(p=>p.hp>0));
 duel.winner=!alive[0]&&!alive[1]?"draw":!alive[0]?1:!alive[1]?0:null;
 duel.choices=[null,null];duel.turn++;
 // Bound zero-damage or repeated defensive matches without changing damage rules.
 if(duel.turn>200&&duel.winner===null){duel.winner="draw";duel.logs.push("200턴이 지나 무승부로 끝났어요.");}
 return duel;
}
