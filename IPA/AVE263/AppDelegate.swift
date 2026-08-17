// AppDelegate.swift — AVE263 research trigger app (AVE + JPEG runners)
// Builds via GitHub Actions macOS runner into unsigned IPA
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class ViewController: UIViewController {
    private let log = UITextView()
    private let runButton = UIButton(type: .system)
    private let runV2Button = UIButton(type: .system)
    private let runV3Button = UIButton(type: .system)
    private let jpegCreateButton = UIButton(type: .system)
    private let jpegEncodeButton = UIButton(type: .system)
    private let jpegNextButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let mk: (CGRect, String, Selector) -> UIButton = { frame, title, sel in
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            b.addTarget(self, action: sel, for: .touchUpInside)
            b.frame = frame
            return b
        }

        runButton = mk(CGRect(x: 20, y: 60, width: 340, height: 32), "v1 AVAssetWriter H264", #selector(runTapped))
        runV2Button = mk(CGRect(x: 20, y: 96, width: 340, height: 32), "v2 VT H264", #selector(runV2Tapped))
        runV3Button = mk(CGRect(x: 20, y: 132, width: 340, height: 32), "v3 IOKit probe", #selector(runV3Tapped))
        jpegCreateButton = mk(CGRect(x: 20, y: 176, width: 340, height: 32), "JPEG create-only (size seq)", #selector(jpegCreateTapped))
        jpegEncodeButton = mk(CGRect(x: 20, y: 212, width: 340, height: 32), "JPEG create+encode", #selector(jpegEncodeTapped))
        jpegNextButton = mk(CGRect(x: 20, y: 248, width: 340, height: 32), "JPEG next size", #selector(jpegNextTapped))

        log.frame = CGRect(x: 20, y: 288, width: view.bounds.width - 40, height: view.bounds.height - 300)
        log.isEditable = false
        log.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        log.text = "AVE263 research ready\n"

        for v in [runButton, runV2Button, runV3Button, jpegCreateButton, jpegEncodeButton, jpegNextButton] {
            view.addSubview(v)
        }
        view.addSubview(log)
    }

    @objc private func runTapped() {
        log.text += "=== v1 start ===\n"
        AVERunner.shared.start { [weak self] msg in
            DispatchQueue.main.async { self?.log.text += msg + "\n" }
        }
    }

    @objc private func runV2Tapped() {
        log.text += AVERunnerV2.shared.next() + "\n"
        log.text += "=== v2 start ===\n"
        AVERunnerV2.shared.start { [weak self] msg in
            DispatchQueue.main.async { self?.log.text += msg + "\n" }
        }
    }

    @objc private func runV3Tapped() {
        log.text += "=== v3 start ===\n"
        AVERunnerV3.shared.start { [weak self] msg in
            DispatchQueue.main.async { self?.log.text += msg + "\n" }
        }
    }

    @objc private func jpegCreateTapped() {
        log.text += AVERunnerJPEG.shared.next() + "\n"
        log.text += "=== JPEG create-only ===\n"
        AVERunnerJPEG.shared.createOnly { [weak self] msg in
            DispatchQueue.main.async { self?.log.text += msg + "\n" }
        }
    }

    @objc private func jpegEncodeTapped() {
        log.text += AVERunnerJPEG.shared.next() + "\n"
        log.text += "=== JPEG create+encode ===\n"
        AVERunnerJPEG.shared.createAndEncode { [weak self] msg in
            DispatchQueue.main.async { self?.log.text += msg + "\n" }
        }
    }

    @objc private func jpegNextTapped() {
        log.text += AVERunnerJPEG.shared.next() + "\n"
    }
}
