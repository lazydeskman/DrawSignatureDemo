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
    
    UIImageView * imageView;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.view.backgroundColor = UIColor.lightGrayColor;
    self.navigationController.navigationBar.barTintColor = UIColor.blackColor;
    UIBarButtonItem * line = [[UIBarButtonItem alloc]initWithTitle:@"线条" style:UIBarButtonItemStylePlain target:self action:@selector(randomLineWidth:)];
    UIBarButtonItem * color = [[UIBarButtonItem alloc]initWithTitle:@"颜色" style:UIBarButtonItemStylePlain target:self action:@selector(randomLineColor:)];
    UIBarButtonItem * back = [[UIBarButtonItem alloc]initWithTitle:@"后退" style:UIBarButtonItemStylePlain target:self action:@selector(backwordInput:)];
    UIBarButtonItem * forword = [[UIBarButtonItem alloc]initWithTitle:@"前进" style:UIBarButtonItemStylePlain target:self action:@selector(forwordInput:)];
    UIBarButtonItem * eraS = [[UIBarButtonItem alloc]initWithTitle:@"擦除" style:UIBarButtonItemStylePlain target:self action:@selector(eraseStart:)];
    UIBarButtonItem * eraE = [[UIBarButtonItem alloc]initWithTitle:@"手写" style:UIBarButtonItemStylePlain target:self action:@selector(eraseEnd:)];
    UIBarButtonItem * im = [[UIBarButtonItem alloc]initWithTitle:@"图" style:UIBarButtonItemStylePlain target:self action:@selector(displaySignature:)];
    self.navigationItem.leftBarButtonItems = @[line,color,back,im];
    self.navigationItem.rightBarButtonItems = @[forword,eraS,eraE];
    sigView = [[LRSignView alloc]initWithFrame:self.view.bounds];
    [self.view addSubview:sigView];
    
}
//随机线条颜色
- (void)randomLineColor:(id)sender {
    UIColor * color = [UIColor colorWithRed:(arc4random()%256)/255.f green:(arc4random()%256)/255.f blue:(arc4random()%256)/255.f alpha:(arc4random()%256)/255.f];
    sigView.lineColor = color;
}
//随机线条宽度
- (void)randomLineWidth:(id)sender {
    CGFloat width = (arc4random()%10)/1000.f;
    sigView.lineWidth = width;
}
//撤销
- (void)backwordInput:(id)sender {
    [sigView backword];
}
//前进
- (void)forwordInput:(id)sender {
    [sigView forword];
}
//擦除
- (void)eraseStart:(id)sender {
    [sigView eraserBegin];
}
//结束擦除
- (void)eraseEnd:(id)sender {
    [sigView eraserEnd];
}
//获取签名图片并显示
- (void)displaySignature:(id)sender {
    if (!imageView) {
        imageView = [[UIImageView alloc]initWithFrame:self.view.bounds];
        imageView.backgroundColor = UIColor.clearColor;
        [self.view addSubview:imageView];
        imageView.image = [sigView signatureImage];
        sigView.hidden = YES;
    }
}
@end
