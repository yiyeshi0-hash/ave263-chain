// AVE263 — iPad 8 iPadOS 26.3 research trigger app
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        runButton.setTitle("Run AVE trigger (v1 AVAssetWriter)", for: .normal)
        runButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        runButton.frame = CGRect(x: 20, y: 100, width: 340, height: 44)

        runV2Button.setTitle("Run AVE trigger (v2 VideoToolbox)", for: .normal)
        runV2Button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        runV2Button.addTarget(self, action: #selector(runV2Tapped), for: .touchUpInside)
        runV2Button.frame = CGRect(x: 20, y: 150, width: 340, height: 44)

        log.frame = CGRect(x: 20, y: 210, width: view.bounds.width - 40, height: view.bounds.height - 230)
        log.isEditable = false
        log.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        log.text = "AVE263 research trigger v2 — ready\n"

        view.addSubview(runButton)
        view.addSubview(runV2Button)
        view.addSubview(log)
    }

    @objc private func runTapped() {
        log.text += "=== v1 start ===\n"
        AVERunner.shared.start { [weak self] msg in
            DispatchQueue.main.async {
                self?.log.text += msg + "\n"
            }
        }
    }

    @objc private func runV2Tapped() {
        log.text += "=== v2 start ===\n"
        AVERunnerV2.shared.start { [weak self] msg in
            DispatchQueue.main.async {
                self?.log.text += msg + "\n"
            }
        }
    }
}
