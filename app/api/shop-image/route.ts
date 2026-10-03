import { FarmError } from "@/lib/domain";
import { gateway } from "@/lib/backend";
// Teacher-uploaded item images live in the DB as data URLs; the URL carries a content hash, so cache forever.
export async function GET(request:Request){try{const q=new URL(request.url).searchParams;const r=await gateway("productImage","",{sku:q.get("sku")||"",classId:q.get("c")||""});const m=/^data:(image\/(?:webp|png|jpeg));base64,(.+)$/.exec(r?.image||"");if(!m)return new Response("Not found",{status:404});return new Response(Buffer.from(m[2],"base64"),{headers:{"Content-Type":m[1],"Cache-Control":"public, max-age=31536000, immutable","X-Content-Type-Options":"nosniff"}});}catch(error){return new Response("Not found",{status:error instanceof FarmError?error.status:503});}}
