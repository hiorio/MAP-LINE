# 배포

지금은 `localhost:3000`에서만 돕니다. 이 문서는 그걸 인터넷 주소로 옮기는 절차입니다.

## 왜 필요한가

이 제품의 핵심 루프는 **만들기 → 링크 공유 → 상대가 열어봄**입니다. `localhost`는
내 PC를 가리키는 주소라 상대가 열 수 없습니다. 그리고 카카오톡이 링크 미리보기를
만들려면 크롤러가 공개 URL로 OG 태그를 읽어야 하는데 여기도 도달하지 못합니다.

**즉 제품의 절반(공유받은 사람의 경험)은 배포 전까지 검증할 수 없습니다.**

## 두 가지 방법

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

### B. 정식 배포 (Vercel)

Vercel은 Next.js를 만든 회사의 호스팅이라 설정이 사실상 없습니다. 다른 곳(Cloudflare
Pages, Netlify, VPS)도 됩니다 — DB는 이미 Supabase에 있으니 Node가 도는 곳이면 충분합니다.

#### 1. Vercel 계정 만들고 저장소 연결

1. https://vercel.com 에서 GitHub 계정으로 가입
2. `Add New` > `Project`
3. `hiorio/MAP-LINE` 저장소 선택 > `Import`
4. Framework Preset이 **Next.js**로 잡혔는지 확인 (자동으로 잡힙니다)
5. **아직 Deploy를 누르지 마세요.** 환경 변수부터 넣어야 합니다

#### 2. 환경 변수 등록

`Environment Variables` 항목에 `.env.local`의 값을 그대로 옮깁니다.
Production / Preview / Development 전부 체크합니다.

| 변수 | 값 |
|---|---|
| `NEXT_PUBLIC_KAKAO_JS_KEY` | `.env.local`과 동일 |
| `KAKAO_REST_KEY` | `.env.local`과 동일 |
| `NEXT_PUBLIC_SUPABASE_URL` | `.env.local`과 동일 |
| `SUPABASE_SERVICE_ROLE_KEY` | `.env.local`과 동일 |
| `NEXT_PUBLIC_SITE_URL` | **일단 비워 두고 3단계 후에 채웁니다** |

`NEXT_PUBLIC_SUPABASE_ANON_KEY`는 현재 코드에서 쓰지 않으므로 넣지 않아도 됩니다.

#### 3. 배포하고 주소 확인

`Deploy`를 누르면 2~3분 뒤 `https://map-line-xxxx.vercel.app` 형태의 주소가 나옵니다.

#### 4. 배포 후 반드시 할 두 가지

**(1) `NEXT_PUBLIC_SITE_URL`을 그 주소로 채우고 재배포**

Vercel > Settings > Environment Variables에서 값을 넣고,
Deployments 탭에서 `Redeploy`를 누릅니다.

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

## 이후

### 커스텀 도메인

`.vercel.app` 주소도 동작하지만 공유 링크로는 어색합니다. 도메인을 사면
Vercel > Settings > Domains에서 연결하고, `NEXT_PUBLIC_SITE_URL`과 카카오 SDK 도메인을
새 주소로 바꿉니다. 도메인은 연 1~2만원 수준입니다.

### 자동 배포

Vercel은 `main`에 push하면 자동으로 다시 배포합니다. 별도 설정이 필요 없습니다.

### 요금

| 항목 | 지금 | 광고 붙이면 |
|---|---|---|
| Vercel | Hobby (무료) | **Pro 월 $20 필요** — Hobby는 상업적 사용 금지 |
| Supabase | Free (500MB DB, 1GB Storage) | 초과 시 Pro 월 $25 |
| 카카오 API | 무료 쿼터 내 | 경로 건당 10원, 정적 지도 건당 2원 |
| 도메인 | — | 연 1~2만원 |

애드센스를 붙이는 시점에 Vercel Pro가 필요해지는 걸 손익분기 계산에 반드시 넣으세요.

### 주의

- **`SUPABASE_SERVICE_ROLE_KEY`는 RLS를 통과하는 마스터 키입니다.** `NEXT_PUBLIC_` 접두어를
  절대 붙이지 마세요. 붙는 순간 브라우저 번들에 박혀 누구나 DB 전체를 읽고 씁니다
- Vercel의 Preview 배포는 PR마다 임시 주소가 생깁니다. 그 주소는 카카오 SDK 도메인에
  등록돼 있지 않아 지도가 안 뜹니다. 정상입니다
