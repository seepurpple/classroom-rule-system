import { FarmError } from "@/lib/domain";
import { gateway,json,payload,tokenOf } from "@/lib/backend";
export async function POST(request:Request){try{const body=await payload(request);const name=String(body.name||"");const args=body.args as Record<string,unknown>||{};return json({data:await gateway("legacy",tokenOf(request),{name,args}),error:null});}catch(error){return json({data:null,error:{message:error instanceof Error?error.message:"요청 실패"}},error instanceof FarmError?error.status:503);}}
