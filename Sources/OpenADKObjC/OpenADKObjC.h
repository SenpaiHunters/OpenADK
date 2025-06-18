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

@interface WKPreferences ()
-(void)_setFullScreenEnabled:(BOOL)fullScreenEnabled;
-(void)_setAllowsPictureInPictureMediaPlayback:(BOOL)allowed;
-(void)_setBackspaceKeyNavigationEnabled:(BOOL)enabled;
@end

typedef NS_OPTIONS(NSUInteger, _WKMediaMutedState) {
    _WKMediaNoneMuted = 0,
    _WKMediaAudioMuted = 1 << 0,
    _WKMediaCaptureDevicesMuted = 1 << 1,
    _WKMediaScreenCaptureMuted = 1 << 2,
};

@interface WKWebView ()
@property (nonatomic, readonly) BOOL _isInFullscreen;
@property (nonatomic, readonly, nullable) NSString *_MIMEType;
@property (nonatomic, readonly) _WKMediaMutedState _mediaMutedState;

- (void)_setPageMuted:(_WKMediaMutedState)mutedState;

- (void)_setAddsVisitedLinks:(BOOL)addsVisitedLinks;

- (void)_getMainResourceDataWithCompletionHandler:(void (^_Nonnull)(NSData * _Nullable, NSError * _Nullable))completionHandler;

-(CGFloat)_topContentInset;
-(void)_setTopContentInset:(CGFloat)inset;

-(BOOL)_automaticallyAdjustsContentInsets;
-(void)_setAutomaticallyAdjustsContentInsets:(BOOL)enabled;

-(BOOL)_isBeingInspected;
@end

@interface WKWebsiteDataStore ()
// Enable or disable Intelligent Tracking Prevention (ITP). When ITP is enabled resource load statistics
// are collected and used to decide whether to allow or block third-party cookies and prevent user tracking.
// An example of this is blocking `www.youtube.com` cookies on `youtube.com` urls (BE-3846)
- (BOOL)_resourceLoadStatisticsEnabled;
- (void)_setResourceLoadStatisticsEnabled:(BOOL)enabled;
@end

typedef NS_OPTIONS(NSUInteger, _WKCaptureDevices) {
    _WKCaptureDeviceMicrophone = 1 << 0,
    _WKCaptureDeviceCamera = 1 << 1,
    _WKCaptureDeviceDisplay = 1 << 2,
};

@protocol WKUIDelegatePrivate <WKUIDelegate>
- (void)_webView:(WKWebView * _Nonnull)webView getWindowFrameWithCompletionHandler:(void (^_Nonnull)(CGRect))completionHandler;
- (void)_webView:(WKWebView * _Nonnull)webView requestUserMediaAuthorizationForDevices:(_WKCaptureDevices)devices url:(NSURL * _Nonnull)url mainFrameURL:(NSURL * _Nonnull)mainFrameURL decisionHandler:(void (^_Nonnull)(BOOL authorized))decisionHandler;
@end
