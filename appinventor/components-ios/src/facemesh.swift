import Foundation
import WebKit
import UIKit


@objc open class FaceExtension: NonvisibleComponent, WKScriptMessageHandler, WKUIDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  
  private var imagePicker: UIImagePickerController?
  var selectedImage: UIImage?
  
  fileprivate final let _ERROR_WEBVIEWER_NOT_SET: String =  "You must specify a WebViewer using the WebViewer designer property before you can call"
  private let _ERROR_JSON_PARSE_FAILED = 101
  private let _MODEL_URL = "https://tfhub.dev/mediapipe/tfjs-model/facemesh/1/default/1/"
  private let _BACK_CAMERA = "Back"
  private let _FRONT_CAMERA = "Front"
  
  private var _webview: WKWebView?
  private var _webviewer: WebViewer?
  private var _webviewerApiSource: String = ""
  private var _webviewerApi: WKUserScript?
  
  private var _keyPoints: [String: [Double]] = [:]
  internal var _cameraMode = "Front"
  internal var _initialized = false
  private var _enabled = true
  private var _showMesh: Bool = false
  private var _backgroundImage = ""
  private var width = 350
  private var height = 200
  
  private enum IllegalStateError: Error {
    case webviewerNotSet
  }
  
  /**
   * Creates a new FaceExtension extension.
   */
  
  @objc public override init(_ parent: ComponentContainer) {
    super.init(parent)
    
    _keyPoints["forehead"] = []
    _keyPoints["leftCheek"] = []
    _keyPoints["rightCheek"] = []
    _keyPoints["leftEyebrow"] = []
    _keyPoints["rightEyebrow"] = []
    _keyPoints["chin"] = []
    _keyPoints["leftEyeInnerCorner"] = []
    _keyPoints["rightEyeInnerCorner"] = []
    _keyPoints["mouthTop"] = []
    _keyPoints["mouthBottom"] = []
    _keyPoints["leftEyeTop"] = []
    _keyPoints["leftEyeBottom"] = []
    _keyPoints["rightEyeTop"] = []
    _keyPoints["rightEyeBottom"] = []
    _keyPoints["rightEarStart"] = []
    _keyPoints["leftEarStart"] = []
    _keyPoints["noseBottom"] = []
    _keyPoints["rightNoseTop"] = []
    _keyPoints["leftNoseTop"] = []
    _keyPoints["allPoints"] = []
    print("Created FaceExtension")
  }
  
  private func configureWebView(_ webview: WKWebView) {
    self._webview = webview
    let config = webview.configuration
    
    let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        config.preferences = preferences
    
    if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
    
        config.preferences.javaScriptEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
    
    let controller = config.userContentController
    controller.add(self, name: "FaceExtension")
  }
  
  @objc open var WebViewer: WebViewer {
    get {
      return _webviewer!
    }
    set {
      configureWebView(newValue.view as! WKWebView)
      print("configureWebView called")
      if let url = Bundle(for: FaceExtension.self).url(forResource: "index", withExtension: "html") {
        let request = URLRequest(url: url)
        print(request)
        _webview?.load(request)
        print("Request loaded")
      }else {
        print("Error: Unable to find the HTML file in the bundle")
    }
//      showImagePicker()
    }
  }

  
  @objc open func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      print("WebView content fully loaded")
      
      let jsCheck = "typeof processImage === 'function';"
      _webview?.evaluateJavaScript(jsCheck) { result, error in
          if let error = error {
              print("Error checking JS function existence: \(error)")
          } else if let isFunction = result as? Bool, isFunction {
              print("processImage function is available")
              self.showImagePicker()
          } else {
              print("processImage function is not available")
            let scriptCheck = "document.getElementsByTagName('script').length;"
            self._webview?.evaluateJavaScript(scriptCheck) { scriptCount, scriptError in
              if let scriptError = scriptError {
                print("Error checking script count: \(scriptError.localizedDescription)")
              } else {
                print("Number of scripts loaded: \(scriptCount ?? 0)")
              }
            }
          }
      }
  }

//  @objc open func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//      print("WebView content fully loaded")
//      
//      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//          self.showImagePicker()
//      }
//  }
  
  @objc open func showImagePicker() {
      guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
          print("Photo library not available")
          return
      }
      
      imagePicker = UIImagePickerController()
      imagePicker?.delegate = self
      imagePicker?.sourceType = .photoLibrary
      
      if let viewController = UIApplication.shared.windows.first?.rootViewController {
          DispatchQueue.main.async {
              viewController.present(self.imagePicker!, animated: true, completion: nil)
          }
      } else {
          print("Error: Unable to access the root view controller")
      }
  }

  @objc open func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
      picker.dismiss(animated: true, completion: nil)
      
      guard let selectedImage = info[.originalImage] as? UIImage else {
          print("Error: No image was selected")
          return
      }
      
      // Convert the selected image to a base64 string
      if let imageData = selectedImage.jpegData(compressionQuality: 0.8) {
          let base64Image = imageData.base64EncodedString()
          
          // Now send this base64 string to WebView
          sendImageToWebView(base64String: base64Image)
      } else {
          print("Error: Unable to convert image to data")
      }
  }
      
  @objc open func sendImageToWebView(base64String: String) {
    let jsCode = String(format: "processImage('%@');", base64String)
    _webview?.evaluateJavaScript(jsCode) { result, error in
      if let error = error {
        print("Error sending image to JavaScript: \(error)")
      } else {
        print("Image sent successfully")
      }
    }
  }
  
  @available(iOS 15.0, *)
  public func webView(_ webView: WKWebView,
                      requestMediaCapturePermissionFor
                      origin: WKSecurityOrigin,initiatedByFrame
                      frame: WKFrameInfo,type: WKMediaCaptureType,
                      decisionHandler: @escaping (WKPermissionDecision) -> Void) {
    decisionHandler(.grant)
  }
  
  public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    print("receiving content")
    if message.name == "FaceExtension" {
      guard let dict = message.body as? [String: Any],
            let functionCall = dict["functionCall"] as? String,
            let args = dict["args"] else {
        print("JSON Error message not received")
        return
      }
      
      switch functionCall {
      case "ready":
        print("Model Ready")
        ModelReady()
        if _enabled {
          UseCamera = _cameraMode
        }
        
      case "reportResult":
        print("Reporting Result")
        do {
          let result = try getYailObjectFromJson(args as? String, true)
          print(result)
        } catch {
          print("Error parsing JSON from web view")
          Error(_ERROR_JSON_PARSE_FAILED as AnyObject, "Error parsing JSON from web view" as AnyObject)
        }
        
      case "reportImage":
        print("Reporting Image")
        VideoUpdated()
        
      case "error":
        print("Error function called")
        if let errorDetails = args as? [String: Any],
           let errorCode = errorDetails["errorCode"],
           let errorMessage = errorDetails["errorMessage"] {
          Error(errorCode as AnyObject, errorMessage as AnyObject)
        } else {
          Error("UnknownError" as AnyObject, "Unknown error occurred" as AnyObject)
        }
        
      default:
        print("Unknown function call: \(functionCall)")
      }
    }
  }
  
  @objc open var FaceLandmarks: [[Double]] {
    get {
      var landmarks: [[Double]] = []
      for point in _keyPoints.values {
        if point.count == 2 {
          landmarks.append(point)
        }
      }
      return landmarks
    }
  }
  
  @objc open var BackgroundImage: String = ""
  
  @objc open var Forehead: [Double] {
    return _keyPoints["forehead"] ?? []
  }
  
  @objc open var NoseBottom: [Double] {
    return _keyPoints["noseBottom"] ?? []
  }
  
  @objc open var Chin: [Double] {
    return _keyPoints["chin"] ?? []
  }
  
  @objc open var LeftCheek: [Double] {
    return _keyPoints["leftCheek"] ?? []
  }
  
  @objc open var RightCheek: [Double] {
    return _keyPoints["rightCheek"] ?? []
  }
  
  @objc open var LeftEyebrow: [Double] {
    return _keyPoints["leftEyebrow"] ?? []
  }
  
  @objc open var RightEyebrow: [Double] {
    return _keyPoints["rightEyebrow"] ?? []
  }
  
  @objc open var LeftEyeInnerCorner: [Double] {
    return _keyPoints["leftEyeInnerCorner"] ?? []
  }
  
  @objc open var RightEyeInnerCorner: [Double] {
    return _keyPoints["rightEyeInnerCorner"] ?? []
  }
  
  @objc open var MouthTop: [Double] {
    return _keyPoints["mouthTop"] ?? []
  }
  
  @objc open var MouthBottom: [Double] {
    return _keyPoints["mouthBottom"] ?? []
  }
  
  @objc open var LeftEyeTop: [Double] {
    return _keyPoints["leftEyeTop"] ?? []
  }
  
  @objc open var LeftEyeBottom: [Double] {
    return _keyPoints["leftEyeBottom"] ?? []
  }
  
  @objc open var RightEyeTop: [Double] {
    return _keyPoints["rightEyeTop"] ?? []
  }
  
  @objc open var RightEyeBottom: [Double] {
    return _keyPoints["rightEyeBottom"] ?? []
  }
  
  @objc open var RightEarStart: [Double] {
    return _keyPoints["rightEarStart"] ?? []
  }
  
  @objc open var LeftEarStart: [Double] {
    return _keyPoints["leftEarStart"] ?? []
  }
  
  @objc open var RightNoseTop: [Double] {
    return _keyPoints["rightNoseTop"] ?? []
  }
  
  @objc open var LeftNoseTop: [Double] {
    return _keyPoints["leftNoseTop"] ?? []
  }
  
  @objc open var FaceWidth: Double {
    return (_keyPoints["rightCheek"]?.first ?? 0) - (_keyPoints["leftCheek"]?.first ?? 0)
  }
  
  @objc open var CheekToNoseDistance: Double {
    return (_keyPoints["leftNoseTop"]?.first ?? 0) - (_keyPoints["leftCheek"]?.first ?? 0)
  }
  
  @objc open var EyeToMouthHeight: Double {
    return (_keyPoints["mouthTop"]?.last ?? 0) - (_keyPoints["forehead"]?.last ?? 0)
  }
  
  @objc open var AllPoints: [Double] {
    return _keyPoints["allPoints"] ?? []
  }
  
  
  @objc open var Enabled: Bool {
    get {
      return _enabled
    }
    set {
      _enabled = newValue
      if _initialized {
        do {
          try assertWebView("Enabled")
        } catch {
          print(_ERROR_WEBVIEWER_NOT_SET, "Enabled")
        }
      }
    }
  }
  
  @objc open var ShowMesh: Bool {
    get {
      return _showMesh
    }
    set {
      _showMesh = newValue
      if _initialized {
        if _showMesh {
          _webview?.evaluateJavaScript("turnMeshOn();", completionHandler: nil)
        } else {
          _webview?.evaluateJavaScript("turnMeshOff();", completionHandler: nil)
        }
      }
    }
  }
  
  @objc open var UseCamera: String {
    get {
      return _cameraMode
    }
    set {
      if newValue == _BACK_CAMERA || newValue == _FRONT_CAMERA {
        _cameraMode = newValue
        if _initialized {
          do {
            let frontFacing = (newValue == _FRONT_CAMERA)
            try assertWebView("UseCamera", frontFacing)
          } catch {
            print(_ERROR_WEBVIEWER_NOT_SET, "UseCamera")
          }
        }
      } else {
        DispatchQueue.main.async {
          self.Error("InvalidCameraMode" as AnyObject, "Invalid camera selection. Must be either 'Front' or 'Back'." as AnyObject)
        }
        _form?.dispatchErrorOccurredEvent(self, "UseCamera", 3300, "Invalid camera selection. Must be either 'Front' or 'Back'.")
      }
    }
  }
  
  //faceMesh Methods
  
  @objc open func Initialize() {
    if _webview != nil {
      print("Initialized")
      _initialized = true
    }
  }
  
  @objc open var Width: Int {
    get {
      return width
    }
    set {
      width = newValue
    }
  }
  
  @objc open var Height: Int {
    get {
      return height
    }
    set {
      height = newValue
    }
  }
  
  
  @objc open func ModelReady() {
    EventDispatcher.dispatchEvent(of: self, called: "ModelReady")
    print("Dispatched ModelReady")
  }
  
  @objc open func Error(_ errorCode: AnyObject, _ errorMessage: AnyObject) {
    EventDispatcher.dispatchEvent(of: self, called: "Error", arguments: errorCode, errorMessage)
    print("Dispatched Error")
  }
  
  @objc open func VideoUpdated() {
    EventDispatcher.dispatchEvent(of: self, called: "VideoUpdated")
    print("Dispatched VideoUpdated")
  }
  
  private func evaluateJavaScript(_ script: String) {
    _webview?.evaluateJavaScript(script, completionHandler: { (result, error) in
      if let error = error {
        print("JavaScript evaluation error: \(error)")
      } else {
        print("JavaScript evaluation result: \(String(describing: result))")
      }
    })
  }
  
  
  @objc open func onDelete() {
    if _initialized && _webview != nil {
      evaluateJavaScript("teardown();")
      _webview = nil
    }
  }
  
  @objc open func onPause() {
    if _initialized && _webview != nil {
      evaluateJavaScript("stopVideo();")
    }
  }
  
  @objc open func onResume() {
    if _initialized && _enabled && _webview != nil {
      evaluateJavaScript("startVideo();")
    }
  }
  
  @objc open func onStop() {
    if _initialized && _webview != nil {
      evaluateJavaScript("teardown();")
      _webview = nil
    }
  }
  
  private let y_offset: Int = -20
  private let y_multiplier: Double = 1.0 / 620.0
  private let x_multiplier: Double = 1.0 / 480.0
  private let x_offset: Double = 180.0
  private let x_range: Double = 480.0
  
  @objc open func reportImage(dataUrl: String) {
    print("reportImage \(dataUrl)")
    if !dataUrl.isEmpty {
      self.BackgroundImage = String(dataUrl.dropFirst(dataUrl.firstIndex(of: ",")?.utf16Offset(in: dataUrl) ?? 0 + 1))
      DispatchQueue.main.async {
        self.VideoUpdated()
      }
    }
  }
  
  @objc open func reportWidth() -> String {
    return String(width)
  }
  
  @objc open func reportHeight() -> String {
    return String(height)
  }
  
  @objc open func reportResult(result: String) {
    do {
      let res = try JSONSerialization.jsonObject(with: Data(result.utf8), options: []) as! [String: Any]
      
      func parseKeyPoints(from obj: [String: Any], keys: [String]) -> [String: [Double]] {
        var points = [String: [Double]]()
        for key in keys {
          if let point = obj[key] as? [String: Double] {
            points[key] = [point["x"]! * Double(width) * x_multiplier, point["y"]! * Double(height) * y_multiplier, point["z"]!]
          }
        }
        return points
      }
      
      let keys = ["forehead", "chin", "leftCheek", "rightCheek", "leftEyebrow", "rightEyebrow", "leftEyeInnerCorner", "rightEyeInnerCorner", "mouthTop", "mouthBottom", "leftEyeTop", "leftEyeBottom", "rightEyeTop", "rightEyeBottom", "rightEarStart", "leftEarStart", "noseBottom", "rightNoseTop", "leftNoseTop"]
      _keyPoints = parseKeyPoints(from: res, keys: keys)
      
      if let allPoints = res["allPoints"] as? [String: [String: Double]] {
        var listOfObjects = [Double]()
        for i in 0..<450 {
          if let point = allPoints[String(i)],
             let x = point["x"], let y = point["y"] {
            let adjustedX = x * Double(width) * x_multiplier
            let adjustedY = y * Double(height) * y_multiplier
            listOfObjects.append(adjustedX)
            listOfObjects.append(adjustedY)
          }
        }
        
        _keyPoints["allPoints"] = listOfObjects
      }
      
      DispatchQueue.main.async {
        self.FaceUpdated()
      }
      
    } catch let error as NSError {
      DispatchQueue.main.async {
        self.Error(self._ERROR_JSON_PARSE_FAILED as AnyObject, error.localizedDescription as AnyObject)
      }
      print("Error parsing JSON from web view: \(error)")
    }
  }
  
  @objc open func FaceUpdated() {
    EventDispatcher.dispatchEvent(of: self, called: "FaceUpdated")
    print("Dispatched FaceUpdated")
  }
  
  
  @objc open func error(errorCode: Int, errorMessage: String) {
    DispatchQueue.main.async {
      self.Error(errorCode as AnyObject, errorMessage as AnyObject)
    }
  }
  
  private func assertWebView(_ method: String, _ args: Any...) throws {
    if _webview == nil {
      throw IllegalStateError.webviewerNotSet
    }
    switch method {
    case "UseCamera":
      _webview?.evaluateJavaScript("setCameraFacingMode(\(args[0] as! Bool));")
    default:
      print("Error: Not a valid method")
    }
  }
  
  @objc open func getYailObjectFromJson(_ json: String?, _ boolean: Bool) throws -> Any {
    guard let json = json else {
      throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
    }
    guard let data = json.data(using: .utf8) else {
      throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Error converting string to data"])
    }
    return try JSONSerialization.jsonObject(with: data, options: [])
  }
  
}
