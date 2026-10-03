import { battleAction } from "@/lib/battle-backend";
import { gateway,json,payload,tokenOf } from "@/lib/backend";
import { FarmError } from "@/lib/domain";
export async function GET(request:Request){try{return json(await gateway("battleLobby",tokenOf(request)));}catch(error){return json({error:error instanceof Error?error.message:"배틀을 불러오지 못했어요."},error instanceof FarmError?error.status:503);}}
export async function POST(request:Request){try{return json(await battleAction(tokenOf(request),await payload(request)));}catch(error){return json({error:error instanceof Error?error.message:"배틀 작업을 처리하지 못했어요."},error instanceof FarmError?error.status:503);}}
