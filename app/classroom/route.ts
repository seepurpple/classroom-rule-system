// 학급 운영 화면은 PetClass 메뉴로 합쳐졌다. 예전 주소·방문 기록은 서버에서 바로 홈으로 보낸다.
export function GET(request: Request) {
  return Response.redirect(new URL("/", request.url), 308);
}
