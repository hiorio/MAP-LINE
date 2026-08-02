/**
 * 카카오 지도 SDK 중 이 프로젝트가 실제로 쓰는 부분만 선언한다.
 * 공식 타입 패키지가 없으므로 사용처가 늘어날 때마다 여기에 추가한다.
 */
declare namespace kakao.maps {
  class LatLng {
    constructor(lat: number, lng: number);
    getLat(): number;
    getLng(): number;
    equals(other: LatLng): boolean;
  }

  class Point {
    constructor(x: number, y: number);
    x: number;
    y: number;
  }

  interface Projection {
    containerPointFromCoords(latlng: LatLng): Point;
    coordsFromContainerPoint(point: Point): LatLng;
  }

  class LatLngBounds {
    constructor(sw?: LatLng, ne?: LatLng);
    extend(latlng: LatLng): void;
    isEmpty(): boolean;
  }

  interface MapOptions {
    center: LatLng;
    level?: number;
    draggable?: boolean;
  }

  class Map {
    constructor(container: HTMLElement, options: MapOptions);
    getCenter(): LatLng;
    setCenter(latlng: LatLng): void;
    setBounds(bounds: LatLngBounds): void;
    getLevel(): number;
    setLevel(level: number): void;
    getProjection(): Projection;
    setDraggable(draggable: boolean): void;
    setZoomable(zoomable: boolean): void;
    relayout(): void;
  }

  namespace event {
    function addListener(target: object, type: string, handler: () => void): void;
    function removeListener(target: object, type: string, handler: () => void): void;
  }

  function load(callback: () => void): void;
}

interface Window {
  kakao?: { maps: typeof kakao.maps };
}
