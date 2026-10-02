import { createHash } from "node:crypto";
import { applyAction, type FarmDocument, type StoredUser, FarmError } from "./domain";

const cookieName = "petclass_session";
export function tokenOf(request: Request) { return request.headers.get("cookie")?.split(";").map(v => v.trim()).find(v => v.startsWith(`${cookieName}=`))?.slice(cookieName.length + 1) || ""; }
export function sessionCookie(request: Request, token: string) { return `${cookieName}=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${token ? 7200 : 0}${new URL(request.url).protocol === "https:" ? "; Secure" : ""}`; }
export function json(data: unknown, status = 200, cookie?: string) { return Response.json(data, { status, headers: { "Cache-Control": "no-store, private", "X-Content-Type-Options": "nosniff", ...(cookie ? { "Set-Cookie": cookie } : {}) } }); }
export async function payload(request: Request) {
  if (request.headers.get("origin") !== new URL(request.url).origin || request.headers.get("sec-fetch-site") === "cross-site") throw new FarmError("허용되지 않은 요청입니다.", 403);
  if (!request.headers.get("content-type")?.includes("application/json")) throw new FarmError("JSON 요청이 필요합니다.", 415);
  const reader=request.body?.getReader(); let size=0; const chunks:Uint8Array[]=[];
  if(reader) for(;;) {const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>16384){await reader.cancel();throw new FarmError("요청이 너무 큽니다.",413);}chunks.push(value);}
  let body;try{body=JSON.parse(Buffer.concat(chunks).toString());}catch{throw new FarmError("요청 형식을 확인해 주세요.");}
  if(!body||typeof body!=="object"||Array.isArray(body))throw new FarmError("요청 형식을 확인해 주세요.");return body as Record<string,unknown>;
}
export async function gateway(action:string,token:string,body:Record<string,unknown>={}) {
  const key=process.env.PETCLASS_API_SECRET;if(!key)throw new FarmError("서버 연결 설정이 필요합니다.",503);
  const response=await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/petclass_gateway`,{method:"POST",headers:{apikey:process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,"Content-Type":"application/json"},body:JSON.stringify({p_key:key,p_action:action,p_token:token,p_body:body}),signal:AbortSignal.timeout(12000),cache:"no-store"});
  const result=await response.json();if(!response.ok)throw new FarmError(result.message||"데이터를 불러오지 못했어요.",response.status===401||response.status===403?response.status:400);if(result?.error)throw new FarmError(result.error,result.status||400);return result;
}
export async function login(request:Request,body:Record<string,unknown>) {
  if(body.role!=="teacher"&&body.role!=="student")throw new FarmError("학생 또는 교사를 선택해 주세요.");
  if(typeof body.code!=="string"||!/^\d{4}$/.test(body.code))throw new FarmError("기존 고유 번호 4자리를 입력해 주세요.");
  // Vercel overwrites this header. Local access shares one limiter key.
  const ip=process.env.VERCEL?request.headers.get("x-vercel-forwarded-for")||"unknown":"local";
  return gateway("login","",{...body,limiter:createHash("sha256").update(`${ip}:${body.role}`).digest("hex")});
}
export async function farmAction(token:string,body:Record<string,unknown>) {
  const action=String(body.action||"");
  if(["purchase","refund","points","price"].includes(action))return gateway(action,token,body);
  if(!["choosePet","useItem","representative","grant","adjustLevel"].includes(action))throw new FarmError("지원하지 않는 작업입니다.",400);
  if(typeof body.requestId!=="string"||!/^[a-zA-Z0-9-]{12,80}$/.test(body.requestId))throw new FarmError("요청 번호를 확인해 주세요.");
  const fingerprint=createHash("sha256").update(JSON.stringify(Object.keys(body).sort().map(k=>[k,body[k]]))).digest("hex");
  const replay=await gateway("request",token,{requestId:body.requestId,fingerprint});if(replay)return replay;
  for(let attempt=0;attempt<4;attempt++) {
    const state=await gateway("state",token);const actor=state.user;if(!actor)throw new FarmError("다시 로그인해 주세요.",401);
    const target=actor.role==="teacher"?state.students.find((s:StoredUser)=>s.id===body.studentId):actor;if(!target)throw new FarmError("학생을 선택해 주세요.");
    const row=actor.role==="teacher"?target:{...actor,pets:state.pets,inventory:state.inventory,claimedStarter:state.claimedStarter,version:state.version};
    const stored={...row,passwordHash:"",authVersion:1,mustChangePassword:false} as StoredUser;
    const doc:FarmDocument={className:"1학년 3반",users:actor.role==="teacher"?[{...actor,passwordHash:"",authVersion:1,mustChangePassword:false,claimedStarter:true,pets:[],inventory:[]} as StoredUser,stored]:[stored]};
    let outcome;
    if(action==="useItem") {
      if(typeof body.quantity!=="number"||!Number.isInteger(body.quantity)||body.quantity<1||body.quantity>999)throw new FarmError("사용 수량을 확인해 주세요.");
      let left=body.quantity;const lots=stored.inventory.filter(g=>!g.revoked&&g.sku===body.sku&&g.remaining>0);
      if(lots.reduce((n,g)=>n+g.remaining,0)<left)throw new FarmError("아이템 수량이 부족합니다.",409);
      for(const lot of lots){if(!left)break;const n=Math.min(left,lot.remaining);outcome=applyAction(doc,actor.id,{...body,action,requestId:body.requestId,grantId:lot.id,quantity:n});left-=n;}
    } else {
      const extra=action==="grant"?{reference:`교사지급-${body.requestId}`}:action==="choosePet"&&stored.claimedStarter?{grantId:stored.inventory.find(g=>g.sku==="pet-choice-ticket"&&!g.revoked&&g.remaining>0)?.id}:{};
      outcome=applyAction(doc,actor.id,{...body,...extra,action,requestId:body.requestId});
    }
    if(!outcome)throw new FarmError("작업을 확인해 주세요.");
    try{return await gateway("commit",token,{studentId:target.id,version:row.version||0,data:{pets:stored.pets,inventory:stored.inventory,claimedStarter:stored.claimedStarter},requestId:body.requestId,fingerprint,message:outcome.message});}
    catch(error){if(!(error instanceof FarmError)||error.status!==409||!error.message.includes("다시 시도"))throw error;}
  }
  throw new FarmError("다른 작업을 처리 중이에요. 다시 시도해 주세요.",409);
}
