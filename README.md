# MAP-LINE

손으로 그린 지도를 링크 하나로 공유하는 서비스.

> 설계안 v0.1 (2026-08-02) 기준. W0 드로잉 프로토타입 검증은 끝났고, 지금은 편집기 코어
> (드로잉·핀·라벨·검색 API)까지 만든 상태입니다. **다른 세션에서 이어서 작업하려면
> [HANDOFF.md](HANDOFF.md)를 먼저 읽으세요** — 지금 뭐가 되고 뭐가 안 되는지, 다음에 뭘 해야
> 하는지가 거기 정리돼 있습니다. 이 README는 설계 배경과 "왜 이렇게 했는가"만 다룹니다.

## 지금까지 만들어진 것

| 작업 | 상태 | 위치 |
| --- | --- | --- |
| T1 드로잉 프로토타입 | ✅ 검증 완료 | `public/prototype/draw.html` |
| T2 Next.js + Tailwind 스캐폴딩 | ✅ | `app/`, 루트 설정 파일 |
| T3 스키마 마이그레이션 | ✅ (미적용) | `supabase/migrations/0001_init.sql` |
| T4 KakaoMap.tsx | ✅ | `components/map/KakaoMap.tsx` |
| T5 좌표 단순화·투영 유틸 | ✅ | `lib/geo/` |
| T6 DrawCanvas.tsx | ✅ | `components/map/DrawCanvas.tsx` |
| T7 useMapStore.ts | ✅ | `store/useMapStore.ts` |
| T9 공유 텍스트 파서 | ✅ (API 미연결) | `lib/kakao/parseShareText.ts` |
| T12 저장/불러오기 | 🟡 로컬 초안만 | `lib/map/draftStorage.ts` |
| T8 검색, T10 핀, T11 연결선, T13~T15 | ⏸ 다음 | — |

편집기에서 현재 되는 것: **손그림(색상 4종·굵기 2단), 텍스트 라벨, 지우개, 되돌리기,
전체 지우기, 제목, 자동 저장.** 장소 검색과 핀은 Kakao REST 키가 필요해 다음 단계입니다.

## 실행

```bash
npm install
npm run dev
```

`.env.local`을 만들고 카카오 JavaScript 키를 넣어야 편집기의 지도가 뜹니다.

```bash
NEXT_PUBLIC_KAKAO_JS_KEY=발급받은_JavaScript_키
```

- 랜딩: <http://localhost:3000>
- 편집기: 랜딩의 `지도 만들기` (슬러그가 자동 생성됩니다)
- W0 프로토타입: <http://localhost:3000/prototype/draw.html>

프로토타입은 `.env.local`과 무관하게 첫 진입 시 화면에서 키를 입력받아 브라우저
localStorage에만 저장합니다. 서버로 전송되지 않습니다.

**반드시 `http://localhost:3000`으로 열어야 합니다.** `file://`로 열면 카카오 키의 도메인
검증에 실패합니다.

## 카카오 콘솔 사전 준비 (설계안 §12.3)

- [ ] 앱 생성 — **계정당 1개만.** 무료 쿼터는 개발자 계정에서 첫 번째로 카카오맵 API를 활성화한
      앱에만 주어집니다. 개발/운영 앱을 분리하지 말고 한 앱에 localhost와 운영 도메인을 함께 등록합니다.
- [ ] 내 애플리케이션 > 제품 설정 > 카카오맵 > 사용 설정 ON
- [ ] 앱 목록에서 `카카오맵 무료 쿼터` 뱃지 확인
- [ ] 플랫폼 > Web > `http://localhost:3000` 등록
- [ ] JavaScript 키 / REST API 키 분리 보관
- [ ] 비즈월렛 연결은 쿼터 부족 시점까지 보류

## W0 검증 체크리스트

프로토타입에서 다음을 순서대로 확인하고, 하나라도 실패하면 그 지점을 먼저 해결합니다.

1. **지리 고정** — 선을 그린 뒤 지도를 크게 이동했다 돌아왔을 때 같은 건물 위에 있는가
2. **줌 추적** — 줌을 3단계 이상 바꿨을 때 선이 지형과 함께 커지고 작아지는가
3. **새로고침 생존** — F5 이후에도 같은 자리에 남아 있는가 (localStorage 왕복 = 저장 왕복의 대역)
4. **제스처 분리** — 그리기 모드에서 지도가 전혀 움직이지 않는가
5. **선명도** — 레티나/모바일에서 선이 흐리지 않은가 (HUD의 `dpr` 확인)
6. **단순화율** — HUD의 `마지막 획`이 원본의 10% 이하인가
7. **팬 지연** — 지도를 끄는 동안 그림이 붙어 따라오는가 (HUD의 `redraw` ms 확인)
8. **모바일 실기기** — 특히 **카카오톡 인앱 브라우저**. 공유 링크 대다수가 여기서 열립니다

각 항목의 튜닝 상수는 `public/prototype/draw.html` 상단에 모아 두었습니다. W0의 목적은
이 값들을 실제로 만져 보고 확정하는 것입니다. 확정된 값은 `lib/geo/projection.ts`로 옮깁니다.

## 데이터베이스

```bash
# Supabase 프로젝트의 SQL Editor에 supabase/migrations/0001_init.sql 을 붙여넣어 실행
```

`edit_token`은 공개 읽기 대상에서 제외해야 하므로 뷰어와 조회 API는 `maps_public` 뷰만
조회합니다. 쓰기 정책은 만들지 않았습니다 — anon key로는 쓸 수 없고, 모든 쓰기는 Route Handler가
service role로 수행하며 `edit_token`을 서버에서 검증합니다.

## 환경 변수

`.env.example`을 `.env.local`로 복사해 채웁니다.

| 변수 | 노출 | 용도 |
| --- | --- | --- |
| `NEXT_PUBLIC_KAKAO_JS_KEY` | 클라이언트 | 지도 SDK. 도메인 화이트리스트로 방어 |
| `KAKAO_REST_KEY` | **서버 전용** | 검색·경로·정적 지도 프록시 |
| `NEXT_PUBLIC_SUPABASE_URL` | 클라이언트 | — |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | 클라이언트 | 읽기 전용 |
| `SUPABASE_SERVICE_ROLE_KEY` | **서버 전용** | 쓰기 |

`KAKAO_REST_KEY`에 `NEXT_PUBLIC_` 접두어를 붙이면 안 됩니다. 노출되면 타인이 쿼터를 소진시키고
그 비용이 청구됩니다. 클라이언트는 카카오 REST API를 직접 호출하지 않고 반드시 Route Handler를
경유합니다.

## 테스트

```bash
npm test
npm run typecheck
```

**`npm run dev`가 떠 있는 상태에서 `npm run build`를 돌리지 마세요.** 둘이 같은 `.next`를
쓰기 때문에 프로덕션 빌드가 dev 서버가 참조하던 청크를 덮어쓰고, 이후 모든 페이지가
`Cannot find module './vendor-chunks/....js'`로 500을 냅니다. 이미 겪었다면:

```bash
npx kill-port 3000 && rm -rf .next && npm run dev
```

`lib/geo`의 RDP와 줌 보정만 대상입니다. 프로토타입은 브라우저에서 사람이 확인합니다.

## 설계상 확정해 둔 것

- **RDP는 위경도가 아니라 화면 좌표에서 수행합니다.** 고정 줌에서 화면↔위경도는 국소적으로
  선형이라 결과가 사실상 같고, 오차 단위가 픽셀이라 지각적으로도 맞습니다. 대신 획마다
  `zoom_created`를 남겨 다른 줌에서 볼 때 굵기와 투명도를 보정합니다.
- **팬 중에는 캔버스를 CSS transform으로 통째로 밉니다.** 기준 좌표 하나의 이동량만 계산하므로
  획 수와 무관하게 비용이 일정합니다. 정확한 재투영은 `idle`에서 한 번만 합니다.
- **줌 중에는 캔버스를 숨깁니다.** 줌 애니메이션 동안 transform 근사는 축척이 어긋납니다.
- **지도 컨테이너에 `z-index: 0`을 명시합니다.** 카카오 SDK가 컨테이너 안에 만드는 레이어에
  z-index가 붙어 있어서, 컨테이너가 `auto`면 그 자식들이 상위 스태킹 컨텍스트에 참여해
  드로잉 캔버스보다 위에 깔립니다. 그러면 그리기 모드에서 `pointerdown`이 캔버스에 닿지
  않습니다. W0에서 실제로 겪은 문제입니다.
- **되돌리기는 pop이 아니라 스냅샷입니다.** 지우개가 중간 획을 지울 수 있어서 단순 pop은
  엉뚱한 획을 되살립니다. 획은 RDP 후 점 수십 개라 스냅샷 비용이 무시할 수준입니다.
- **`crypto.randomUUID`를 직접 쓰지 않습니다.** 보안 컨텍스트에서만 존재하므로 실기기 테스트에
  쓰는 `http://192.168.x.x:3000`에서 터집니다. `lib/id.ts`의 `createId()`를 씁니다.
- **`confirm()`에 의존하지 않습니다.** 인앱 브라우저나 대화상자 차단 상태에서 `false`를
  반환해 버튼이 조용히 죽습니다. 파괴적 동작은 두 번 누르기로 확인합니다.

## 아직 없는 것

장소 검색(T8), 핀과 순서 배치(T10), 자동 연결선(T11), 서버 저장(T12), 뷰어와 공유 링크(T13),
OG 썸네일(T14), 중간지점(v0.2).

T8부터는 Kakao REST 키와 Supabase 프로젝트가 필요합니다. 클라이언트는 Kakao REST API를
직접 호출하지 않고 반드시 Next.js Route Handler를 경유합니다.
