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
//    UIBarButtonItem * red = [[UIBarButtonItem alloc]initWithTitle:@"红色" style:UIBarButtonItemStylePlain target:self action:@selector(rightAction:)];
//    UIBarButtonItem * back = [[UIBarButtonItem alloc]initWithTitle:@"后退" style:UIBarButtonItemStylePlain target:self action:@selector(saveAction:)];
//    self.navigationItem.rightBarButtonItems = @[red,back];
//    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"橙色" style:UIBarButtonItemStylePlain target:self action:@selector(leftAction:)];
    UIBarButtonItem * redLine = [[UIBarButtonItem alloc]initWithTitle:@"红色" style:UIBarButtonItemStylePlain target:self action:@selector(redLine:)];
    UIBarButtonItem * greenLine = [[UIBarButtonItem alloc]initWithTitle:@"绿色" style:UIBarButtonItemStylePlain target:self action:@selector(greenLine:)];
    UIBarButtonItem * back = [[UIBarButtonItem alloc]initWithTitle:@"后退" style:UIBarButtonItemStylePlain target:self action:@selector(backword:)];
    UIBarButtonItem * forword = [[UIBarButtonItem alloc]initWithTitle:@"前进" style:UIBarButtonItemStylePlain target:self action:@selector(forword:)];
    UIBarButtonItem * estart = [[UIBarButtonItem alloc]initWithTitle:@"橡皮开始" style:UIBarButtonItemStylePlain target:self action:@selector(eraseStart:)];
    UIBarButtonItem * eend = [[UIBarButtonItem alloc]initWithTitle:@"橡皮结束" style:UIBarButtonItemStylePlain target:self action:@selector(eraseEnd:)];
    self.navigationItem.leftBarButtonItems = @[redLine,greenLine,estart];
    self.navigationItem.rightBarButtonItems = @[back,forword,eend];
    sigView = [[LRSignView alloc]initWithFrame:self.view.bounds];
    [self.view addSubview:sigView];
}

- (void)redLine:(id)sender {
    sigView.lineColor = UIColor.redColor;
}

- (void)greenLine:(id)sender {
    sigView.lineColor = UIColor.greenColor;
}

- (void)backword:(id)sender {
    [sigView backword];
}

- (void)forword:(id)sender {
    [sigView forword];
}

- (void)eraseStart:(id)sender {
    [sigView eraserBegin];
}
- (void)eraseEnd:(id)sender {
    [sigView eraserEnd];
}



@end
