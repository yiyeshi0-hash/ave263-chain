// AVE263 鈥?iPad 8 iPadOS 26.3 research trigger app
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        runButton.setTitle("v1 AVAssetWriter", for: .normal)
        runButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        runButton.frame = CGRect(x: 20, y: 80, width: 340, height: 40)

        runV2Button.setTitle("v2 VideoToolbox (next)", for: .normal)
        runV2Button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        runV2Button.addTarget(self, action: #selector(runV2Tapped), for: .touchUpInside)
        runV2Button.frame = CGRect(x: 20, y: 126, width: 340, height: 40)

        runV3Button.setTitle("v3 IOKit direct probe", for: .normal)
        runV3Button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        runV3Button.addTarget(self, action: #selector(runV3Tapped), for: .touchUpInside)
        runV3Button.frame = CGRect(x: 20, y: 172, width: 340, height: 40)

        log.frame = CGRect(x: 20, y: 220, width: view.bounds.width - 40, height: view.bounds.height - 240)
        log.isEditable = false
        log.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        log.text = "AVE263 research 鈥?ready\n"

        view.addSubview(runButton)
        view.addSubview(runV2Button)
        view.addSubview(runV3Button)
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
}
