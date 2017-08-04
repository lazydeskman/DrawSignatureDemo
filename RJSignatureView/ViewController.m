//
//  ViewController.m
//  RJSignatureView
//
//  Created by WangAn on 2017/7/25.
//  Copyright © 2017年 WangAn. All rights reserved.
//

#import "ViewController.h"
#import "LRSignView.h"
@interface ViewController ()
{
    LRSignView * sigView;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationController.navigationBar.barTintColor = UIColor.blackColor;
    UIBarButtonItem * era = [[UIBarButtonItem alloc]initWithTitle:@"红色" style:UIBarButtonItemStylePlain target:self action:@selector(rightAction:)];
    UIBarButtonItem * save = [[UIBarButtonItem alloc]initWithTitle:@"黑色" style:UIBarButtonItemStylePlain target:self action:@selector(saveAction:)];
    self.navigationItem.rightBarButtonItems = @[era,save];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"橙色" style:UIBarButtonItemStylePlain target:self action:@selector(leftAction:)];

    
    
    sigView = [[LRSignView alloc]initWithFrame:self.view.bounds];
    [self.view addSubview:sigView];
}

- (void)rightAction:(id)sender {
    sigView.lineColor = UIColor.redColor;
}

- (void)leftAction:(id)sender {
    sigView.lineColor = UIColor.orangeColor;
}

- (void)saveAction:(id)sender {
//    sigView.lineColor = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.0f];
    
//    CGFloat width = (arc4random() % 20 ) / 1000.f;
//    sigView.lineWidth = width;
    
    [sigView backword];
}



@end
