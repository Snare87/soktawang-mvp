import UIKit
import Flutter
// import UserNotifications // 최신 버전에서는 명시적 import가 필요 없을 수 있음

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS 10 미만 버전을 위한 코드 (최신 앱에서는 거의 필요 없음)
    // if #available(iOS 10.0, *) {
    //   UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    // }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}