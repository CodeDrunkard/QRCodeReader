//
//  DetailViewController.m
//  QRCodeReader
//
//  Created by JT Ma on 30/03/2017.
//  Copyright © 2017 JT Ma. All rights reserved.
//

#import "DetailViewController.h"

#import "Capture.h"
#import "CapturePreview.h"

#import <ZBarSDK/ZBarCaptureReader.h>

#import "ZXMultiFormatReader.h"
#import "ZXCGImageLuminanceSource.h"
#import "ZXHybridBinarizer.h"
#import "ZXBinaryBitmap.h"
#import "ZXDecodeHints.h"
#import "ZXResult.h"

@interface DetailViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate, ZBarCaptureDelegate>

@property (nonatomic, strong) Capture *capture;
@property (nonatomic, strong) CapturePreview *capturePreview;
@property (nonatomic, strong) AVCaptureVideoDataOutput *captureVideoDataOutput;
@property (nonatomic, strong) AVCaptureMetadataOutput *captureMetadataOutput;

@property (nonatomic, strong) ZBarCaptureReader *zbarReader;

@property (nonatomic, strong) ZXDecodeHints *zxingHints;
@property (nonatomic, strong) id<ZXReader> zxingReader;
@property (nonatomic, assign) CGRect scanRect;

@end

@implementation DetailViewController {
    dispatch_queue_t _captureQueue;
    int _skipCount;
    int _skipMaxCount;
    BOOL _scanEnable;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self initCamera];
    
    _skipCount = 0;
    _skipMaxCount = 3;
    _scanEnable = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    [self checkCaptureSetupResult];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self.capture stop];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    
    [self deinitCamera];
}

- (void)setTypeString:(NSString *)typeString {
    _typeString = typeString;
    if ([_typeString isEqualToString:EnumRawValue(QRCodeReaderTypeFoundation)]) {
        self.type = QRCodeReaderTypeFoundation;
    } else if ([_typeString isEqualToString:EnumRawValue(QRCodeReaderTypeZBar)]) {
        self.type = QRCodeReaderTypeZBar;
    } else if ([_typeString isEqualToString:EnumRawValue(QRCodeReaderTypeZXing)]) {
        self.type = QRCodeReaderTypeZXing;
    }
}

#pragma mark - Camera Config

- (void)initCamera {
    if (!self.capture) {
        _captureQueue = dispatch_queue_create("com.hiscene.jt.captureSesstionQueue", DISPATCH_QUEUE_SERIAL);
        self.capture = [[Capture alloc] initWithSessionPreset:AVCaptureSessionPresetHigh
                                               devicePosition:AVCaptureDevicePositionBack
                                                 sessionQueue:_captureQueue];
        
        self.capturePreview = [[CapturePreview alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.height / 4 * 3, self.view.bounds.size.height)];
        self.capturePreview.center = self.view.center;
        self.capturePreview.session = self.capture.session;
        self.capturePreview.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.capturePreview.backgroundColor = [UIColor blackColor];
        self.capturePreview.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        self.capturePreview.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.view insertSubview:self.capturePreview atIndex:0];
        
        dispatch_async( _captureQueue, ^{
            switch (self.type) {
                case QRCodeReaderTypeFoundation:
                    [self configCaptureMetadataOutput];
                    break;
                case QRCodeReaderTypeZBar:
                    [self initZBar];
                    [self configCaptureVideoDataOutput:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange];
                    break;
                case QRCodeReaderTypeZXing:
                    [self initZXing];
                    [self configCaptureVideoDataOutput:kCVPixelFormatType_32BGRA];
                    break;
            }
        });
    }
}

- (void)configCaptureMetadataOutput {
    if ( self.capture.setupResult != CaptureSetupResultSuccess ) {
        return;
    }
    
    [self.capture.session beginConfiguration];
    
    // Must add output to session before config metadataoutput, otherwise, it doesn't work.
    self.captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    if ([self.capture.session canAddOutput:self.captureMetadataOutput]) {
        [self.capture.session addOutput:self.captureMetadataOutput];
    } else {
#if DEBUG
        NSLog( @"Could not add metadata output to the session" );
#endif
        self.capture.setupResult = CaptureSetupResultSessionConfigurationFailed;
        [self.capture.session commitConfiguration];
        return;
    }
    
    [self.captureMetadataOutput setMetadataObjectsDelegate:self queue:_captureQueue];
    self.captureMetadataOutput.metadataObjectTypes = [NSArray arrayWithObject:AVMetadataObjectTypeQRCode];
    
    [self.capture.session commitConfiguration];
}

- (void)configCaptureVideoDataOutput:(int)pixelBufferPixelFormatTypeKey {
    if ( self.capture.setupResult != CaptureSetupResultSuccess ) {
        return;
    }
    
    [self.capture.session beginConfiguration];
    
    self.captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.captureVideoDataOutput setVideoSettings:[NSDictionary dictionaryWithObject: [NSNumber numberWithInt: pixelBufferPixelFormatTypeKey]
                                                                              forKey: (NSString *)kCVPixelBufferPixelFormatTypeKey]];
    [self.captureVideoDataOutput setSampleBufferDelegate:self queue:_captureQueue];
    
    if ([self.capture.session canAddOutput:self.captureVideoDataOutput]) {
        [self.capture.session addOutput:self.captureVideoDataOutput];
    } else {
#if DEBUG
        NSLog( @"Could not add video device output to the session" );
#endif
        self.capture.setupResult = CaptureSetupResultSessionConfigurationFailed;
        [self.capture.session commitConfiguration];
        return;
    }
    
    /*
     Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
     handled by -[AVCamCameraViewController viewWillTransitionToSize:withTransitionCoordinator:].
     */
    UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
    AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
    if ( statusBarOrientation != UIInterfaceOrientationUnknown ) {
        initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
    }
    self.capturePreview.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation;
    
    AVCaptureConnection *videoConnection = [self.captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    if ([videoConnection isVideoOrientationSupported]) {
        videoConnection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
    }
    
    [self.capture.session commitConfiguration];
}

- (void)checkCaptureSetupResult {
    dispatch_async( _captureQueue, ^{
        switch ( self.capture.setupResult ) {
            case CaptureSetupResultSuccess: {
                // Only setup observers and start the session running if setup succeeded.
                dispatch_async( dispatch_get_main_queue(), ^{
                    [self.capture start];
                });
                break;
            }
            case CaptureSetupResultCameraNotAuthorized: {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = NSLocalizedString( @"The app doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera" );
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    // Provide quick access to Settings.
                    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"Settings", @"Alert button to open Settings" ) style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
                    }];
                    [alertController addAction:settingsAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                });
                break;
            }
            case CaptureSetupResultSessionConfigurationFailed: {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = NSLocalizedString( @"Unable to capture media", @"Alert message when something goes wrong during capture session configuration" );
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                });
                break;
            }
        }
    });
}

- (void)deinitCamera {
    dispatch_async( _captureQueue, ^{
        if (self.capture.setupResult != CaptureSetupResultSuccess) {
            self.capturePreview.session = nil;
            self.capturePreview = nil;
            [self.capture close];
        }
    });
}


#pragma mark - ZBar Configeration

- (void)initZBar {
    self.zbarReader = [[ZBarCaptureReader alloc] init];
    self.zbarReader.captureDelegate = self;
    self.zbarReader.enableReader = YES;
}

#pragma mark - ZXing Configeration

- (void)initZXing {
    self.zxingReader = [ZXMultiFormatReader reader];
    self.zxingHints = [ZXDecodeHints hints];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (_scanEnable) {
        _skipCount++;
        if (_skipCount > _skipMaxCount) {
            _skipCount = 0;
            switch (self.type) {
                case QRCodeReaderTypeZBar: {
                    [(id<AVCaptureVideoDataOutputSampleBufferDelegate>)_zbarReader captureOutput:captureOutput
                                                                           didOutputSampleBuffer:sampleBuffer
                                                                                  fromConnection:connection];
                    break;
                }
                case QRCodeReaderTypeZXing: {
                    @autoreleasepool {
                        
                        CVImageBufferRef videoFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
                        
                        CGImageRef videoFrameImage = [ZXCGImageLuminanceSource createImageFromBuffer:videoFrame];
                        CGImageRef rotatedImage = [self createRotatedImage:videoFrameImage degrees:0];
                        CGImageRelease(videoFrameImage);
                        
                        // If scanRect is set, crop the current image to include only the desired rect
                        if (!CGRectIsEmpty(self.scanRect)) {
                            CGImageRef croppedImage = CGImageCreateWithImageInRect(rotatedImage, self.scanRect);
                            CFRelease(rotatedImage);
                            rotatedImage = croppedImage;
                        }
                        
                        ZXCGImageLuminanceSource *source = [[ZXCGImageLuminanceSource alloc] initWithCGImage:rotatedImage];

                        CGImageRelease(rotatedImage);
                        
                        ZXHybridBinarizer *binarizer = [[ZXHybridBinarizer alloc] initWithSource:source];
                        
                        ZXBinaryBitmap *bitmap = [[ZXBinaryBitmap alloc] initWithBinarizer:binarizer];
                        
                        NSError *error;
                        ZXResult *result = [self.zxingReader decode:bitmap hints:self.zxingHints error:&error];
                        if (result && error == nil) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                NSLog(@"ZXing scan result is: %@", result.text);
                            });
                        }
                    }
                    break;
                }
                default:
                    break;
            }
        }
    }
}

- (CGImageRef)createRotatedImage:(CGImageRef)original degrees:(float)degrees CF_RETURNS_RETAINED {
    if (degrees == 0.0f) {
        CGImageRetain(original);
        return original;
    } else {
        double radians = degrees * M_PI / 180;
        
#if TARGET_OS_EMBEDDED || TARGET_IPHONE_SIMULATOR
        radians = -1 * radians;
#endif
        
        size_t _width = CGImageGetWidth(original);
        size_t _height = CGImageGetHeight(original);
        
        CGRect imgRect = CGRectMake(0, 0, _width, _height);
        CGAffineTransform __transform = CGAffineTransformMakeRotation(radians);
        CGRect rotatedRect = CGRectApplyAffineTransform(imgRect, __transform);
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL,
                                                     rotatedRect.size.width,
                                                     rotatedRect.size.height,
                                                     CGImageGetBitsPerComponent(original),
                                                     0,
                                                     colorSpace,
                                                     kCGBitmapAlphaInfoMask & kCGImageAlphaPremultipliedFirst);
        CGContextSetAllowsAntialiasing(context, FALSE);
        CGContextSetInterpolationQuality(context, kCGInterpolationNone);
        CGColorSpaceRelease(colorSpace);
        
        CGContextTranslateCTM(context,
                              +(rotatedRect.size.width/2),
                              +(rotatedRect.size.height/2));
        CGContextRotateCTM(context, radians);
        
        CGContextDrawImage(context, CGRectMake(-imgRect.size.width/2,
                                               -imgRect.size.height/2,
                                               imgRect.size.width,
                                               imgRect.size.height),
                           original);
        
        CGImageRef rotatedImage = CGBitmapContextCreateImage(context);
        CFRelease(context);
        
        return rotatedImage;
    }
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    // Check if the metadataObjects array is not nil and it contains at least one object.
    if (metadataObjects == nil || metadataObjects.count == 0) {
        return;
    }
    
    AVMetadataMachineReadableCodeObject *metadataObject = metadataObjects.firstObject;
    if ([AVMetadataObjectTypeQRCode isEqualToString:metadataObject.type]) {
        NSString *value = metadataObject.stringValue;
        NSLog(@"AVFoundation scan result is: %@", value);
    }
}


#pragma mark - ZBarCaptureDelegate

- (void)captureReader:(ZBarCaptureReader *)captureReader didReadNewSymbolsFromImage:(ZBarImage *)image {
    for (ZBarSymbol *sym in captureReader.scanner.results) {
        NSLog(@"ZBar scan result is : %@", sym.data);
    }
}

- (void)captureReader:(ZBarCaptureReader *)captureReader didTrackSymbols:(ZBarSymbolSet *)symbols {
    for (ZBarSymbol *sym in symbols) {
        NSLog(@"ZBar scan result is : %@", sym.data);
    }
}


@end
