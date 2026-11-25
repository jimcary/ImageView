import AppKit

@MainActor
final class AboutWindowController: NSWindowController, NSTextViewDelegate {
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 224),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.text("app.about")
        super.init(window: panel)

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = NSTextField(labelWithString: "ImageView")
        name.font = .boldSystemFont(ofSize: 20)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let versionLabel = NSTextField(labelWithString: build.map { "\(version) (\($0))" } ?? version)
        versionLabel.textColor = .secondaryLabelColor

        let contacts = NSTextView()
        contacts.isEditable = false
        contacts.isSelectable = true
        contacts.drawsBackground = false
        contacts.delegate = self
        contacts.textStorage?.setAttributedString(credits())

        let content = NSStackView(views: [icon, name, versionLabel, contacts])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        panel.contentView = content
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            contacts.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40),
            contacts.heightAnchor.constraint(equalToConstant: 44),
        ])
        panel.center()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL else { return false }
        let workspace = NSWorkspace.shared
        if url.scheme == "mailto", let mail = fallbackMailApplication(for: url, workspace: workspace) {
            workspace.open([url], withApplicationAt: mail, configuration: .init(), completionHandler: nil)
        } else {
            workspace.open(url)
        }
        return true
    }

    private func fallbackMailApplication(for url: URL, workspace: NSWorkspace) -> URL? {
        if let handler = workspace.urlForApplication(toOpen: url) {
            let urlTypes = Bundle(url: handler)?.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
            let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() }
            // A browser can be assigned mailto without declaring support for it.
            guard schemes.contains("https"), !schemes.contains("mailto") else { return nil }
        }
        return workspace.urlForApplication(withBundleIdentifier: "com.apple.mail")
    }

    private func credits() -> NSAttributedString {
        let credits = NSMutableAttributedString(string: "\(L10n.text("app.about.author")) ")
        credits.append(NSAttributedString(
            string: "Cary",
            attributes: [.link: URL(string: "mailto:jimcary@qq.com")!]
        ))
        credits.append(NSAttributedString(string: "\n\(L10n.text("app.about.website")) "))
        credits.append(NSAttributedString(
            string: "ImageView",
            attributes: [.link: URL(string: "https://github.com/jimcary/ImageView")!]
        ))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        credits.addAttributes([
            .paragraphStyle: paragraphStyle,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ], range: NSRange(location: 0, length: credits.length))
        return credits
    }
}
