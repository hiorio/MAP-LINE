# HANDOFF — MAP-LINE

마지막 갱신: 2026-08-02

다른 AI 세션이 이 문서 하나만 읽고 바로 이어서 작업할 수 있도록 쓴 인수인계 문서입니다.
설계 배경과 근거는 [README.md](README.md)에 있으니 "왜 이렇게 했는가"가 궁금하면 거기를 봅니다.
이 문서는 "지금 뭐가 되고, 뭐가 안 되고, 다음에 뭘 하면 되는가"만 다룹니다.

## 지금 상태를 한 줄로

**v0.1 기능이 전부 구현·검증됐고 서울 리전 Supabase에 배포까지 끝났습니다.**
만들기 → 공유 링크 → 상대가 열어봄까지 OG 썸네일 포함해 실제로 동작합니다.

- 배포본: https://map-line-production.up.railway.app (Railway, `ap-southeast-1`)
- 저장소: https://github.com/hiorio/MAP-LINE (`main`)
- DB: Supabase `chouiphlafpxmglwriix` (**서울 `ap-northeast-2`**)
- 마이그레이션 0001~0009 적용 완료, 테스트 **177개** 통과

⚠️ **남은 미검증 항목은 하나뿐입니다 — 카카오톡 인앱 브라우저 실기기 테스트.**
공유 링크 대부분이 거기서 열리는데 pointer event 처리가 표준과 달라 드로잉이 깨질 수
있습니다. 배포가 끝났으므로 이제 실제로 확인 가능합니다. 아래 "다음 세션이 제일 먼저 할 일" 참고.

장기 계획은 [docs/ROADMAP.md](docs/ROADMAP.md), 배포는 [docs/DEPLOY.md](docs/DEPLOY.md),
마이그레이션은 [docs/MIGRATIONS.md](docs/MIGRATIONS.md).

## 실행

```bash
cd C:\MAP-LINE
npm install   # 이미 설치돼 있으면 생략
npm run dev
```

- 랜딩: http://localhost:3000
- 편집기: 랜딩의 "지도 만들기" 클릭 (슬러그 자동 생성) 또는 임의 슬러그로 `/edit/아무값`
- W0 프로토타입(참고용, 이제 안 건드려도 됨): http://localhost:3000/prototype/draw.html

**주의:** `npm run dev`가 떠 있는 상태에서 `npm run build`를 돌리면 `.next`가 깨져서 모든 페이지가 500을 냅니다(`Cannot find module './vendor-chunks/....js'`). 겪으면:
```bash
npx kill-port 3000 && rm -rf .next && npm run dev
```

## 환경 변수 현재 값 (`.env.local`)

| 변수 | 상태 | 비고 |
|---|---|---|
| `NEXT_PUBLIC_KAKAO_JS_KEY` | ✅ 채워짐 | 편집기 지도가 뜬다 |
| `KAKAO_REST_KEY` | ✅ 채워짐 | 장소 검색·공유텍스트 파싱 동작 확인 |
| `NEXT_PUBLIC_SUPABASE_URL` | ✅ 채워짐 | 서울 리전 프로젝트. **Railway에도 같은 값이 있어야 한다** |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | ⬜ 비어 있음 | 현재 코드에서 안 씀. 없어도 됨 |
| `SUPABASE_SERVICE_ROLE_KEY` | ✅ 채워짐 | 〃 |
| `NEXT_PUBLIC_SITE_URL` | ⬜ 로컬은 불필요 | **Railway에는 배포 주소가 들어가 있어야 OG 썸네일이 뜬다** |

`.env.local`은 `.gitignore`에 걸려 있어 커밋되지 않습니다. `.env.example`에 각 변수 설명이 있습니다.

## 사용자가 해줘야 하는 것 (코드로는 못 하는 일)

### A. Supabase — ✅ 완료

서울 리전(`ap-northeast-2`) 프로젝트에 마이그레이션 0001~0009가 적용돼 있고 서버 저장이
실제로 동작합니다. 뭄바이 리전에서 옮긴 뒤 통합 테스트가 23.2초 → 7.2초로 줄었습니다.

**환경 변수는 두 곳에 있습니다** — `.env.local`(로컬)과 Railway `Variables`(배포본).
Supabase 프로젝트를 바꾸면 양쪽 다 고쳐야 합니다. 코드에는 주소가 하드코딩된 곳이 없고
`lib/supabase/server.ts` 한 곳에서만 환경 변수를 읽습니다.

`NEXT_PUBLIC_SUPABASE_ANON_KEY`는 아직 비어 있는데, 현재 코드에서 쓰는 곳이 없어 문제없습니다.
뷰어(T13)가 브라우저에서 Supabase를 직접 읽게 만들 때만 필요합니다. 지금 설계에서는 뷰어도
Route Handler를 경유하면 되므로 끝까지 안 쓸 수도 있습니다.

### B. Kakao REST API 키 — ✅ 완료

`KAKAO_REST_KEY` 설정됨. 실제 카카오 응답으로 검색·공유텍스트 파싱 모두 동작 확인.

### C. 마이그레이션 — ✅ CLI로 자동화됨

새 마이그레이션이 생기면 **`npm run db:push`** 한 줄이면 됩니다. 절차와 주의사항은
[docs/MIGRATIONS.md](docs/MIGRATIONS.md)에 있습니다. 이 PC에는 로그인·연결이 끝나 있고,
새 PC에서만 `supabase login` → `npm run db:link`를 한 번 하면 됩니다.

| 파일 | 내용 |
|---|---|
| `0001_init.sql` | 테이블·인덱스·RLS 초기 정의 |
| `0002_document_rpc.sql` | 읽기/쓰기 RPC, 0001의 `edit_token` 노출 구멍 차단 |
| `0003_view_count.sql` | 조회수, `updated_at` 트리거를 조회수에 둔감하게 |
| `0004_og_cache.sql` | OG 썸네일 캐시 컬럼, 트리거 제외 목록에 OG 컬럼 추가 |
| `0005_api_usage.sql` | 카카오 API 사용량 집계 테이블 |
| `0006_upsert_save.sql` | 저장을 업서트로 전환, 클라이언트 id 보존 |
| `0007_stops.sql` | 단계·후보 모델(`places.stop_index`), `segments` 제거 |
| `0008_auto_line_toggles.sql` | 자동 선 표시 설정 두 개 |
| `0009_rate_limit.sql` | 요청 빈도 제한 집계 |

**마이그레이션은 두 번 돌려도 안전해야 합니다.** 도구가 재실행할 수 있게 된 이상
사람이 고르는 안전장치가 사라졌습니다. 특히 데이터 백필이 위험합니다 — `0007`의
`stop_index` 백필은 재실행하면 한 단계의 후보들을 쪼개 놓는 형태였고, 널 허용 컬럼으로
만든 뒤 널만 채우는 방식으로 고쳤습니다.

스키마를 바꾼 배포는 **`db:push` 먼저, 배포 나중**입니다. 순서가 바뀌면 새 코드가
아직 없는 컬럼을 찾습니다.

### D. 배포 — ✅ 완료

Railway에 올라가 있습니다: https://map-line-production.up.railway.app

절차와 함정(포트 불일치로 인한 502, Node 버전, `npm ci`와 빌드 캐시 충돌)은
[docs/DEPLOY.md](docs/DEPLOY.md)에 정리돼 있습니다.

**Railway `Variables`에 있어야 하는 값** — `.env.local`과 같되 `NEXT_PUBLIC_SITE_URL`이
배포 주소로 들어가 있어야 카카오톡 미리보기 썸네일이 뜹니다.

카카오 콘솔 > 앱 > 플랫폼 키 > JavaScript 키의 SDK 도메인에 배포 주소가 등록돼 있어야
지도 타일이 보입니다.

> 참고: 카카오 REST/네이티브 앱 키가 작업 중 대화 로그에 평문으로 남은 적이 있습니다.
> 사용자는 신경 쓰지 않기로 했으므로 그대로 진행하되, 공개 서비스로 갈 때 재발급하면 됩니다.

## 지금까지 만들어진 것

### 완료 — 코드·테스트 있고 실제 환경에서 확인됨

| 영역 | 파일 |
|---|---|
| RDP 단순화·좌표 투영·줌 보정 | `lib/geo/rdp.ts`, `lib/geo/projection.ts` |
| 카카오 SDK 로더·지도 | `lib/kakao/loadSdk.ts`, `components/map/KakaoMap.tsx` |
| 캔버스 오버레이 (손그림·핀·라벨·화살표) | `components/map/MapOverlay.tsx`, `components/map/useMapCanvas.ts`, `lib/render/scene.ts` |
| 편집기 상태·되돌리기 | `store/useMapStore.ts` |
| 단계·후보 모델 | `lib/map/types.ts`(`Stop`, `flattenStops`, `stopCentroid`), `0007` |
| 자동 선(후보 연결선·이동 화살표)과 끄기 | `lib/render/scene.ts`, `0008` |
| 라벨 수정·이동 | `components/map/MapOverlay.tsx` (탭=수정, 드래그=이동) |
| 장소 검색·거리순 정렬 | `lib/kakao/localSearch.ts`, `lib/kakao/searchParams.ts`, `app/api/search` |
| 공유 텍스트 파싱 | `lib/kakao/parseShareText.ts`, `app/api/parse-share` |
| 보관함(개인 장소 저장) | `lib/map/savedPlaces.ts`, `store/useSavedPlacesStore.ts` |
| 서버 저장·낙관적 잠금 | `app/api/maps/**`, `lib/map/persistence.ts`, `0002`/`0006` |
| 뷰어·공유 링크 | `app/m/[slug]/**`, `Editor.tsx`의 `ShareButton` |
| OG 썸네일 + Storage 캐시 | `app/api/og/[slug]`, `lib/map/ogImage.ts`, `lib/kakao/staticMap.ts`, `0004` |
| 썸네일에 핀·손그림·화살표·메모 합성 | `lib/render/ogOverlay.ts`, `lib/render/sceneGeometry.ts`, `lib/map/staticProjection.ts`, `nixpacks.toml` |
| 랜딩 | `app/page.tsx`, `components/DemoMap.tsx` |
| 사용량 집계·진단 | `lib/kakao/usage.ts`, `app/api/usage`, `0005` |
| 요청 빈도 제한 | `lib/rateLimit.ts`, `0009` |

**실제 환경 검증 요약**

| 확인 | 결과 |
|---|---|
| 서버 저장 왕복 | 제목·단계·후보 순서·좌표·설정 보존 (통합 테스트 26개) |
| 클라이언트 id 보존 | 여러 번 저장해도 불변, 교차 지도 id 탈취 차단 |
| 낙관적 잠금 | 오래된 `updatedAt` → 409 |
| `updated_at` 트리거 | 조회수·썸네일 기록에 반응하지 않음 |
| 배포본 전 기능 | 생성·저장·뷰어·OG(216KB)·삭제 모두 200 |
| 요청 빈도 제한 | 20건까지 통과, 21건째 429, 다른 IP는 영향 없음 |
| 서울 리전 이전 | 통합 테스트 23.2초 → 7.2초 |

`npm run typecheck` / `npm run lint` / `npm test`(**177개**) 전부 통과.
`npm run build`는 dev 서버를 끄고 돌려야 합니다(위 "실행" 주의사항).

### 미완료

- **카카오톡 인앱 브라우저 실기기 테스트** — 유일하게 남은 미검증 항목이자 제일 중요합니다.
  아래 "다음 세션이 제일 먼저 할 일" 참고
- **실제 경로 좌표** — 단계 사이 화살표가 직선입니다. `/api/route`로 실제 도보·대중교통
  경로를 받으면 `lib/render/scene.ts`의 `drawStopArrows`가 좌표 배열을 받도록 바꾸면 됩니다.
  단계마다 후보가 여럿이면 어느 후보 기준으로 경로를 뽑을지 정해야 합니다
- **신고 링크** — 빈도 제한은 넣었지만 신고 창구는 없습니다
- **v0.2 중간지점** — 손 안 댐. 알고리즘 설계는 [docs/ROADMAP.md](docs/ROADMAP.md)에 있습니다

## 다음 세션이 제일 먼저 할 일

**카카오톡 인앱 브라우저에서 실기기 테스트.** 기능은 다 됐고 배포도 끝났지만, 실제 사용
환경에서 한 번도 안 돌려봤습니다. 공유 링크 대부분이 카카오톡 안에서 열리는데 그 웹뷰의
pointer event 처리가 표준과 달라, 여기서 드로잉이 깨지면 제품이 성립하지 않습니다.

1. 폰 카카오톡에서 자신에게 https://map-line-production.up.railway.app 전송
2. 카톡 안에서 링크를 눌러 인앱 브라우저로 열기
3. 확인할 것:
   - 손가락으로 선이 그어지는가 (제일 중요)
   - 그리기 모드에서 지도가 안 움직이는가
   - 선이 흐리지 않은가 (레티나 DPR)
   - `📍 핀` / `T 라벨` 탭 시 입력창이 뜨고 **사라지지 않는가**
     (데스크톱에서 같은 증상을 겪고 고친 적이 있음 — 터치는 또 다른 경로)
   - 라벨 드래그로 이동이 되는가
   - 편집기에서 `공유` → 카톡 전송 → **미리보기에 지도 썸네일이 뜨는가**

깨지는 게 있으면 그 화면에서 무슨 일이 일어나는지부터 알려 주세요. 원격 디버깅이
어려우므로 증상 서술이 유일한 단서입니다.

### 아직 확인 안 된 것

- `0002`가 `0001`의 RLS 구멍을 막았는지 **직접 테스트는 못 했습니다.** 논리적으로는 확실합니다
  (0002가 통째로 성공했으므로 맨 위 `drop policy` 문들도 실행됐고, Supabase SQL Editor는
  스크립트를 한 트랜잭션으로 돌립니다). 확실히 하려면 Supabase 대시보드 > Authentication >
  Policies 에서 `maps`/`places`/`strokes`/`labels`/`segments`에 정책이 없는지 보면 됩니다.
  `NEXT_PUBLIC_SUPABASE_ANON_KEY`를 채운다면 anon으로 `select edit_token from maps`가
  거부되는지 쏴 보는 게 가장 확실합니다.

### 테스트 돌리는 법

```bash
npm test                                                  # 전체 177개
npx vitest run lib/map/mapDocument.integration.test.ts     # 스키마 건드린 뒤엔 이것부터
```

통합 테스트는 실제 Supabase에 `zztest`로 시작하는 지도를 만들고 `afterAll`에서 지웁니다.
환경 변수가 없으면 스스로 스킵합니다.

**통합 테스트를 새로 쓸 때 주의:** 지도마다 새 uuid를 쓰세요(`makeSample()`). 고정 id를 여러
테스트가 공유하면 두 번째 지도부터 교차 지도 방어에 걸려 행이 조용히 빠집니다. 실제로 겪었습니다.

작업 커밋은 의미 있는 단위로 나눠서 하세요. `.env.local`은 `.gitignore`에 걸려 있지만, 새 파일을 추가하기 전에 `git status`로 한 번 확인하는 습관을 들이면 안전합니다.

## 코드에 이미 반영된, 다시 겪지 않아도 될 문제들

작업 중 실제로 겪고 고친 것들입니다. README에도 있지만 여기 요약합니다 — 재작업 방지용.

- **카카오 지도 컨테이너에 `z-index: 0`이 없으면 그리기가 안 됩니다.** SDK가 컨테이너 안에 만드는 내부 레이어가 z-index를 갖고 있어서, 컨테이너가 `auto`면 그 자식이 드로잉 캔버스보다 위에 깔려 `pointerdown`이 캔버스에 안 닿습니다. `KakaoMap.tsx`에 `z-0`, 오버레이 캔버스에 `z-10`으로 이미 고정돼 있습니다.
- **합성 이벤트로 한 검증을 믿지 마세요.** `pointerdown`만 dispatch하면 뒤따르는
  `mouseup`이 없어서, 실제 마우스에서만 드러나는 경로를 통째로 건너뜁니다. 핀·라벨 입력창이
  뜨자마자 스스로 닫히던 버그를 그렇게 놓쳤습니다. 입력이 얽힌 기능은 `computer` 도구의
  진짜 클릭·드래그로 확인하세요.
- **한글 입력 확정 Enter를 제출로 받으면 안 됩니다.** 조합을 확정하는 Enter도 `keydown`으로
  들어와 마지막 글자가 빠진 채 저장됩니다. `e.nativeEvent.isComposing`으로 걸러냅니다.
  한국어 장소 이름을 치는 제품이라 치명적입니다.
- **오류를 삼키고 빈 결과를 200으로 돌려주지 마세요.** `/api/usage`가 그래서 "DB 죽음"과
  "사용량 0"을 구분 못 했고, 배포본이 삭제된 프로젝트를 보고 있는데도 정상으로 읽혔습니다.
  상태를 보러 오는 경로는 상태를 숨기면 안 됩니다.
- **환경 변수는 두 곳에 있습니다** — `.env.local`과 Railway `Variables`. 한쪽만 바꾸면
  로컬은 되는데 배포본만 깨지고, 원인이 눈에 안 띕니다.
- **`crypto.randomUUID()`를 직접 쓰면 안 됩니다.** 보안 컨텍스트에서만 존재해서 `http://192.168.x.x:3000`(실기기 테스트용 LAN 주소)에서 터집니다. `lib/id.ts`의 `createId()`를 씁니다 — 대체 경로에서도 uuid v4 형식을 지킵니다.
- **`@next/env`를 ESM 설정 파일에서 명명 import하면 조용히 실패합니다.** CommonJS 모듈이라 에러 없이 값만 안 들어옵니다. `vitest.config.ts`는 `.env.local`을 직접 읽습니다.
- **vitest의 `setupFiles`에서 `process.env`를 채워도 워커에 반영되지 않습니다.** 설정 파일에서 읽어 `test.env`로 넘겨야 합니다.
- **`confirm()`에 의존하면 안 됩니다.** 인앱 브라우저(카카오톡 등)나 대화상자 차단 상태에서 조용히 `false`를 반환해 버튼이 안 먹습니다. "전체 지우기"는 두 번 누르기 패턴으로 대체했습니다 (`components/toolbar/EditorToolbar.tsx`의 `ClearButton`).
- **되돌리기는 pop이 아니라 스냅샷입니다.** 설계안 원문은 "pop 방식"이라 했지만, 지우개가 중간 획/핀을 지울 수 있어서 단순 pop은 엉뚱한 걸 되살립니다. `useMapStore.ts`의 `commit()`이 매 변경 전 `{places, strokes, labels}` 스냅샷을 히스토리에 쌓습니다.
- **RDP는 위경도가 아니라 화면 좌표에서 합니다.** 고정 줌에서 화면↔위경도가 국소적으로 선형이라 결과가 사실상 같고, 오차 단위가 픽셀이라 튜닝이 직관적입니다. 대신 획마다 `zoomCreated`를 저장해 다른 줌에서 볼 때 `strokeRenderWidth`/`strokeRenderAlpha`(`lib/geo/projection.ts`)로 굵기·투명도를 보정합니다.
- **팬 중엔 캔버스를 통째로 `transform`으로 밀고, 줌 중엔 숨깁니다.** 획/핀 전부를 매 프레임 재투영하면 느립니다. `idle` 이벤트에서만 정확히 재계산합니다 (`MapOverlay.tsx`).
- **핀·연결선·라벨·손그림은 캔버스 하나에서 그립니다.** 설계안은 `PinLayer`/`SegmentLayer`를 별도 컴포넌트로 뒀지만, 레이어마다 캔버스를 나누면 팬/줌 동기화를 그 수만큼 반복해야 해서 하나로 합쳤습니다 (`lib/render/scene.ts`가 그리기 함수, `MapOverlay.tsx`가 입력 처리).
- **Kakao Local API는 `x`=경도, `y`=위도입니다.** 순서가 직관과 반대라 `lib/geo/projection.ts`의 `fromKakaoXY()` 한 곳에 가둬뒀습니다. 새로 카카오 응답을 다루는 코드를 쓸 때 직접 `{lat: y, lng: x}`를 쓰지 말고 이 함수를 거치세요.
- **`updated_at` 트리거는 "내용이 바뀐 시각"만 담아야 합니다.** 0001의 트리거는 update마다 무조건 `now()`로 덮었습니다. 그대로 두면 (a) 뷰어 조회로 `view_count`가 오를 때, (b) 썸네일 URL을 기록할 때도 `updated_at`이 밀립니다. (a)는 편집기의 낙관적 잠금이 실제 충돌도 아닌데 409를 뱉게 만들고, (b)는 `og_updated_at < updated_at`이 영원히 참이 되어 **썸네일 무한 재생성 = 카카오 쿼터 소진**을 일으킵니다. 0003·0004에서 `view_count`, `og_image_url`, `og_updated_at`을 제외하도록 고쳤습니다. **메타데이터 컬럼을 새로 추가하면 이 목록에도 넣으세요** (`0004_og_cache.sql`의 `ignored` 배열).
- **OG 이미지는 `og:image` URL이 절대 경로여야 크롤러가 읽습니다.** `app/layout.tsx`의 `metadataBase`가 `NEXT_PUBLIC_SITE_URL`로 그 기준을 잡습니다. 배포 시 이걸 안 바꾸면 썸네일이 localhost를 가리켜 카톡 미리보기가 비어 보입니다.
- **카카오 정적 지도의 `markers` 파라미터는 쓰면 안 됩니다.** 폴리라인 파라미터가 아예 없는 것도 문제지만, 더 나쁜 건 `markers`를 넘기면 카카오가 **`center`를 무시하고 마커에 맞춰 지도를 다시 잡는다**는 점입니다(마커 하나면 그 마커가 무조건 이미지 한가운데에 옵니다). 지도를 만든 사람이 맞춰 둔 화면이 통째로 어긋납니다. 그래서 지도는 표시 없이 받고 핀·화살표·손그림·메모를 전부 직접 합성합니다 — `lib/render/ogOverlay.ts`(SVG 생성) + `lib/map/ogImage.ts`(sharp 합성).
- **좌표 → 픽셀 대응은 실측해서 `lib/map/staticProjection.ts`에 넣어뒀습니다.** 카카오가 문서로 내놓지 않아 직접 쟀습니다. 성질이 중요한데, **메르카토르가 아닙니다**: 위도 1도당 픽셀 수가 위도와 무관하게 일정하고, 경도만 `cos(위도)`배로 좁아지는 등거리 투영입니다. 레벨이 1 오를 때마다 정확히 절반이 됩니다. 검증은 정적 지도의 `center`를 알려진 각도만큼 옮겼을 때 이미지가 실제로 몇 픽셀 밀리는지 대조했고, 레벨 1·2·3·5·7에서 240px 기준 오차 0px이었습니다. **요청한 레벨과 그린 레벨이 어긋나면 획이 통째로 엉뚱한 배율로 찍히므로 `clampLevel()`을 양쪽에서 같이 쓰세요.**
- **썸네일의 한글은 서버 글꼴에 달려 있습니다.** SVG 안에 가게 이름과 메모가 한글로 들어가는데 기본 빌드 이미지에는 CJK 글꼴이 없습니다. `nixpacks.toml`의 `fonts-noto-cjk`가 그걸 넣습니다. 이 줄이 빠지면 **핀과 선은 멀쩡한데 글자만 빈칸/두부로 나와서** 알아채기 어렵습니다.
- **0001의 RLS 정책에는 보안 구멍이 있었고 0002에서 막았습니다.** `create policy maps_read on maps for select using (true)`는 컬럼 단위가 아니라서 anon 키로 `select edit_token from maps`가 통했습니다. 즉 누구나 남의 지도를 편집할 수 있었습니다. `maps_public` 뷰로는 원본 테이블 직접 조회를 막지 못합니다. 0002에서 읽기 정책을 전부 없애 기본 거부로 만들고, `get_map_document`(security definer, edit_token 미반환)로만 읽기를 엽니다. **새 테이블에 읽기 정책을 추가할 때 같은 실수를 반복하지 마세요.**
- **저장은 지도 전체 스냅샷을 보내지만 DB에는 업서트로 반영됩니다** (0006). 클라이언트가 만든 uuid를 그대로 기본키로 쓰고, 페이로드에 없는 행만 지웁니다. 그래서 `lib/id.ts`의 `createId()`는 **어떤 환경에서도 유효한 uuid를 반환해야 합니다** — 형식이 깨지면 저장이 통째로 실패합니다. PostGIS ↔ `{lat,lng}` 변환은 RPC 안에서 끝나므로 클라이언트는 PostGIS를 모릅니다.
- **업서트에는 `where <table>.map_id = v_id` 가드가 붙어 있습니다.** 없으면 남의 지도 행 id를 일부러 보내 그 행을 자기 지도로 끌어올 수 있습니다. 이 가드 때문에 **테스트에서 여러 지도가 같은 id를 쓰면 행이 조용히 빠집니다** — 의도된 동작입니다.
- **이동수단은 `segments` 테이블이 아니라 `places.mode_to_next`에 있습니다.** 클라이언트의 유일한 근거가 "places 배열 순서 + 각 핀의 다음 구간 이동수단"이라 두 곳에 나누면 동기화 버그만 생깁니다. `segments` 테이블은 비어 있고, 설계안의 `style='manual'`(사용자가 그린 선으로 연결선 대체)과 실제 경로 좌표를 저장할 때 쓸 자리로 남겨 뒀습니다.
- **공유 텍스트 파싱은 단축 URL을 절대 풀지 않습니다.** `naver.me`/`kko.kr`을 서버에서 리졸브하는 건 타사 약관 회색지대입니다. 대신 URL을 버리고 이름/주소만 뽑아 Kakao Local에 재검색합니다 (`lib/kakao/parseShareText.ts` + `app/api/parse-share/route.ts`).
- **`extractDistrict`는 시/도 접두를 먼저 걷어냅니다.** 안 그러면 "서울특별시"의 '시'를 구·군으로 오인합니다.
- **`next lint`는 안 씁니다.** Next 16에서 제거 예정이고 대화형 프롬프트를 띄워서 `eslint.config.mjs` + `eslint .`로 바꿨습니다.
- **dev 서버가 떠 있을 때 `npm run build`를 돌리면 안 됩니다.** 같은 `.next`를 공유해서 vendor-chunk가 깨집니다.

## 참고

- 설계 원본(§ 번호로 인용되는 문서)은 이 대화의 앞부분에만 있고 프로젝트 파일로는 저장돼 있지 않습니다. 이 저장소는 원래 사용자의 다른 프로젝트(`link-reminder`, 링크 저장 앱)와 융합하지 않고 별도로 새로 만든 것입니다 — 두 프로젝트는 완전히 무관합니다.
- 작업 방식: T1~T15는 설계안 §12.4의 작업 분해 번호를 그대로 따르고 있습니다. 이 문서와 README의 T번호가 그 원문 번호입니다.
