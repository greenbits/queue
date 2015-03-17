//
//  EDViewController.h
//  queue
//
//  Created by Andrew Sliwinski on 6/29/12.
//  Copyright (c) 2012 Andrew Sliwinski. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "EDQueue.h"

@interface EDViewController : UIViewController

@property (nonatomic, retain) IBOutlet UITextView *activity;
@property (weak, nonatomic) IBOutlet UILabel *runningLabel;
@property (weak, nonatomic) IBOutlet UILabel *activeLabel;
@property (weak, nonatomic) IBOutlet UILabel *staleLabel;

- (IBAction)addSuccess:(id)sender;
- (IBAction)addFail:(id)sender;
- (IBAction)addCritical:(id)sender;

@end