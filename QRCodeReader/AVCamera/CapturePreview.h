//
//  CapturePreview.h
//  CaptureManager
//
//  Created by JT Ma on 25/03/2017.
//  Copyright © 2017 JT Ma. All rights reserved.
//

@import AVFoundation;
@import UIKit;

@interface CapturePreview : UIView

@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *videoPreviewLayer;
@property (nonatomic) AVCaptureSession *session;

@end
