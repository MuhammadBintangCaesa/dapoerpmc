import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DapoerCalendarNotifications")
    let channel = FlutterMethodChannel(name: "dapoer/calendar_notifications", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "requestPermission":
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "permission_failed", message: error.localizedDescription, details: nil))
            } else {
              result(granted)
            }
          }
        }
      case "getEnabled":
        result(UserDefaults.standard.bool(forKey: "calendar_notifications_enabled"))
      case "setEnabled":
        let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
        UserDefaults.standard.set(enabled, forKey: "calendar_notifications_enabled")
        result(nil)
      case "schedule":
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? Int,
              let title = args["title"] as? String,
              let body = args["body"] as? String,
              let millis = args["atMillis"] as? Double else {
          result(FlutterError(code: "invalid_arguments", message: "Data pengingat tidak lengkap", details: nil))
          return
        }
        let date = Date(timeIntervalSince1970: millis / 1000.0)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: String(id), content: content, trigger: trigger)) { error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "schedule_failed", message: error.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
      case "cancel":
        let id = (call.arguments as? [String: Any])?["id"] as? Int ?? 0
        center.removePendingNotificationRequests(withIdentifiers: [String(id)])
        center.removeDeliveredNotifications(withIdentifiers: [String(id)])
        result(nil)
      case "cancelAll":
        center.removeAllPendingNotificationRequests()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
