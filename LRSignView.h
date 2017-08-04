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
 橡皮擦宽度,默认为 0.1
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
 */
- (void)backword;
/**
 前进(前进一步)
 */
- (void)forword;

/**
 获取签名数据
 @return 签名数据
 */
- (NSData*)signBufferData;
/**
 从文件读取签名并显示
 @param filePath 文件路径
 @return YES文件存在并有数据,NO文件不存或为空
 */
- (BOOL)displaySignatureFromFile:(NSString*)filePath;
@end
