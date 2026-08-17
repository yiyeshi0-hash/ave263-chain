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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        runButton.setTitle("Run AVE trigger", for: .normal)
        runButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        runButton.frame = CGRect(x: 40, y: 100, width: 300, height: 50)

        log.frame = CGRect(x: 20, y: 180, width: view.bounds.width - 40, height: view.bounds.height - 220)
        log.isEditable = false
        log.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        log.text = "AVE263 research trigger — ready\n"

        view.addSubview(runButton)
        view.addSubview(log)
    }

    @objc private func runTapped() {
        log.text += "=== starting ===\n"
        AVERunner.shared.start { [weak self] msg in
            DispatchQueue.main.async {
                self?.log.text += msg + "\n"
            }
        }
    }
}
