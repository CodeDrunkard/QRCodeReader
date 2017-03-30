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

@interface DetailViewController () <AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) Capture *capture;
@property (nonatomic, strong) CapturePreview *capturePreview;
@property (nonatomic, strong) AVCaptureMetadataOutput *captureMetadataOutput;

@end

@implementation DetailViewController {
    dispatch_queue_t _captureQueue;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self initCamera];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self checkCaptureSetupResult];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self.capture stop];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    [self deinitCamera];
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
            [self configCaptureMetadataOutput];
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
            [self.capture.session removeOutput:self.captureMetadataOutput];
            self.captureMetadataOutput = nil;
            self.capturePreview.session = nil;
            self.capturePreview = nil;
            [self.capture close];
        }
    });
}


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // do some things, like get sreenshot.
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
        NSLog(@"metadataObject value: %@", value);
    }
}


@end
