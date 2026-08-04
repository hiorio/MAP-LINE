import UIKit

extension UIColor {
    /// `#RRGGBB` 문자열에서 색을 만든다.
    ///
    /// 색을 이 형식으로 들고 다니는 이유는 서버에 그렇게 저장되기 때문이다. 웹이
    /// CSS 색으로 쓰던 값을 그대로 받으므로, 앱에서만 다른 형식으로 바꾸면 같은
    /// 지도가 두 곳에서 다른 색으로 보인다.
    ///
    /// 읽을 수 없는 값이면 nil을 준다. 검정으로 대신하면 사용자가 고른 색이 조용히
    /// 사라진 것인지 원래 검정인지 구별할 수 없다.
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
