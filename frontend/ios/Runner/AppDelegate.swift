import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Explicitly owned engine. Using the implicit-эngine (storyboard) path
  // crashes on ProMotion (120 Hz) devices running iOS 26.x:
  // -[VSyncClient initWithTaskRunner:callback:] SIGSEGV when viewDidLoad
  // runs before the engine has a shell. See flutter/flutter#190030.
  lazy var flutterEngine = FlutterEngine(name: "avro_engine", project: nil)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    window.makeKeyAndVisible()
    self.window = window

    return launched
  }
}