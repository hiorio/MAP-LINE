import UIKit

protocol DrawingOverlayViewDelegate: AnyObject {
    /// 손을 뗐을 때 한 번 부른다. 화면 좌표로 넘기고, 위경도 변환은 지도를 아는 쪽이 한다.
    func drawingView(_ view: DrawingOverlayView, didFinishStroke screenPoints: [CGPoint])
}

/// 지도 위에서 손가락을 따라 선을 긋는 레이어.
///
/// 긋는 동안에는 여기서 화면 좌표 그대로 그린다. 손을 떼면 위경도로 바꿔 SDK의
/// Shape로 넘기고 이 레이어는 지운다. 웹에서 쓰던 방식과 같다 — 그리는 중인 획은
/// 아직 문서가 아니므로 확정된 것들과 섞지 않는다.
final class DrawingOverlayView: UIView {
    weak var delegate: DrawingOverlayViewDelegate?

    /// 그리기 모드가 아니면 터치를 지도로 흘려보낸다.
    var isEnabled: Bool = false {
        didSet { isUserInteractionEnabled = isEnabled }
    }

    private var livePoints: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isMultipleTouchEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("사용하지 않는다") }

    // MARK: - 입력

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        livePoints = [point]
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        // 같은 자리에서 떨리는 값은 버린다. 좌표만 늘고 그림은 그대로다.
        if let last = livePoints.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
        livePoints.append(point)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // 전화가 오거나 시스템 제스처가 끼어들면 그리던 것을 버린다.
        livePoints = []
        setNeedsDisplay()
    }

    private func finish() {
        let points = livePoints
        livePoints = []
        setNeedsDisplay()
        guard points.count >= 2 else { return }
        delegate?.drawingView(self, didFinishStroke: points)
    }

    // MARK: - 그리기

    override func draw(_ rect: CGRect) {
        guard livePoints.count >= 2, let context = UIGraphicsGetCurrentContext() else { return }

        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(6)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: livePoints[0])
        for point in livePoints.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }
}
