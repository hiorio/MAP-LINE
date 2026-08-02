# 배포

지금은 `localhost:3000`에서만 돕니다. 이 문서는 그걸 인터넷 주소로 옮기는 절차입니다.

## 왜 필요한가

이 제품의 핵심 루프는 **만들기 → 링크 공유 → 상대가 열어봄**입니다. `localhost`는
내 PC를 가리키는 주소라 상대가 열 수 없습니다. 그리고 카카오톡이 링크 미리보기를
만들려면 크롤러가 공개 URL로 OG 태그를 읽어야 하는데 여기도 도달하지 못합니다.

**즉 제품의 절반(공유받은 사람의 경험)은 배포 전까지 검증할 수 없습니다.**

## 어디에 배포할까

이 프로젝트는 **Vercel 전용 기능을 하나도 쓰지 않습니다.** `next/image`도, `@vercel/og`도,
Edge Runtime도 안 씁니다. 그냥 Node가 도는 곳이면 어디든 됩니다. DB는 이미 Supabase에 있습니다.

| | Railway | Vercel |
|---|---|---|
| 실행 방식 | 상시 켜져 있는 Node 서버 | 서버리스 함수 |
| 광고 게재 | 요금제 제약 없음 | **Hobby는 상업적 사용 금지 → Pro 월 $20** |
| 사용량 카운터(`/api/usage`) | ✅ 정확 (단일 인스턴스) | ⚠️ 인스턴스마다 따로 세어 과소 집계 |
| 콜드 스타트 | 없음 | 있음 |
| 설정 | Nixpacks 자동 감지 | 자동 감지 |

**이 제품에는 Railway가 더 맞습니다.** 애드센스를 붙일 계획이 로드맵(v0.3)에 있는데
Vercel Hobby는 상업적 사용을 금지하므로 그 시점에 월 $20이 추가됩니다. 그리고
`lib/kakao/usage.ts`의 쿼터 카운터가 프로세스 메모리에 있어서, 서버가 하나로 계속
떠 있는 Railway에서는 실제로 정확하게 동작합니다.

아래는 Railway 기준으로 적고, Vercel 절차도 뒤에 남겨 둡니다.

## 배포 전 임시 확인 — 터널

| | 임시 터널 | 정식 배포 |
|---|---|---|
| 걸리는 시간 | 10초 | 20분 |
| 주소 | 매번 바뀌는 임의 주소 | 고정 |
| PC를 꺼도 되나 | ❌ 내 PC가 서버 | ✅ |
| 용도 | 카톡 인앱 브라우저 테스트 | 실제 서비스 |

### A. 임시 터널 — 테스트만 할 때

```bash
npx cloudflared tunnel --url http://localhost:3000
```

`https://xxxx-yyyy.trycloudflare.com` 같은 주소가 출력됩니다.

1. 카카오 콘솔 > 앱 > 플랫폼 키 > JavaScript 키 > SDK 도메인에 그 주소 추가
2. 폰에서 열어 보거나, 카톡으로 자신에게 링크를 보내 인앱 브라우저에서 확인

터미널을 닫으면 주소가 사라집니다. 다시 켜면 다른 주소가 나오므로 도메인도 다시
등록해야 합니다. **테스트용으로만 쓰세요.**

### B. 정식 배포 (Railway)

Railway는 Nixpacks가 Next.js를 자동 감지해 `npm install` → `npm run build` → `npm start`를
실행합니다. **이 순서는 로컬에서 검증해 뒀습니다** — `PORT` 환경변수를 주입해 실행했을 때
랜딩·API·뷰어·OG 썸네일·저장·삭제까지 전부 정상 동작합니다.

#### 1. 프로젝트 생성

1. https://railway.app 에서 GitHub 계정으로 로그인
2. `New Project` > `Deploy from GitHub repo`
3. `hiorio/MAP-LINE` 선택
4. 첫 빌드가 자동으로 시작됩니다. **환경 변수가 없어 실패하거나 반쪽으로 뜨는 게 정상입니다** —
   다음 단계에서 채웁니다

#### 2. 환경 변수 등록

서비스 > `Variables` 탭에서 `.env.local`의 값을 그대로 옮깁니다.

| 변수 | 값 |
|---|---|
| `NEXT_PUBLIC_KAKAO_JS_KEY` | `.env.local`과 동일 |
| `KAKAO_REST_KEY` | `.env.local`과 동일 |
| `NEXT_PUBLIC_SUPABASE_URL` | `.env.local`과 동일 |
| `SUPABASE_SERVICE_ROLE_KEY` | `.env.local`과 동일 |
| `NEXT_PUBLIC_SITE_URL` | **3단계에서 도메인을 만든 뒤 채웁니다** |

`PORT`도 함께 넣습니다.

```
PORT=3000
```

`next start`는 `PORT`가 없으면 3000을 쓰므로 값 자체는 같지만, 다음 단계에서 도메인이
포워딩할 **Target Port를 직접 입력해야 하므로** 양쪽을 같은 값으로 못 박아 둔다.
어긋나면 앱은 정상인데 502만 돌아온다.

`NEXT_PUBLIC_SUPABASE_ANON_KEY`는 현재 코드에서 쓰지 않으므로 넣지 않아도 됩니다.

> **`NEXT_PUBLIC_`이 붙은 변수는 빌드 시점에 코드 안으로 박힙니다.** 나중에 값만 바꾸면
> 반영되지 않고 반드시 재배포해야 합니다. Railway는 변수를 바꾸면 자동으로 재배포합니다.

#### 3. 도메인 만들기

서비스 > `Settings` > `Networking` > `Generate Domain`을 누르면
`https://map-line-production-xxxx.up.railway.app` 형태의 주소가 생깁니다.

**Target Port를 입력하라는 란이 뜨면 `3000`을 넣습니다.** 앞 단계에서 `PORT=3000`을
설정했으므로 앱이 듣는 포트와 일치합니다. 두 값이 다르면 배포는 성공했는데 접속만 502가 됩니다.

#### 4. 배포 후 반드시 할 두 가지

**(1) `NEXT_PUBLIC_SITE_URL`을 그 주소로 채우기**

`Variables`에 넣으면 Railway가 자동으로 재배포합니다.

이걸 안 하면 OG 이미지 주소가 `http://localhost:3000/api/og/...`를 가리켜서
**카카오톡 미리보기에 썸네일이 안 뜹니다.** 배포에서 가장 흔히 빠뜨리는 단계입니다.

**(2) 카카오 콘솔에 도메인 등록**

카카오 콘솔 > 앱 > 플랫폼 키 > JavaScript 키 > SDK 도메인에 배포 주소를 추가합니다.
안 하면 지도 타일이 아예 안 뜹니다.

`http://localhost:3000`은 지우지 말고 그대로 두세요. 개발할 때 계속 씁니다.

#### 5. 확인

- [ ] 랜딩이 뜨는가
- [ ] `지도 만들기` → 편집기에서 지도 타일이 보이는가 (안 보이면 4-(2) 누락)
- [ ] 핀 찍고 그림 그린 뒤 우상단이 `저장됨`인가
- [ ] `공유` → 카톡으로 링크 전송 → **미리보기에 지도 썸네일이 뜨는가** (안 뜨면 4-(1) 누락)
- [ ] 카톡에서 링크를 눌러 인앱 브라우저로 열리는가

### C. Vercel을 쓸 경우

절차는 Railway와 거의 같습니다.

1. https://vercel.com 가입 > `Add New` > `Project` > `hiorio/MAP-LINE` Import
2. Framework Preset이 **Next.js**로 잡혔는지 확인 (자동)
3. `Environment Variables`에 위 표와 같은 값 등록 (Production/Preview/Development 전부 체크)
4. `Deploy` > `https://map-line-xxxx.vercel.app` 주소 확인
5. `NEXT_PUBLIC_SITE_URL`을 그 주소로 채우고 Deployments 탭에서 `Redeploy`
6. 카카오 콘솔 SDK 도메인에 주소 추가

Vercel 특유의 주의점:

- **Hobby 요금제는 상업적 사용이 금지됩니다.** 애드센스를 붙이는 순간 Pro(월 $20)가 필요합니다
- Preview 배포는 PR마다 임시 주소가 생기는데, 그 주소는 카카오 SDK 도메인에 없어 지도가
  안 뜹니다. 정상입니다
- 서버리스라 인스턴스가 여러 개 뜨므로 `/api/usage`의 쿼터 카운터가 과소 집계됩니다

## 이후

### 커스텀 도메인

`.up.railway.app` / `.vercel.app` 주소도 동작하지만 공유 링크로는 어색합니다.
도메인을 사면 각 플랫폼의 Domains 설정에서 연결하고, `NEXT_PUBLIC_SITE_URL`과
카카오 SDK 도메인을 새 주소로 바꿉니다. 도메인은 연 1~2만원 수준입니다.

### 자동 배포

Railway와 Vercel 모두 `main`에 push하면 자동으로 다시 배포합니다. 별도 설정이 없습니다.

### 요금

| 항목 | 지금 | 광고 붙이면 |
|---|---|---|
| Railway | 사용량 기반 (Hobby $5/월 크레딧 포함) | 요금제 제약 없음 |
| Vercel | Hobby (무료) | **Pro 월 $20 필요** — Hobby는 상업적 사용 금지 |
| Supabase | Free (500MB DB, 1GB Storage) | 초과 시 Pro 월 $25 |
| 카카오 API | 무료 쿼터 내 | 경로 건당 10원, 정적 지도 건당 2원 |
| 도메인 | — | 연 1~2만원 |

요금제는 자주 바뀌니 실제 금액은 각 플랫폼에서 확인하세요.

### 주의

**`SUPABASE_SERVICE_ROLE_KEY`는 RLS를 통과하는 마스터 키입니다.** `NEXT_PUBLIC_` 접두어를
절대 붙이지 마세요. 붙는 순간 브라우저 번들에 박혀 누구나 DB 전체를 읽고 쓸 수 있습니다.
