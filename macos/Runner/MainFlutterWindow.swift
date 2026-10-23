import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 360, height: 500)

    // Lets demo mode resize the window to check mobile and desktop layouts.
    let channel = FlutterMethodChannel(
      name: "mirragram/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setContentSize",
        let args = call.arguments as? [String: Double],
        let width = args["width"], let height = args["height"], let window = self
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      window.setContentSize(NSSize(width: width, height: height))
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
