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

@interface DetailViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate, ZBarCaptureDelegate>

@property (nonatomic, strong) Capture *capture;
@property (nonatomic, strong) CapturePreview *capturePreview;
@property (nonatomic, strong) AVCaptureVideoDataOutput *captureVideoDataOutput;
@property (nonatomic, strong) AVCaptureMetadataOutput *captureMetadataOutput;

@property (nonatomic, strong) ZBarCaptureReader *zbarReader;

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
    if ([_typeString isEqualToString:EnumRawValue(QRCodeReaderTypeNative)]) {
        self.type = QRCodeReaderTypeNative;
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
        [self.view insertSubview:self.capturePreview atIndex:0];
        self.capturePreview.backgroundColor = [UIColor blackColor];
        
        dispatch_async( _captureQueue, ^{
            switch (self.type) {
                case QRCodeReaderTypeNative:
                    [self configCaptureMetadataOutput];
                    break;
                case QRCodeReaderTypeZBar:
                    [self initZBar];
                    [self configCaptureVideoDataOutput];
                    break;
                case QRCodeReaderTypeZXing:
                    
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

- (void)configCaptureVideoDataOutput {
    if ( self.capture.setupResult != CaptureSetupResultSuccess ) {
        return;
    }
    
    [self.capture.session beginConfiguration];
    
    self.captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.captureVideoDataOutput setVideoSettings:[NSDictionary dictionaryWithObject: [NSNumber numberWithInt: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
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


#pragma mark - ZBar config

- (void)initZBar {
    self.zbarReader = [[ZBarCaptureReader alloc] init];
    self.zbarReader.captureDelegate = self;
    self.zbarReader.enableReader = YES;
    
    _skipCount = 0;
    _skipMaxCount = 3;
    _scanEnable = YES;
}


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (_scanEnable && self.type == QRCodeReaderTypeZBar) {
        _skipCount++;
        if (_skipCount > _skipMaxCount) {
            _skipCount = 0;
            [(id<AVCaptureVideoDataOutputSampleBufferDelegate>)_zbarReader captureOutput:captureOutput
                                                                   didOutputSampleBuffer:sampleBuffer
                                                                          fromConnection:connection];
        }
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
