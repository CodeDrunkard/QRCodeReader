//
//  DetailViewController.h
//  QRCodeReader
//
//  Created by JT Ma on 30/03/2017.
//  Copyright © 2017 JT Ma. All rights reserved.
//

#import <UIKit/UIKit.h>

#define EnumRawValue(enum) [@[@"AVFoundation", @"ZBar", @"ZXing"] objectAtIndex:enum]

typedef NS_ENUM(NSUInteger, QRCodeReaderType) {
    QRCodeReaderTypeFoundation,
    QRCodeReaderTypeZBar,
    QRCodeReaderTypeZXing,
};

@interface DetailViewController : UIViewController

@property (nonatomic, assign) QRCodeReaderType type;
@property (nonatomic, strong) NSString *typeString;
@property (weak, nonatomic) IBOutlet UILabel *detailDescriptionLabel;

@end

