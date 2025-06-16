//

import Foundation
import OpenADKObjC
import WebKit

public class Alto {
    
    public init() {
        WKWebsiteDataStore.nonPersistent()._setResourceLoadStatisticsEnabled(false)
        WKWebsiteDataStore.default()._setResourceLoadStatisticsEnabled(false)
    }
}
