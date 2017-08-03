//
//  LRSignView.h
//  RJSignatureView
//
//  Created by WangAn on 2017/8/1.
//  Copyright © 2017年 WangAn. All rights reserved.
//

#import <GLKit/GLKit.h>

@interface LRSignView : GLKView
/**
 线条颜色,默认为(r:0.0,g:0.0,b:0.0,a:1.0)黑
 */
@property (strong, nonatomic) UIColor * lineColor;
/**
 线条宽度,默认为0.007
 */
@property (assign, nonatomic) CGFloat lineWidth;
/**
 橡皮擦宽度,默认为
 */
@property (assign, nonatomic) CGFloat eraserWidth;
/**
 开始擦除
 */
- (void)eraserBegin;
/**
 擦除结束
 */
- (void)eraserEnd;
/**
 撤销(后退一步)
 @return YES可以撤销,NO没有内容可以撤销
 */
- (BOOL)backword;
/**
 前进(前进一步)
 @return YES可以前进,NO没有内容可以前进
 */
- (BOOL)forword;
@end
