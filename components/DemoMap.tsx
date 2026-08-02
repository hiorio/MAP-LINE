/**
 * 랜딩용 데모 그림.
 *
 * 실제 카카오 지도를 띄우지 않는 이유: 랜딩은 방문자 전원이 보는 화면이라 지도 SDK를
 * 띄우면 첫 화면 로딩이 무거워지고, 정적 지도 이미지를 쓰면 방문자 수만큼 쿼터를 먹는다.
 * 제품이 무엇인지 한눈에 보여주는 것이 목적이므로 그림 하나로 충분하다.
 */
export function DemoMap() {
  return (
    <svg
      viewBox="0 0 400 260"
      className="h-auto w-full"
      role="img"
      aria-label="손그림이 얹힌 지도 예시: 번호가 매겨진 장소 세 곳과 그 사이를 잇는 손으로 그린 선"
    >
      <rect width="400" height="260" rx="12" fill="#F1EDE6" />

      {/* 도로망 — 실제 지도의 느낌만 낸다 */}
      <g stroke="#FFFFFF" strokeLinecap="round" fill="none">
        <path d="M0 96 H400" strokeWidth="13" />
        <path d="M150 0 V260" strokeWidth="11" />
        <path d="M0 190 H400" strokeWidth="8" />
        <path d="M292 0 V260" strokeWidth="7" />
      </g>
      <g stroke="#E4DED3" strokeWidth="2" fill="none">
        <path d="M0 44 H400" />
        <path d="M0 140 H400" />
        <path d="M62 0 V260" />
        <path d="M222 0 V260" />
        <path d="M356 0 V260" />
      </g>

      {/* 블록 */}
      <g fill="#E7E2D8">
        <rect x="18" y="54" width="30" height="30" rx="3" />
        <rect x="76" y="54" width="58" height="30" rx="3" />
        <rect x="166" y="110" width="42" height="22" rx="3" />
        <rect x="238" y="152" width="40" height="28" rx="3" />
        <rect x="310" y="54" width="34" height="30" rx="3" />
      </g>
      <rect x="238" y="200" width="120" height="46" rx="4" fill="#DCE8DA" />

      {/* 손그림 — 이 제품의 핵심. 핀만으로는 표현되지 않는 정보 */}
      <path
        d="M96 78 C 120 92, 118 116, 142 122 S 186 132, 206 154"
        stroke="#E24B4A"
        strokeWidth="4"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M198 148 l10 8 -12 5"
        stroke="#E24B4A"
        strokeWidth="4"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
      <ellipse
        cx="300"
        cy="206"
        rx="34"
        ry="21"
        stroke="#2D6BE4"
        strokeWidth="3"
        fill="none"
        opacity="0.85"
      />

      {/* 순서 연결선 — 도보 구간 */}
      <path
        d="M225 168 L288 196"
        stroke="#6B6B66"
        strokeWidth="3"
        strokeDasharray="2 7"
        strokeLinecap="round"
        fill="none"
      />

      {/* 메모 */}
      <g transform="translate(100 196)">
        <rect x="0" y="0" width="104" height="24" rx="4" fill="#FFFFFF" opacity="0.9" />
        <rect x="0" y="0" width="104" height="24" rx="4" fill="none" stroke="rgba(44,44,42,0.18)" />
        <text x="52" y="16" textAnchor="middle" fontSize="12" fill="#2C2C2A">
          여기서 계단으로
        </text>
      </g>

      {/* 번호 핀 */}
      {[
        { x: 92, y: 72, n: 1 },
        { x: 214, y: 160, n: 2 },
        { x: 300, y: 206, n: 3 },
      ].map(({ x, y, n }) => (
        <g key={n}>
          <circle cx={x} cy={y} r="13" fill="#E24B4A" stroke="#FFFFFF" strokeWidth="2" />
          <text
            x={x}
            y={y + 1}
            textAnchor="middle"
            dominantBaseline="middle"
            fontSize="13"
            fontWeight="600"
            fill="#FFFFFF"
          >
            {n}
          </text>
        </g>
      ))}
    </svg>
  );
}
