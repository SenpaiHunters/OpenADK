
import Observation
import WebKit

/// Handles navigation requests from the Webview
class AltoWebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    var alto: Alto = Alto.shared
    
    weak var tab: AltoTab?
    
    // This checks for new Window Requests from tabs
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        if navigationAction.targetFrame == nil {
            print("New tab or window requested: \(navigationAction.request.url?.absoluteString ?? "unknown URL")")
            
            let newWebView = AltoWebView(frame: .zero, configuration: configuration)
            
            // This is for login windows
            if navigationAction.navigationType == .other {
                print("THe browser has requested a login expereicnce")
                //let newTab = AltoTab(webView: newWebView, state: tab?.state ?? AltoState())
                //let tabRep = TabRepresentation(id:newTab.id, index: tab?.mannager?.currentSpace.normal.tabs.count ?? 0)
                //Alto.shared.tabs[newTab.id] = newTab
                
                //tab?.mannager?.currentSpace.normal.appendTabRep(tabRep)
                //tab?.mannager?.currentSpace.currentTab = newTab
                alto.cookieManager.setupCookies(for: newWebView)
            } else if let url = navigationAction.request.url?.absoluteString {
                //let newTab = AltoTab(webView: newWebView, state: tab?.state ?? AltoState())
                //let tabRep = TabRepresentation(id:newTab.id, index: tab?.mannager?.currentSpace.normal.tabs.count ?? 0)
                //Alto.shared.tabs[newTab.id] = newTab
                
                //tab?.mannager?.currentSpace.normal.appendTabRep(tabRep)
                //tab?.mannager?.currentSpace.currentTab = newTab
                alto.cookieManager.setupCookies(for: newWebView)
                
                newWebView.load(navigationAction.request)
            }
            return newWebView
        }
        return nil
    }
    
    // This will handle Tabs using js to close themselves
    func webViewDidClose(_ webView: WKWebView) {
        print("CLOSE")
    }
}
