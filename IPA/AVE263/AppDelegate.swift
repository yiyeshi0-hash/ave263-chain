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
    private var log: UITextView!
    private var runButton: UIButton!
    private var runV2Button: UIButton!
    private var runV3Button: UIButton!
    private var jpegCreateButton: UIButton!
    private var jpegEncodeButton: UIButton!
    private var jpegNextButton: UIButton!
    private var jpeg2Button: UIButton!

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
        jpeg2Button = mk(CGRect(x: 20, y: 284, width: 340, height: 32), "JPEG2 ImageIO encode", #selector(jpeg2Tapped))

        log.frame = CGRect(x: 20, y: 324, width: view.bounds.width - 40, height: view.bounds.height - 336)
        log.isEditable = false
        log.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        log.text = "AVE263 research ready\n"

        let buttons: [UIButton] = [runButton, runV2Button, runV3Button, jpegCreateButton, jpegEncodeButton, jpegNextButton, jpeg2Button]
        for v in buttons { view.addSubview(v) }
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

    @objc private func jpeg2Tapped() {
        log.text += AVERunnerJPEG2.shared.next() + "\n"
        log.text += "=== JPEG2 ImageIO ===\n"
        AVERunnerJPEG2.shared.run { [weak self] msg in
            DispatchQueue.main.async { self?.log.text += msg + "\n" }
        }
    }
}
