import SwiftUI
import UIKit

/// iOS 기본 공유 시트.
///
/// 직접 만들지 않는다. 사람들이 링크를 어디로 보낼지는 우리가 정할 일이 아니고,
/// 카카오톡·메시지·메모 어디로든 가야 이 제품이 쓸모가 있다. 기본 시트는 그 목록을
/// 기기 설정과 설치된 앱에서 알아서 가져온다.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
