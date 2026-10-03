import { createHash, randomInt } from "node:crypto";
import { gateway } from "./backend";
import { FarmError, requiredText } from "./domain";
import { advanceDuel, startDuel, type Duel } from "./duels";

function paragraph(value:unknown,label:string,max:number,optional=false){
 if(typeof value!=="string"||value.trim().length>max||(!optional&&!value.trim())||Array.from(value).some(c=>c.charCodeAt(0)<32&&![10,13].includes(c.charCodeAt(0))))throw new FarmError(`${label} 값을 확인해 주세요.`);
 return value.trim();
}
export async function battleAction(token:string,body:Record<string,unknown>){
 const action=body.action;
 if(!["challenge","respond","start","move","tournamentCreate"].includes(String(action)))throw new FarmError("지원하지 않는 배틀 작업입니다.");
 if(typeof body.requestId!=="string"||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.requestId))throw new FarmError("요청 번호를 확인해 주세요.");
 if(action==="challenge")return gateway("battleChallenge",token,{opponentId:body.opponentId,requestId:body.requestId});
 if(action==="respond")return gateway("battleRespond",token,{battleId:body.battleId,accept:body.accept});
 if(action==="tournamentCreate")return gateway("tournamentCreate",token,{requestId:body.requestId,name:requiredText(body.name,"대회 이름",80),conditions:paragraph(body.conditions,"참가 조건",2000,true),petLimit:body.petLimit,prize:paragraph(body.prize,"상품",1000)});
 const fingerprint=createHash("sha256").update(JSON.stringify(Object.keys(body).sort().map(k=>[k,body[k]]))).digest("hex");
 const args={battleId:body.battleId,requestId:body.requestId,fingerprint};
 for(let attempt=0;attempt<4;attempt++){
  const context=await gateway("battleContext",token,args);
  if(context.replayed)return gateway("battleLobby",token);
  const {battle,actorId,pets}=context;
  let data:Duel;
  if(action==="start"){
   if(battle.status==="active"||battle.status==="finished")return gateway("battleLobby",token);
   if(battle.status!=="accepted")throw new FarmError("상대가 승인한 뒤 시작할 수 있어요.",409);
   data=startDuel(pets);
  }else{
   if(battle.status!=="active")throw new FarmError("진행 중인 배틀이 아니에요.",409);
   data=advanceDuel(battle.data,actorId===battle.challenger?0:1,body,()=>randomInt(0,0x100000000)/0x100000000);
  }
  try{
   await gateway("battleCommit",token,{...args,version:battle.version,data,status:data.winner===null?"active":"finished"});
   return gateway("battleLobby",token);
  }catch(error){if(!(error instanceof FarmError)||error.status!==409||!error.message.includes("다시 시도"))throw error;}
 }
 throw new FarmError("다른 행동을 처리 중이에요. 다시 시도해 주세요.",409);
}
