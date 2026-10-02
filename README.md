# PetClass

학급 포인트·기존 학생 계정과 개인 펫 키우기를 통합했습니다. React 19 + vinext + Nitro, 기존 Supabase `classroom-rule-system`을 사용합니다.

## 실행

Node.js 22.13 이상에서:

```sh
npm ci
npm run dev -- --port 3016
```

`http://localhost:3016`에서 기존 학생 고유 번호 또는 교사 비밀번호로 로그인합니다. 역할 배정·포인트 대장·역할 신청·학급 관리도 PetClass 메뉴 안에 있습니다(`/classroom`은 홈으로 이동).

로컬 `.env.local`에는 다음 설정이 구성되어 있습니다. 내용은 공유하거나 Git에 올리지 마세요.

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
PETCLASS_API_SECRET=YOUR_RANDOM_SERVER_SECRET
```

배포 시 세 값을 호스팅 환경 변수에 등록합니다. 서버 비밀키는 DB의 `private.petclass_config.key_hash`와 일치해야 합니다. 공개 환경 변수로 만들지 않습니다.

```sh
npm test
npm run typecheck
npm run lint
npm run build
PORT=3016 npm start
```

`supabase/migrations/`는 운영 DB에 적용한 변경 기록입니다(Supabase SQL Editor에서 순서대로 실행). 과거 마이그레이션에는 최초 스키마 전체가 포함되지 않으므로 빈 DB 초기화용으로 사용하지 않습니다. 운영 DB에서 `db reset`을 실행하지 않습니다.

학생 번호 0번은 테스트 계정입니다. 학생 화면과 학급 통계에는 나타나지 않습니다.

웹 이미지: `public/assets/`
