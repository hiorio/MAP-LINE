import Foundation

/// 웹과 네이티브 카카오 지도가 같은 축척을 문서 하나로 주고받기 위한 변환.
///
/// 웹은 값이 작을수록 확대되고 1~14를 사용한다. 네이티브 v2는 값이 클수록 확대되고
/// 같은 축척의 두 값 합이 20이다. 서버 문서에는 웹 기준 값만 저장한다.
enum MapZoom {
    static let documentRange = 1...14
    static let nativeRangeForSharedDocument = 6...19

    static func nativeLevel(fromDocumentLevel level: Int) -> Int {
        let document = min(documentRange.upperBound, max(documentRange.lowerBound, level))
        return 20 - document
    }

    static func documentLevel(fromNativeLevel level: Int) -> Int {
        let native = min(
            nativeRangeForSharedDocument.upperBound,
            max(nativeRangeForSharedDocument.lowerBound, level)
        )
        return 20 - native
    }

    /// 이전 iOS 빌드가 네이티브 레벨(예: 17)을 문서에 직접 남긴 경우를 복구한다.
    static func normalizedDocumentLevel(_ level: Int) -> Int {
        if level > documentRange.upperBound {
            return documentLevel(fromNativeLevel: level)
        }
        return min(documentRange.upperBound, max(documentRange.lowerBound, level))
    }
}

extension GeoStroke {
    func normalizingDocumentZoomLevel() -> GeoStroke {
        let normalized = MapZoom.normalizedDocumentLevel(zoomCreated)
        guard normalized != zoomCreated else { return self }
        return GeoStroke(
            id: id,
            path: path,
            color: color,
            width: width,
            zoomCreated: normalized
        )
    }
}
