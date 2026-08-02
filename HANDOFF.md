# HANDOFF — MAP-LINE

마지막 갱신: 2026-08-02 (이 문서를 갱신한 세션이 끝나는 시점)

다른 AI 세션이 이 문서 하나만 읽고 바로 이어서 작업할 수 있도록 쓴 인수인계 문서입니다.
설계 배경과 근거는 [README.md](README.md)에 있으니 "왜 이렇게 했는가"가 궁금하면 거기를 봅니다.
이 문서는 "지금 뭐가 되고, 뭐가 안 되고, 다음에 뭘 하면 되는가"만 다룹니다.

## 지금 상태를 한 줄로

**v0.1 기능이 전부 구현·검증됐습니다.** 만들기 → 공유 링크 → 상대가 열어봄까지, OG 썸네일 포함해서 실제로 동작합니다. 마이그레이션 0001~0004 모두 적용됨.

**남은 것은 기능이 아니라 마감입니다** — 실기기 테스트, 랜딩 페이지, 배포, 사용량 모니터링.
장기 계획은 [docs/ROADMAP.md](docs/ROADMAP.md) 참고.

⚠️ **가장 큰 미검증 리스크: 카카오톡 인앱 브라우저.** 공유 링크 대부분이 거기서 열리는데
pointer event 처리가 표준과 달라 드로잉이 깨질 수 있습니다. 아직 한 번도 실기기에서 확인 안 했습니다.

저장소: https://github.com/hiorio/MAP-LINE (초기 커밋 `a84aed8` push 완료, `main` 브랜치)

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
| `NEXT_PUBLIC_SUPABASE_URL` | ✅ 채워짐 | 서버 저장 동작 확인됨 |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | ⬜ 비어 있음 | 현재 코드에서 안 씀. 없어도 됨 |
| `SUPABASE_SERVICE_ROLE_KEY` | ✅ 채워짐 | 〃 |

`.env.local`은 `.gitignore`에 걸려 있어 커밋되지 않습니다. `.env.example`에 각 변수 설명이 있습니다.

## 사용자가 해줘야 하는 것 (코드로는 못 하는 일)

### A. Supabase — ✅ 완료

프로젝트 생성, 0001·0002 마이그레이션 적용, `.env.local`의 `NEXT_PUBLIC_SUPABASE_URL`과
`SUPABASE_SERVICE_ROLE_KEY` 설정까지 끝났고 서버 저장이 실제로 동작합니다.

`NEXT_PUBLIC_SUPABASE_ANON_KEY`는 아직 비어 있는데, 현재 코드에서 쓰는 곳이 없어 문제없습니다.
뷰어(T13)가 브라우저에서 Supabase를 직접 읽게 만들 때만 필요합니다. 지금 설계에서는 뷰어도
Route Handler를 경유하면 되므로 끝까지 안 쓸 수도 있습니다.

### B. Kakao REST API 키 — ✅ 완료

`KAKAO_REST_KEY` 설정됨. 실제 카카오 응답으로 검색·공유텍스트 파싱 모두 동작 확인.

### C. 마이그레이션 0001~0004 — ✅ 전부 적용 완료

새 마이그레이션을 추가하면 사용자에게 SQL Editor 실행을 안내해야 합니다.
`supabase` CLI를 연결하지 않았으므로 자동 적용되지 않습니다.

### D. 배포할 때 (아직 안 함)

- Vercel 프로젝트 연결, 환경 변수 5개 등록 (`.env.local`과 동일 + `NEXT_PUBLIC_SITE_URL`)
- **`NEXT_PUBLIC_SITE_URL`을 운영 도메인으로 설정** — OG 이미지가 절대 URL이어야 카카오톡이
  미리보기를 읽습니다. 안 하면 localhost를 가리켜 썸네일이 안 뜹니다
- 카카오 콘솔 > 앱 > 플랫폼 키 > JavaScript 키의 SDK 도메인에 운영 도메인 추가
- 애드센스를 붙이는 시점에는 Vercel Pro(월 $20)가 필요합니다 — Hobby는 상업적 사용 불가

> 참고: 카카오 REST/네이티브 앱 키가 작업 중 대화 로그에 평문으로 남은 적이 있습니다.
> 사용자는 신경 쓰지 않기로 했으므로 그대로 진행하되, 나중에 서비스를 공개할 때
> 콘솔에서 키를 재발급하면 됩니다. `.env.local`은 `.gitignore`에 걸려 있어 저장소에는
> 올라가지 않습니다.

## 지금까지 만들어진 것

### 완료 — 코드 있음, 테스트 있음, 로컬에서 동작 확인됨

| 영역 | 파일 | 확인 방법 |
|---|---|---|
| W0 드로잉 프로토타입 (참고용, 값 확정 완료) | `public/prototype/draw.html` | 이미 검증 끝. 더 안 건드려도 됨 |
| RDP 단순화·좌표 투영·줌 보정 | `lib/geo/rdp.ts`, `lib/geo/projection.ts` | `npm test` |
| 카카오 SDK 로더 | `lib/kakao/loadSdk.ts` | 실제 지도 뜨는 것으로 확인 |
| 지도 컴포넌트 | `components/map/KakaoMap.tsx` | 〃 |
| 드로잉+핀+연결선+라벨 통합 오버레이 | `components/map/MapOverlay.tsx`, `lib/render/scene.ts` | ✅ 실제 카카오 지도 위에서 검증 완료: 핀 3개 찍기(번호·이름), 순서 변경(▲▼, 지도 번호도 즉시 반영), 이동수단 변경(연결선 스타일 즉시 반영 — 도보=회색 점선, 대중교통=파란 굵은 점선), 지우개로 핀 삭제 시 연결선도 함께 제거, 새로고침 후 전부 복원 |
| 편집기 상태(Zustand) | `store/useMapStore.ts` | `npm test` (18개 테스트, 되돌리기·순서변경·전체지우기 포함) |
| 공유 텍스트 파서 | `lib/kakao/parseShareText.ts` | `npm test` (12개), 브라우저에서 API 경유 확인 |
| Kakao Local 검색 래퍼 | `lib/kakao/localSearch.ts` | `npm test` (6개, x/y↔lat/lng 매핑 포함) |
| `/api/search`, `/api/parse-share` | `app/api/search/route.ts`, `app/api/parse-share/route.ts` | ✅ 실제 카카오 응답 확인 ("강남역" → 5건, 네이버 공유텍스트 → 파싱 후 후보 검색) |
| T13 뷰어 `/m/[slug]` | `app/m/[slug]/page.tsx`, `app/m/[slug]/Viewer.tsx` | ✅ SSR 메타(제목·OG 경로 요약), 읽기 전용 캔버스, 장소 스트립 탭 이동, 토큰 있으면 "편집하기" 노출·없으면 숨김, 없는 슬러그 404 |
| 캔버스 공용 훅 | `components/map/useMapCanvas.ts` | 편집기와 뷰어가 같은 `drawScene`을 쓰도록 추출. 리팩터 후 편집기 재검증 완료 |
| F7 공유 버튼 | `app/edit/[slug]/Editor.tsx`의 `ShareButton` | ✅ 서버 저장 모드에서만 활성화. `navigator.share` 우선, 없으면 클립보드 복사 |
| T14 OG 썸네일 | `app/api/og/[slug]/route.ts`, `lib/map/ogImage.ts`, `lib/kakao/staticMap.ts` | ✅ 실제 생성 확인 (홍대 지도 + 핀 3개, 254KB PNG), Storage 캐시·재사용·내용 변경 시 재생성·`updated_at` 불변까지 검증 |
| T12 서버 저장 API + 스키마 | `app/api/maps/route.ts`, `app/api/maps/[slug]/route.ts`, `lib/supabase/server.ts`, `supabase/migrations/0002_document_rpc.sql` | ✅ 실제 Supabase에 대해 검증 완료 — 아래 상세 |
| 서버/로컬 저장 자동 전환 | `lib/map/persistence.ts` | ✅ 양방향 확인. Supabase 미설정 시 "이 기기에만 저장됨"으로 폴백, 설정 시 "저장됨" |
| 편집기 화면·툴바·장소 패널 | `app/edit/[slug]/Editor.tsx`, `components/toolbar/EditorToolbar.tsx`, `components/panels/PlacePanel.tsx` | 렌더 확인, 그리기/라벨 흐름 확인 |
| 로컬 초안 저장 (§6.1 구조, debounce 2s + 강제 flush 10s + 이탈 시 flush) | `lib/map/draftStorage.ts` | 브라우저에서 새로고침 후 복원 확인 |
| Supabase 스키마 (아직 미적용) | `supabase/migrations/0001_init.sql`, `0002_document_rpc.sql` | 파일만 있음. **프로젝트에 적용 안 됨 = SQL이 실제로 도는지 아직 검증 안 됨** |
| 랜딩 + 지도 생성 | `app/page.tsx`, `components/CreateMapButton.tsx`, `lib/slug.ts` | 렌더 확인. 서버 있으면 POST /api/maps, 없으면 로컬 슬러그 |

**T12 서버 저장 검증 내역** (실제 Supabase 대상, 전부 통과):

| 확인 | 결과 |
|---|---|
| `POST /api/maps` | 201, 슬러그·편집토큰 발급, `maps` 행 생성 |
| PATCH → GET 왕복 | 제목·핀 2개·손그림(3점)·라벨 한글 그대로, 좌표 정확, `modeToNext`·`kakaoPlaceId` 보존 |
| 핀 순서 | `order_no`로 저장·복원되어 배열 순서 유지 |
| 잘못된 편집 토큰 | 403 |
| 낙관적 잠금 | 오래된 `updatedAt` → 409, 최신 → 200 |
| `DELETE` | 200, 이후 GET 404 (자식 행 cascade 삭제) |
| 편집기 실제 흐름 | 지도 생성 → 토큰 저장 → 핀·손그림 입력 → "저장됨" 표시 |
| **로컬 초안 삭제 후 새로고침** | 제목·핀·연결선·손그림이 전부 복원 — 출처가 서버뿐임을 증명 |

`npm run typecheck` / `npm run lint` / `npm test`(59개) 전부 통과 상태입니다. `npm run build`는 dev 서버가 떠 있어 재실행하지 않았습니다 — 필요하면 dev 서버를 끄고 따로 실행하세요.

### 미완료

기능 목록과 우선순위는 [docs/ROADMAP.md](docs/ROADMAP.md)에 정리돼 있습니다. 요약하면:

- **실기기 테스트 (최우선)** — 특히 카카오톡 인앱 브라우저. 미검증
- **랜딩 페이지** — 지금은 개발 안내문 수준. 설계안 §7.1의 "데모 지도 + CTA 단일 버튼"으로
- **배포** — Vercel, 운영 도메인. 위 "D" 참고
- **사용량 모니터링** — 카카오 쿼터 80% 알림. 지금은 소진돼도 모릅니다
- **썸네일에 손그림** — 카카오 정적 지도 API에 폴리라인 파라미터가 없습니다. 받은 이미지 위에
  직접 합성하려면 카카오의 레벨 → 미터/픽셀 대응을 정확히 알아야 하는데 틀리면 획이 엉뚱한
  곳에 찍힙니다. 지도+핀만으로도 미리보기 목적은 달성한다고 판단해 미뤘습니다
- **T11 후반** — 연결선이 직선입니다. `/api/route`로 실제 경로 좌표를 받으면
  `lib/render/scene.ts`의 `drawSegments`가 좌표 배열을 받도록만 바꾸면 됩니다
- **v0.2 중간지점** — 손 안 댐. 알고리즘 설계는 ROADMAP에 있습니다

## 다음 세션이 제일 먼저 할 일

**1. 실기기 테스트가 최우선입니다.** 기능은 다 됐지만 실제 사용 환경에서 한 번도 안 돌려봤습니다.

- 폰을 개발 PC와 같은 Wi-Fi에 연결하고 `http://192.168.x.x:3000` 접속 (dev 서버 시작 시 출력되는 Network 주소)
- 카카오 콘솔 > 앱 > 플랫폼 키 > JavaScript 키의 SDK 도메인에 그 주소가 등록돼 있어야 합니다
- 확인할 것:
  - 손가락으로 그리기가 되는가 (pointer event 처리)
  - 그리기 모드에서 지도가 안 움직이는가
  - 선이 흐리지 않은가 (DPR)
  - **편집기에서 공유 → 카톡으로 링크 전송 → 카톡 안에서 열기.** 이게 실제 사용 경로입니다
  - 카톡 미리보기에 썸네일이 뜨는가 (배포 후에만 가능 — localhost는 카톡 크롤러가 못 읽습니다)

**2. 랜딩 페이지** — 지금은 개발 안내문입니다. 설계안 §7.1대로 데모 지도 + CTA 단일 버튼으로.
방금 만든 뷰어를 임베드하거나 스크린샷을 쓰면 됩니다.

**3. 배포** — 위 "D" 참고. 배포해야 카톡 미리보기를 실제로 검증할 수 있습니다.

**4. 사용량 모니터링** — 설계안 §10. 카카오 쿼터 80% 알림. 지금은 소진돼도 모릅니다.

### 아직 확인 안 된 것 하나

`0002`가 `0001`의 RLS 구멍을 막았는지는 **논리적으로는 확실하지만 직접 테스트는 못 했습니다.**
(0002가 통째로 성공했으므로 맨 위 `drop policy` 문들도 실행됐습니다. Supabase SQL Editor는
스크립트를 한 트랜잭션으로 돌립니다.) 확실히 하려면 Supabase 대시보드
> Authentication > Policies 에서 `maps` / `places` / `strokes` / `labels` / `segments` 에
정책이 하나도 없는지 눈으로 확인하면 됩니다. anon 키를 채운다면 `select edit_token from maps`가
거부되는지 직접 쏴 보는 게 가장 확실합니다.

작업 커밋은 의미 있는 단위로 나눠서 하세요. `.env.local`은 `.gitignore`에 걸려 있지만, 새 파일을 추가하기 전에 `git status`로 한 번 확인하는 습관을 들이면 안전합니다.

## 코드에 이미 반영된, 다시 겪지 않아도 될 문제들

작업 중 실제로 겪고 고친 것들입니다. README에도 있지만 여기 요약합니다 — 재작업 방지용.

- **카카오 지도 컨테이너에 `z-index: 0`이 없으면 그리기가 안 됩니다.** SDK가 컨테이너 안에 만드는 내부 레이어가 z-index를 갖고 있어서, 컨테이너가 `auto`면 그 자식이 드로잉 캔버스보다 위에 깔려 `pointerdown`이 캔버스에 안 닿습니다. `KakaoMap.tsx`에 `z-0`, 오버레이 캔버스에 `z-10`으로 이미 고정돼 있습니다.
- **`crypto.randomUUID()`를 직접 쓰면 안 됩니다.** 보안 컨텍스트에서만 존재해서 `http://192.168.x.x:3000`(실기기 테스트용 LAN 주소)에서 터집니다. `lib/id.ts`의 `createId()`를 씁니다.
- **`confirm()`에 의존하면 안 됩니다.** 인앱 브라우저(카카오톡 등)나 대화상자 차단 상태에서 조용히 `false`를 반환해 버튼이 안 먹습니다. "전체 지우기"는 두 번 누르기 패턴으로 대체했습니다 (`components/toolbar/EditorToolbar.tsx`의 `ClearButton`).
- **되돌리기는 pop이 아니라 스냅샷입니다.** 설계안 원문은 "pop 방식"이라 했지만, 지우개가 중간 획/핀을 지울 수 있어서 단순 pop은 엉뚱한 걸 되살립니다. `useMapStore.ts`의 `commit()`이 매 변경 전 `{places, strokes, labels}` 스냅샷을 히스토리에 쌓습니다.
- **RDP는 위경도가 아니라 화면 좌표에서 합니다.** 고정 줌에서 화면↔위경도가 국소적으로 선형이라 결과가 사실상 같고, 오차 단위가 픽셀이라 튜닝이 직관적입니다. 대신 획마다 `zoomCreated`를 저장해 다른 줌에서 볼 때 `strokeRenderWidth`/`strokeRenderAlpha`(`lib/geo/projection.ts`)로 굵기·투명도를 보정합니다.
- **팬 중엔 캔버스를 통째로 `transform`으로 밀고, 줌 중엔 숨깁니다.** 획/핀 전부를 매 프레임 재투영하면 느립니다. `idle` 이벤트에서만 정확히 재계산합니다 (`MapOverlay.tsx`).
- **핀·연결선·라벨·손그림은 캔버스 하나에서 그립니다.** 설계안은 `PinLayer`/`SegmentLayer`를 별도 컴포넌트로 뒀지만, 레이어마다 캔버스를 나누면 팬/줌 동기화를 그 수만큼 반복해야 해서 하나로 합쳤습니다 (`lib/render/scene.ts`가 그리기 함수, `MapOverlay.tsx`가 입력 처리).
- **Kakao Local API는 `x`=경도, `y`=위도입니다.** 순서가 직관과 반대라 `lib/geo/projection.ts`의 `fromKakaoXY()` 한 곳에 가둬뒀습니다. 새로 카카오 응답을 다루는 코드를 쓸 때 직접 `{lat: y, lng: x}`를 쓰지 말고 이 함수를 거치세요.
- **`updated_at` 트리거는 "내용이 바뀐 시각"만 담아야 합니다.** 0001의 트리거는 update마다 무조건 `now()`로 덮었습니다. 그대로 두면 (a) 뷰어 조회로 `view_count`가 오를 때, (b) 썸네일 URL을 기록할 때도 `updated_at`이 밀립니다. (a)는 편집기의 낙관적 잠금이 실제 충돌도 아닌데 409를 뱉게 만들고, (b)는 `og_updated_at < updated_at`이 영원히 참이 되어 **썸네일 무한 재생성 = 카카오 쿼터 소진**을 일으킵니다. 0003·0004에서 `view_count`, `og_image_url`, `og_updated_at`을 제외하도록 고쳤습니다. **메타데이터 컬럼을 새로 추가하면 이 목록에도 넣으세요** (`0004_og_cache.sql`의 `ignored` 배열).
- **OG 이미지는 `og:image` URL이 절대 경로여야 크롤러가 읽습니다.** `app/layout.tsx`의 `metadataBase`가 `NEXT_PUBLIC_SITE_URL`로 그 기준을 잡습니다. 배포 시 이걸 안 바꾸면 썸네일이 localhost를 가리켜 카톡 미리보기가 비어 보입니다.
- **카카오 정적 지도 API에는 경로/폴리라인 파라미터가 없습니다.** 마커만 최대 5개입니다. 손그림을 썸네일에 넣으려면 직접 합성해야 합니다.
- **0001의 RLS 정책에는 보안 구멍이 있었고 0002에서 막았습니다.** `create policy maps_read on maps for select using (true)`는 컬럼 단위가 아니라서 anon 키로 `select edit_token from maps`가 통했습니다. 즉 누구나 남의 지도를 편집할 수 있었습니다. `maps_public` 뷰로는 원본 테이블 직접 조회를 막지 못합니다. 0002에서 읽기 정책을 전부 없애 기본 거부로 만들고, `get_map_document`(security definer, edit_token 미반환)로만 읽기를 엽니다. **새 테이블에 읽기 정책을 추가할 때 같은 실수를 반복하지 마세요.**
- **저장은 변경분이 아니라 지도 전체 스냅샷 교체입니다.** `save_map_document`가 자식 행을 지우고 다시 넣습니다. 한 트랜잭션이어야 해서 RPC로 만들었습니다. PostGIS ↔ `{lat,lng}` 변환도 이 함수 안에서 끝나므로 클라이언트는 PostGIS를 모릅니다.
- **이동수단은 `segments` 테이블이 아니라 `places.mode_to_next`에 있습니다.** 클라이언트의 유일한 근거가 "places 배열 순서 + 각 핀의 다음 구간 이동수단"이라 두 곳에 나누면 동기화 버그만 생깁니다. `segments` 테이블은 비어 있고, 설계안의 `style='manual'`(사용자가 그린 선으로 연결선 대체)과 실제 경로 좌표를 저장할 때 쓸 자리로 남겨 뒀습니다.
- **공유 텍스트 파싱은 단축 URL을 절대 풀지 않습니다.** `naver.me`/`kko.kr`을 서버에서 리졸브하는 건 타사 약관 회색지대입니다. 대신 URL을 버리고 이름/주소만 뽑아 Kakao Local에 재검색합니다 (`lib/kakao/parseShareText.ts` + `app/api/parse-share/route.ts`).
- **`extractDistrict`는 시/도 접두를 먼저 걷어냅니다.** 안 그러면 "서울특별시"의 '시'를 구·군으로 오인합니다.
- **`next lint`는 안 씁니다.** Next 16에서 제거 예정이고 대화형 프롬프트를 띄워서 `eslint.config.mjs` + `eslint .`로 바꿨습니다.
- **dev 서버가 떠 있을 때 `npm run build`를 돌리면 안 됩니다.** 같은 `.next`를 공유해서 vendor-chunk가 깨집니다.

## 참고

- 설계 원본(§ 번호로 인용되는 문서)은 이 대화의 앞부분에만 있고 프로젝트 파일로는 저장돼 있지 않습니다. 이 저장소는 원래 사용자의 다른 프로젝트(`link-reminder`, 링크 저장 앱)와 융합하지 않고 별도로 새로 만든 것입니다 — 두 프로젝트는 완전히 무관합니다.
- 작업 방식: T1~T15는 설계안 §12.4의 작업 분해 번호를 그대로 따르고 있습니다. 이 문서와 README의 T번호가 그 원문 번호입니다.
