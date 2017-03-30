//
//  Capture.h
//  CaptureManager
//
//  Created by JT Ma on 25/03/2017.
//  Copyright © 2017 JT Ma. All rights reserved.
//

@import AVFoundation;

typedef NS_ENUM( NSInteger, CaptureSetupResult ) {
    CaptureSetupResultSuccess,
    CaptureSetupResultCameraNotAuthorized,
    CaptureSetupResultSessionConfigurationFailed
};

@interface Capture : NSObject

@property (nonatomic, assign, readwrite) AVCaptureDevicePosition position;
@property (nonatomic, strong, readonly) AVCaptureSession *session;
@property (nonatomic, copy, readonly) NSString *sessionPreset;
@property (nonatomic, assign, readwrite) CaptureSetupResult setupResult;

@property (nonatomic, assign, readwrite) NSInteger activeVideoFrame;

@property (nonatomic, assign, readwrite) AVCaptureFlashMode flashMode;
@property (nonatomic, assign, readwrite) AVCaptureTorchMode torchMode;
@property (nonatomic, assign, readwrite) AVCaptureFocusMode focusMode;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSessionPreset:(NSString *)sessionPreset
                       devicePosition:(AVCaptureDevicePosition)position
                         sessionQueue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;

- (void)start;
- (void)stop;
- (void)close;

@end
