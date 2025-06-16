#import <WebKit/WebKit.h>
#import <Foundation/Foundation.h>


// This code comes from Beam's system: https://github.com/beamlegacy/beam

// The header declares that these are all functions of a the class, exposing them to swiftUI
@interface WKWebsiteDataStore ()
// Enable or disable Intelligent Tracking Prevention (ITP). When ITP is enabled resource load statistics
// are collected and used to decide whether to allow or block third-party cookies and prevent user tracking.
// An example of this is blocking `www.youtube.com` cookies on `youtube.com` urls (BE-3846)
- (BOOL)_resourceLoadStatisticsEnabled;
- (void)_setResourceLoadStatisticsEnabled:(BOOL)enabled;
@end
