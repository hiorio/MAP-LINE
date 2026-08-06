import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// 다른 앱에서 "공유"로 넘어온 장소를 보관함에 담는다.
///
/// 카카오맵·네이버지도에서 장소를 공유하면 보통 이런 텍스트가 온다.
///
///     [카카오맵] 스타벅스 강남점
///     서울 강남구 강남대로 390
///     http://kko.to/xxxx
///
/// 다만 앱마다, 버전마다 무엇을 넘기는지 다르다. 텍스트만 오기도 하고 링크만 오기도
/// 한다. 그래서 골라내지 않고 받은 조각을 전부 서버로 보낸다. 무엇이 실제로 오는지는
/// 시뮬레이터에서 알 수 없다 — 카카오맵이 깔려 있지 않다. 실기기에서만 확인된다.
/// 그래서 받은 원문을 화면에 함께 보여 준다. 첫 실기기 실행이 곧 조사다.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        Task { @MainActor in
            let pieces = await collectSharedText()
            present(ShareIntakeView(
                rawText: ShareIntake.combine(pieces),
                sourcePieceCount: pieces.count,
                onDone: { [weak self] in self?.finish() },
                onCancel: { [weak self] in self?.finish() }
            ))
        }
    }

    private func present(_ root: ShareIntakeView) {
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// 공유 시트가 준 항목에서 글자가 될 만한 것을 전부 긁어모은다.
    private func collectSharedText() async -> [String] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return [] }

        var pieces: [String] = []
        for item in items {
            // 어떤 앱은 제목만 attributedContentText에 담아 보낸다.
            if let title = item.attributedContentText?.string, !title.isEmpty {
                pieces.append(title)
            }
            for provider in item.attachments ?? [] {
                if let text = await load(provider, as: .plainText) { pieces.append(text) }
                if let url = await load(provider, as: .url) { pieces.append(url) }
            }
        }
        return pieces
    }

    private func load(_ provider: NSItemProvider, as type: UTType) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { value, _ in
                switch value {
                case let text as String: continuation.resume(returning: text)
                case let url as URL: continuation.resume(returning: url.absoluteString)
                case let data as Data: continuation.resume(returning: String(data: data, encoding: .utf8))
                default: continuation.resume(returning: nil)
                }
            }
        }
    }
}
