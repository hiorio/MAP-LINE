# HANDOFF — MAP-LINE

마지막 갱신: 2026-08-02 (이 문서를 갱신한 세션이 끝나는 시점)

다른 AI 세션이 이 문서 하나만 읽고 바로 이어서 작업할 수 있도록 쓴 인수인계 문서입니다.
설계 배경과 근거는 [README.md](README.md)에 있으니 "왜 이렇게 했는가"가 궁금하면 거기를 봅니다.
이 문서는 "지금 뭐가 되고, 뭐가 안 되고, 다음에 뭘 하면 되는가"만 다룹니다.

## 지금 상태를 한 줄로

**편집기의 드로잉·라벨·핀·순서·검색 API까지 코드는 다 있고 로컬에서 검증됐지만, 저장은 로컬뿐이고 서버(Supabase)는 아직 하나도 없습니다.** 뷰어·공유 링크는 없습니다. git 저장소도 아직 안 만들었습니다.

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
| `NEXT_PUBLIC_KAKAO_JS_KEY` | ✅ 채워짐 | 편집기 지도가 이미 뜬다 |
| `KAKAO_REST_KEY` | ❌ 비어 있음 | **아래 "먼저 할 일" 참고 — 교체 필요** |
| `NEXT_PUBLIC_SUPABASE_URL` | ❌ 비어 있음 | Supabase 프로젝트 자체가 없음 |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | ❌ 비어 있음 | 〃 |
| `SUPABASE_SERVICE_ROLE_KEY` | ❌ 비어 있음 | 〃 |

`.env.local`은 `.gitignore`에 걸려 있어 커밋되지 않습니다. `.env.example`에 각 변수 설명이 있습니다.

## ⚠️ 먼저 처리해야 할 것 — REST API 키 교체

작업 중 사용자가 스크린샷을 통해 카카오 콘솔의 **REST API 키와 네이티브 앱 키를 실수로 노출**했습니다(대화 로그에 평문으로 남음). REST 키는 그 자체가 인증 수단이라 알면 바로 쓸 수 있고, 사용량은 콘솔 소유자의 비즈월렛에서 나갑니다.

**아직 REST 키를 발급/등록하지 않았으므로 지금은 피해가 없습니다.** 하지만 T8(장소 검색) 작업을 시작하기 전에 사용자에게 다음을 확인하세요:

1. 카카오 콘솔 > 앱 > 플랫폼 키 > REST API 키에서 **새 키를 추가로 발급**하고 대표로 지정
2. 노출됐던 기존 키를 삭제
3. 새 키를 `.env.local`의 `KAKAO_REST_KEY`에 넣기

이 절차 없이 기존(노출된) 키를 그대로 쓰지 마세요.

## 지금까지 만들어진 것

### 완료 — 코드 있음, 테스트 있음, 로컬에서 동작 확인됨

| 영역 | 파일 | 확인 방법 |
|---|---|---|
| W0 드로잉 프로토타입 (참고용, 값 확정 완료) | `public/prototype/draw.html` | 이미 검증 끝. 더 안 건드려도 됨 |
| RDP 단순화·좌표 투영·줌 보정 | `lib/geo/rdp.ts`, `lib/geo/projection.ts` | `npm test` |
| 카카오 SDK 로더 | `lib/kakao/loadSdk.ts` | 실제 지도 뜨는 것으로 확인 |
| 지도 컴포넌트 | `components/map/KakaoMap.tsx` | 〃 |
| 드로잉+핀+연결선+라벨 통합 오버레이 | `components/map/MapOverlay.tsx`, `lib/render/scene.ts` | 브라우저에서 손그림·라벨 동작 확인. **핀·연결선은 코드 작성 후 실제 지도 위에서 미검증** (아래 "다음 세션이 제일 먼저 할 일" 참고) |
| 편집기 상태(Zustand) | `store/useMapStore.ts` | `npm test` (18개 테스트, 되돌리기·순서변경·전체지우기 포함) |
| 공유 텍스트 파서 | `lib/kakao/parseShareText.ts` | `npm test` (12개), 브라우저에서 API 경유 확인 |
| Kakao Local 검색 래퍼 | `lib/kakao/localSearch.ts` | `npm test` (6개, x/y↔lat/lng 매핑 포함) |
| `/api/search`, `/api/parse-share` | `app/api/search/route.ts`, `app/api/parse-share/route.ts` | curl/브라우저 fetch로 확인. **REST 키가 없어서 실제 카카오 응답은 아직 못 봄** (503만 확인됨) |
| 편집기 화면·툴바·장소 패널 | `app/edit/[slug]/Editor.tsx`, `components/toolbar/EditorToolbar.tsx`, `components/panels/PlacePanel.tsx` | 렌더 확인, 그리기/라벨 흐름 확인 |
| 로컬 자동 저장 (§6.1 구조, debounce 2s + 강제 flush 10s + 이탈 시 flush) | `lib/map/draftStorage.ts` | 브라우저에서 새로고침 후 복원 확인 |
| Supabase DDL (아직 미적용) | `supabase/migrations/0001_init.sql` | 파일만 있음, 프로젝트에 적용 안 됨 |
| 랜딩 + 슬러그 생성 | `app/page.tsx`, `components/CreateMapButton.tsx`, `lib/slug.ts` | 렌더 확인 |

`npm run typecheck` / `npm run lint` / `npm test`(59개) 전부 통과 상태입니다. `npm run build`는 이 문서 작성 시점 기준 dev 서버가 떠 있어 재실행하지 않았습니다 — 필요하면 dev 서버를 끄고 따로 실행하세요.

### 미완료 — 코드 없음

- **T11 후반**: 연결선은 지금 핀 사이 직선(점선/실선 스타일만 구분)입니다. `/api/route`로 실제 도보/대중교통 경로를 받아오는 부분은 없습니다.
- **T12 서버 저장**: `PATCH /api/maps/[slug]` 라우트 자체가 없습니다. 지금은 `lib/map/draftStorage.ts`가 `localStorage`에만 씁니다. 함수 시그니처와 debounce 구조는 서버 저장을 그대로 끼울 수 있게 맞춰 뒀습니다.
- **T13 뷰어**: `/m/[slug]` 페이지 없음.
- **T14 OG 썸네일**: `/api/og/[slug]` 없음.
- **F7 공유 링크**: 편집기 상단바의 "공유" 버튼은 `disabled`로 박혀 있습니다. T12+T13 이후에 활성화하면 됩니다.
- **익명 재편집 토큰(F8)**: DDL에는 `edit_token` 컬럼이 있지만 발급/검증 로직 없음.
- **v0.2 중간지점**: 손 안 댐.
- **git 저장소**: 아직 `git init`도 안 했습니다. 커밋 이력이 없습니다.

## 다음 세션이 제일 먼저 할 일

작업이 중단된 시점에 하려던 것: **핀·연결선이 실제 카카오 지도 위에서 정상 렌더링되는지 브라우저로 검증**하는 중이었습니다(자동화 스크립트로 핀 3개를 찍고 캔버스에 그려지는지, `localStorage` 초안에 순서·이동수단이 맞게 저장되는지 확인하려던 것). 이 확인이 끝나지 않은 상태입니다.

권장 순서:

1. **핀/연결선 시각 검증부터 마무리하세요.** `npm run dev` 후 브라우저에서 편집기를 열고:
   - `📍 핀` 모드로 지도를 3곳 탭 → 이름 입력 → 3개 핀이 번호(①②③)와 함께 그려지는지
   - 핀 사이에 이동수단별 스타일(도보=점선, 자동차=실선, 대중교통=굵은 파란 점선)로 연결선이 그려지는지 — `lib/render/scene.ts`의 `SEGMENT_STYLE`
   - `PlacePanel`의 장소 목록에서 ▲▼로 순서를 바꾸면 지도 위 번호와 연결선도 같이 바뀌는지
   - 지우개로 핀을 지우면 연결선도 같이 사라지는지
   - 새로고침 후 핀·순서·이동수단이 복원되는지
   - 문제 있으면 `components/map/MapOverlay.tsx`의 `eraseAt`(라벨→핀→획 순서로 히트테스트)과 `lib/render/scene.ts`의 `drawScene`(연결선→획→핀→라벨 순으로 그림)을 먼저 보세요.

2. **REST 키 교체를 사용자에게 확인**하세요 (위 "먼저 처리해야 할 것" 참고). 교체된 키를 `.env.local`에 넣게 한 뒤 `/api/search`, `/api/parse-share`가 실제 카카오 응답을 정상적으로 돌려주는지 확인합니다.

3. 그다음 T12(서버 저장)로 넘어가면 됩니다. Supabase 프로젝트가 아직 없으니:
   - Supabase 프로젝트 생성
   - `supabase/migrations/0001_init.sql`을 SQL Editor에 적용 (PostGIS, RLS, `maps_public` 뷰 포함 — 뷰를 만든 이유는 파일 안 주석 참고. `edit_token`을 공개 읽기에서 빼기 위함)
   - `.env.local`의 Supabase 3개 변수 채우기
   - `lib/supabase/` 클라이언트 래퍼 작성 (서버 전용 service role 클라이언트와, 필요하면 클라이언트용 anon 클라이언트를 분리)
   - `app/api/maps/route.ts` (POST, 슬러그+edit_token 발급)
   - `app/api/maps/[slug]/route.ts` (GET/PATCH/DELETE, `X-Edit-Token` 헤더 검증, `updated_at` 기반 낙관적 잠금)
   - `Editor.tsx`의 `useAutosave` 안 `saveDraft` 호출을 위 PATCH 호출로 교체 (debounce/flush 구조는 이미 그 형태로 맞춰둠 — 함수 내용만 바꾸면 됨)

4. T13 뷰어(`/m/[slug]`), T14 OG 썸네일, F7 공유 링크 활성화는 T12 이후 순서대로.

5. **git 저장소가 아직 없습니다.** 적당한 시점에 `git init` + 최초 커밋을 사용자와 상의하세요. `.gitignore`는 이미 있습니다.

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
- **공유 텍스트 파싱은 단축 URL을 절대 풀지 않습니다.** `naver.me`/`kko.kr`을 서버에서 리졸브하는 건 타사 약관 회색지대입니다. 대신 URL을 버리고 이름/주소만 뽑아 Kakao Local에 재검색합니다 (`lib/kakao/parseShareText.ts` + `app/api/parse-share/route.ts`).
- **`extractDistrict`는 시/도 접두를 먼저 걷어냅니다.** 안 그러면 "서울특별시"의 '시'를 구·군으로 오인합니다.
- **`next lint`는 안 씁니다.** Next 16에서 제거 예정이고 대화형 프롬프트를 띄워서 `eslint.config.mjs` + `eslint .`로 바꿨습니다.
- **dev 서버가 떠 있을 때 `npm run build`를 돌리면 안 됩니다.** 같은 `.next`를 공유해서 vendor-chunk가 깨집니다.

## 참고

- 설계 원본(§ 번호로 인용되는 문서)은 이 대화의 앞부분에만 있고 프로젝트 파일로는 저장돼 있지 않습니다. 이 저장소는 원래 사용자의 다른 프로젝트(`link-reminder`, 링크 저장 앱)와 융합하지 않고 별도로 새로 만든 것입니다 — 두 프로젝트는 완전히 무관합니다.
- 작업 방식: T1~T15는 설계안 §12.4의 작업 분해 번호를 그대로 따르고 있습니다. 이 문서와 README의 T번호가 그 원문 번호입니다.
