import Cocoa

protocol ShortcutRecorderDelegate: AnyObject {
    func shortcutRecorder(_ panel: ShortcutRecorderPanel, didRecord mapping: ButtonMapping)
    func shortcutRecorderDidCancel(_ panel: ShortcutRecorderPanel)
}

final class ShortcutRecorderPanel: NSPanel {

    weak var recorderDelegate: ShortcutRecorderDelegate?

    private(set) var capturedMouseButton: Int?
    private let instructionLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var captureView: ShortcutCaptureView?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        title = "Record Mapping"
        isFloatingPanel = true
        level = .floating
        isReleasedWhenClosed = false
        center()

        setupUI()
        showStep1()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView else { return }

        instructionLabel.alignment = .center
        instructionLabel.font = .systemFont(ofSize: 14)
        instructionLabel.lineBreakMode = .byWordWrapping
        instructionLabel.maximumNumberOfLines = 2
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(instructionLabel)
        contentView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),
            instructionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

            cancelButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Steps

    private func showStep1() {
        capturedMouseButton = nil
        instructionLabel.stringValue = "Press the mouse button to map..."
        captureView?.removeFromSuperview()
        captureView = nil
    }

    private func showStep2() {
        instructionLabel.stringValue = "Button \(capturedMouseButton!) captured.\nNow press the keyboard shortcut..."

        let capture = ShortcutCaptureView()
        capture.onKeyCapture = { [weak self] keyCode, modifierFlags in
            self?.didCaptureShortcut(keyCode: keyCode, modifierFlags: modifierFlags)
        }
        capture.onEscape = { [weak self] in
            guard let self else { return }
            self.recorderDelegate?.shortcutRecorderDidCancel(self)
            self.close()
        }
        capture.translatesAutoresizingMaskIntoConstraints = false

        contentView?.addSubview(capture)
        if let contentView {
            NSLayoutConstraint.activate([
                capture.widthAnchor.constraint(equalToConstant: 1),
                capture.heightAnchor.constraint(equalToConstant: 1),
                capture.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                capture.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            ])
        }

        self.captureView = capture
        makeFirstResponder(capture)
    }

    // MARK: - Mouse Button Capture (called by AppDelegate)

    func didCaptureMouseButton(_ button: Int) {
        capturedMouseButton = button
        showStep2()
    }

    // MARK: - Keyboard Shortcut Capture

    private func didCaptureShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        guard let mouseButton = capturedMouseButton else { return }

        let mapping = ButtonMapping(
            id: UUID(),
            mouseButton: mouseButton,
            keyCode: keyCode,
            modifierFlags: CGEventFlags(cocoaFlags: modifierFlags).rawValue
        )
        recorderDelegate?.shortcutRecorder(self, didRecord: mapping)
        close()
    }

    // MARK: - Cancel

    @objc private func cancelPressed() {
        recorderDelegate?.shortcutRecorderDidCancel(self)
        close()
    }

    override func cancelOperation(_ sender: Any?) {
        cancelPressed()
    }

    // MARK: - State Query

    var isWaitingForMouseButton: Bool {
        capturedMouseButton == nil
    }
}

// MARK: - ShortcutCaptureView

private final class ShortcutCaptureView: NSView {

    var onKeyCapture: ((_ keyCode: UInt16, _ modifierFlags: NSEvent.ModifierFlags) -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let escapeKeyCode: UInt16 = 0x35
        if event.keyCode == escapeKeyCode {
            onEscape?()
            return
        }
        onKeyCapture?(event.keyCode, event.modifierFlags)
    }
}
