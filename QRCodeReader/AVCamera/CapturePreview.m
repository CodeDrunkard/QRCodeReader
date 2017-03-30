//
//  CapturePreview.m
//  CaptureManager
//
//  Created by JT Ma on 25/03/2017.
//  Copyright © 2017 JT Ma. All rights reserved.
//

#import "CapturePreview.h"

@implementation CapturePreview

+ (Class)layerClass {
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureVideoPreviewLayer *)videoPreviewLayer {
    return (AVCaptureVideoPreviewLayer *)self.layer;
}

- (AVCaptureSession *)session {
    return self.videoPreviewLayer.session;
}

- (void)setSession:(AVCaptureSession *)session {
    if (!self.videoPreviewLayer.session) {
        self.videoPreviewLayer.session = session;
    }
}

@end
