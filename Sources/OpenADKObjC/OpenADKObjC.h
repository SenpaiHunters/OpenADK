//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
// THIS SHOULD BE IMPORTED FROM ANOTHER FILE BUT IT ISNT WORKING TO DO
#warning move contents of OpenADKObjC to sepereate imported header

//! Project version number for OpenADKObjC.
FOUNDATION_EXPORT double OpenADKObjCVersionNumber;

//! Project version string for OpenADKObjC.
FOUNDATION_EXPORT const unsigned char OpenADKObjCVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <OpenADKObjC/PublicHeader.h>


// The header declares that these are all functions of a the class, exposing them to swiftUI
@interface WKWebsiteDataStore ()
// Enable or disable Intelligent Tracking Prevention (ITP). When ITP is enabled resource load statistics
// are collected and used to decide whether to allow or block third-party cookies and prevent user tracking.
// An example of this is blocking `www.youtube.com` cookies on `youtube.com` urls (BE-3846)
- (BOOL)_resourceLoadStatisticsEnabled;
- (void)_setResourceLoadStatisticsEnabled:(BOOL)enabled;
@end
