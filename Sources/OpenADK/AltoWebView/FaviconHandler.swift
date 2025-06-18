//
import WebKit

public class FaviconHandler {
    
    func getFavicon(_ webView: WKWebView) -> NSImage? {
        var nsImage: NSImage?
        
        webView.evaluateJavaScript(
            "document.querySelector(\"link[rel~='icon']\")?.href"
        ) { result, error in
            if let value = result as? String {
                print("VALUE: ", value)
                print("Favicon URL from JS:", value)
                nsImage = self.downloadFavicon(from: value)
            } else {
                if let host = webView.url?.host {
                    let fallbackFavicon = "https://\(host)/favicon.ico"
                    print("Using fallback favicon:", fallbackFavicon)
                    nsImage =  self.downloadFavicon(from: fallbackFavicon)
                }
            }
        }
        return nsImage
    }

    func downloadFavicon(from urlString: String) -> NSImage? {
        var nsImage: NSImage?
        
        guard let url = URL(string: urlString) else { return nil }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    nsImage = image
                }
            }
        }.resume()
        return nsImage
    }
}
