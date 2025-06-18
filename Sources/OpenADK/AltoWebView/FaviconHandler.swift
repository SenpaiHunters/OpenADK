//
import WebKit

public class FaviconHandler {
    func getFavicon(_ webView: WKWebView) -> NSImage? {
        var nsImage: NSImage?

        webView.evaluateJavaScript(
            "document.querySelector(\"link[rel~='icon']\")?.href"
        ) { result, _ in
            if let value = result as? String {
                nsImage = self.downloadFavicon(from: value)
            } else {
                if let host = webView.url?.host {
                    let fallbackFavicon = "https://\(host)/favicon.ico"
                    nsImage = self.downloadFavicon(from: fallbackFavicon)
                }
            }
        }
        return nsImage
    }

    func downloadFavicon(from urlString: String) -> NSImage? {
        var nsImage: NSImage?

        guard let url = URL(string: urlString) else { return nil }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    nsImage = image
                }
            }
        }.resume()
        return nsImage
    }
}
