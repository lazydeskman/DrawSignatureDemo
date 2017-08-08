//
//  LRSignView.m
//  RJSignatureView
//
//  Created by WangAn on 2017/8/1.
//  Copyright © 2017年 WangAn. All rights reserved.
//

#import "LRSignView.h"
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
/*
 这个枚举的作用,记录上次的操作类型,write 用于手写和擦除,word用于撤销和前进  的状态标注
 */
typedef NS_ENUM(NSUInteger, LRHandleState) {
    LRHandleStateWrite = 0,
    LRHandleStateWord = 1,
};

//定义每个点的数据结构(位置x,y,z(0.0),颜色r,g,b,a)
typedef struct {
    GLKVector3 position;//{x,y,z(1.0)}
    GLKVector4 color;//{r,g,b,a}
}LRSignPoint;




//控制点
static inline CGPoint QuadraticPointInCurve(CGPoint start,CGPoint end,CGPoint controlPoint,float percent){
    double a = pow((1.0 - percent), 2.0);
    double b = 2.0 * percent * (1.0 - percent);
    double c = pow(percent, 2.0);
    return CGPointMake(a * start.x + b * controlPoint.x + c * end.x, a * start.y + b * controlPoint.y + c * end.y);
}
//随机数
static inline float generateRandom(float from,float to){
    return random() % 10000 / 10000.0 * (to - from) + from;
}
//比较
static inline float clamp(float min, float max, float value){
    return fmaxf(min, fminf(max, value));
}
//垂线
static inline GLKVector3 perpendicular(LRSignPoint p1, LRSignPoint p2){
    
    return  GLKVector3Make(p2.position.y - p1.position.y,-1 * (p2.position.x - p1.position.x), 0);
}
//坐标转换
static inline LRSignPoint ViewPointToGL(CGPoint viewPoint,CGRect bounds,GLKVector4 color){
    return (LRSignPoint) {
        {
            (viewPoint.x / bounds.size.width * 2.0 - 1),
            ((viewPoint.y / bounds.size.height) * 2.0 - 1) * -1,
            0
        },
        color
    };
    
}

/*
 我想在能想到的点数据保存方式有两种:
 一、直接使用glGenBuffer申请一个最大GPU空间,每次新的顶点 通过glMap获取指定位置,写入数据
 优势:单次写入数据量小
 缺点:如果顶点数目超过最大数,就不能能再写入数据了
 二、CPU保存顶点数据,每次产生新的顶点后,通过glBufferData重新写入保存的所有顶点数据
 优势:不会受限于一的方式申请的最大数
 缺点:每次写入的顶点数据会随着顶点数的增加而增加
 我选择第二种方式 理由:嗯 我定义的一个点的大小是32个字节  200W个点的话大概只有61MB,应该对于性能应该没有屁的影响
 */

@interface LRSignView () <GLKViewDelegate>
{
    GLuint lineBuffer;//线条缓冲句柄
    GLuint lineArray;//线条缓冲区
    uint lineLength;//线条长度
    float currentThickness;//线条宽度
    float previousThickness;//上次线条宽度
    float stroke_width_max;//线条最宽处的宽度
    float stroke_width_min;//线条最窄处的宽度
    float stroke_width_smooth;//线条平滑值
    float velocity_clamp_max;//速度上限
    float velocity_clamp_min;//速度下限
    float quadratic_distance_tolerance;//拆分距离
    GLKVector4 vertex_color;//顶点颜色(线条/点颜色,绘制颜色)
    GLKVector4 clear_color;//清除颜色glClear用来清除颜色缓冲
    CGPoint previousPoint;//上一个点
    CGPoint previousMidPoint;//上一个重点
    LRSignPoint previousVertex;//上一个顶点数据
    NSMutableData * lineData;//保存线条 顶点数据
    float eraser_width;//橡皮宽度
    BOOL isErasing;//是否正在擦除
    NSMutableArray * indexRecords;//记录位置,点击(滑动)结束时需要draw到的index
    LRHandleState lastHandleState;//记录上次的操作类型
}
@end


@implementation LRSignView


- (instancetype)initWithFrame:(CGRect)frame {
    EAGLContext * context = [[EAGLContext alloc]initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (context != nil) {
        return [self initWithFrame:frame context:context];
    }
    return nil;
}

- (instancetype)initWithFrame:(CGRect)frame context:(EAGLContext *)context {
    self = [super initWithFrame:frame context:context];
    if (self) {
        self.delegate = self;
        [self commonInit];
    }
    return self;
}

/**
 初始化
 */
- (void)commonInit {

    self.backgroundColor = UIColor.clearColor;
    self.drawableMultisample = GLKViewDrawableMultisample4X;
    self.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    [EAGLContext setCurrentContext:self.context];
    glDisable(GL_DEPTH_TEST);//不进行深度测试
    [self initParameters];
    [self compileShaderAndProgram];//编译着色器/程序
    [self generateLineBufferData];//初始化用来画线条的缓冲
    [self configGesutreRecognizeies];//初始化手势
}

/**
 初始化参数
 */
- (void)initParameters {
    currentThickness = 0.007;
    stroke_width_min = 0.002;
    stroke_width_max = 0.011;
    stroke_width_smooth = 0.5;
    velocity_clamp_min = 10.0;
    velocity_clamp_max = 8000.0;
    quadratic_distance_tolerance = 1.5;
    lineLength = 0;
    previousPoint = CGPointMake(-100, 0);
    lineData = [NSMutableData data];
    vertex_color = GLKVector4Make(0.0, 0.0, 0.0, 1.0);
    clear_color = GLKVector4Make(0.0, 0.0, 0.0, 0.0);
    indexRecords = @[].mutableCopy;
    lastHandleState = LRHandleStateWrite;
    isErasing = NO;
    _lineColor = UIColor.blackColor;
    _lineWidth = 0.007;
    _eraserWidth = 0.1;
}

/**
 编译 顶点/片段着色器和程序
 */
- (void)compileShaderAndProgram {
    //应该从文件读取顶点和判断着色器会比较好
    //顶点着色器
    char vShaderStr[] =     "#version 300 es                          \n"
                            "layout(location = 0) in vec4 vPosition;  \n"
                            "layout(location = 1) in vec4 aColor;     \n"
                            "out vec4 v_Color;                        \n"
                            "void main()                              \n"
                            "{                                        \n"
                            "   gl_Position = vPosition;              \n"
                            "   v_Color = aColor;                     \n"
                            "}                                        \n";
    //片段着色器
    char fShaderStr[] =     "#version 300 es                              \n"
                            "precision mediump float;                     \n"
                            "in vec4 v_Color;                             \n"
                            "out vec4 fragColor;                          \n"
                            "void main()                                  \n"
                            "{                                            \n"
                            "   fragColor = v_Color;                      \n"
                            "}                                            \n";
    GLint linked;
    GLuint vShader = loadShader(GL_VERTEX_SHADER, vShaderStr);
    GLuint fShader = loadShader(GL_FRAGMENT_SHADER, fShaderStr);
    GLuint programObj = glCreateProgram();
    glAttachShader(programObj, vShader);
    glAttachShader(programObj, fShader);
    glLinkProgram(programObj);
    glGetProgramiv(programObj, GL_LINK_STATUS, &linked);
    if (linked == 0) {
        GLint infoLen = 0;
        glGetProgramiv(programObj, GL_INFO_LOG_LENGTH, &infoLen);//获取log长度
        if (infoLen > 0) {
            char * infoLog = malloc(sizeof(char*)*infoLen);
            glGetProgramInfoLog(programObj, infoLen, NULL, infoLog);//获取log
            NSLog(@"Link Program Failured : %s",infoLog);//打印log
            free(infoLog);
        }
        glDeleteProgram(programObj);
    }
    glDeleteShader(vShader);//标记顶点着色器可删除
    glDeleteShader(fShader);//标记片段着色器可删除
    glUseProgram(programObj);//使用程序
    
}

/**
 生成着色器,根据参数返回着色器id(成功)或者0(失败)
 @param type 需要生成的着色器类型
 @param shaderSrc 着色器源码
 @return 着色器
 */
GLuint loadShader(GLenum type, const char * shaderSrc){
    GLuint shader;
    GLint compiled;
    GLchar infoLog[512];//懒得获取info长度 直接给定个512来获取
    shader = glCreateShader(type);//创建type类型着色器,顶点/片段 着色器
    if (shader==0) {
        NSLog(@"create shader failure");
        __builtin_trap();//自动断点
        return 0;
    }
    glShaderSource(shader, 1, &shaderSrc, NULL);//链接着色器源码到这个着色器
    glCompileShader(shader);//编译着色器
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);//检查着色器编译状态是否成功
    if (compiled==0) {//着色器编译失败
        glGetShaderInfoLog(shader, 512, NULL, infoLog);//获取失败log并打印
        NSLog(@"compile shader failure >>> %s",infoLog);//打印
        glDeleteShader ( shader );//删除着色器
        __builtin_trap();//自动断点
    }
    return shader;
}


/**
 生成线条缓冲
 */
- (void)generateLineBufferData {
    glGenVertexArrays(1, &lineArray);//生成顶点数组对象
    glBindVertexArray(lineArray);//绑定顶点数组对象
    glGenBuffers(1, &lineBuffer);//生成顶点缓冲区对象
    glBindBuffer(GL_ARRAY_BUFFER, lineBuffer);//绑定顶点缓冲区对象
    [self bindVertexAttribute];//绑定属性
    glBindVertexArray(0);//解除缓冲对象绑定
    glViewport(0, 0, self.bounds.size.width, self.bounds.size.height);//设置视口
}

/**
 启动顶点属性
 */
- (void)bindVertexAttribute {
    //在我的顶点着色器中一共规定了2个in属性,在这里启用这2个属性
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(LRSignPoint), (GLvoid*)NULL);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(LRSignPoint), (GLvoid*)NULL+offsetof(LRSignPoint, color));
    glEnableVertexAttribArray(1);
}

/**
 配置手势,tap,pan
 */
- (void)configGesutreRecognizeies {
    //点击
    UITapGestureRecognizer * tap  = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapAction:)];
    [self addGestureRecognizer:tap];
    //滑动
    UIPanGestureRecognizer * pan = [[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panAction:)];
    pan.maximumNumberOfTouches = pan.minimumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];
}
/**
 点击手势回调
 @param tap 点击
 */
- (void)tapAction:(UITapGestureRecognizer*)tap {
    CGPoint location = [tap locationInView:self];
    if (tap.state == UIGestureRecognizerStateRecognized) {
        [self checkLasHandleState];
        glBindBuffer(GL_ARRAY_BUFFER, lineBuffer);
        LRSignPoint touchPoint = ViewPointToGL(location, self.bounds,vertex_color);
        [lineData appendBytes:&touchPoint length:sizeof(LRSignPoint)];
        LRSignPoint centerPoint = touchPoint;
        centerPoint.color = vertex_color;
        [lineData appendBytes:&centerPoint length:sizeof(LRSignPoint)];
        static int segments = 15;
        GLKVector2 radius = (GLKVector2){
            clamp(0.00001, 0.02, currentThickness * generateRandom(0.5, 1.5)),
            clamp(0.00001, 0.02, currentThickness * generateRandom(0.5, 1.5))
        };
        GLKVector2 velocityRadius = radius;
        float angle = 0;
        
        for (int i = 0; i <= segments; i++) {
            
            LRSignPoint p = centerPoint;
            p.color = GLKVector4Make(vertex_color.r, vertex_color.g, vertex_color.b, vertex_color.a*stroke_width_smooth);
            p.position.x += velocityRadius.x * cosf(angle);
            p.position.y += velocityRadius.y * sinf(angle);
            [lineData appendBytes:&p length:sizeof(LRSignPoint)];
            [lineData appendBytes:&centerPoint length:sizeof(LRSignPoint)];
            lineLength += 2;
            angle += M_PI * 2.0 / segments;
        }
        [lineData appendBytes:&touchPoint length:sizeof(LRSignPoint)];
        lineLength += 3;
        [self updateLineBuffer];
        [indexRecords addObject:[NSNumber numberWithUnsignedInt:lineLength]];
        
    }
    [self setNeedsDisplay];
}

/**
 滑动手势回调
 @param pan 滑动
 */
- (void)panAction:(UIPanGestureRecognizer*)pan {
    glBindBuffer(GL_ARRAY_BUFFER, lineBuffer);
    
    CGPoint velocity = [pan velocityInView:self];
    CGPoint location = [pan locationInView:self];
    
    float distance = 0.;
    if (previousPoint.x > 0) {
        distance = sqrtf((location.x - previousPoint.x) * (location.x - previousPoint.x) + (location.y - previousPoint.y) * (location.y - previousPoint.y));
    }
    
    float velocityMagnitude = sqrtf(velocity.x*velocity.x + velocity.y*velocity.y);
    float clampedVelocityMagnitude = clamp(velocity_clamp_min, velocity_clamp_max, velocityMagnitude);
    float normalizedVelocity = (clampedVelocityMagnitude - velocity_clamp_min) / (velocity_clamp_max - velocity_clamp_min);
    
    float lowPassFilterAlpha = stroke_width_smooth;
    float newThickness = (stroke_width_max - stroke_width_min) * (1 - normalizedVelocity) + stroke_width_min;
    currentThickness = currentThickness * lowPassFilterAlpha + newThickness * (1 - lowPassFilterAlpha);
    
    if ([pan state] == UIGestureRecognizerStateBegan) {
        [self checkLasHandleState];
        previousPoint = location;
        previousMidPoint = location;
        
        LRSignPoint startPoint = ViewPointToGL(location, self.bounds, vertex_color);
        previousVertex = startPoint;
        previousThickness = currentThickness;
        [lineData appendBytes:&startPoint length:sizeof(LRSignPoint)];
        [lineData appendBytes:&previousVertex length:sizeof(LRSignPoint)];
        lineLength += 2;
        
    } else if ([pan state] == UIGestureRecognizerStateChanged) {
        
        CGPoint mid = CGPointMake((location.x + previousPoint.x) / 2.0, (location.y + previousPoint.y) / 2.0);
        
        if (distance > quadratic_distance_tolerance) {
            //切成片段
            unsigned int i;
            
            int segments = (int) distance / 1.5;
            
            float startPenThickness = previousThickness;
            float endPenThickness = currentThickness;
            previousThickness = currentThickness;
            
            for (i = 0; i < segments; i++)
            {
                currentThickness = startPenThickness + ((endPenThickness - startPenThickness) / segments) * i;
                
                CGPoint quadPoint = QuadraticPointInCurve(previousMidPoint, mid, previousPoint, (float)i / (float)(segments));
                
                LRSignPoint v = ViewPointToGL(quadPoint, self.bounds, vertex_color);
                [self addTriangleStripPointsForPrevious:previousVertex next:v];
                
                previousVertex = v;
            }
        } else if (distance > 1.0) {
            
            LRSignPoint v = ViewPointToGL(location, self.bounds, vertex_color);
            [self addTriangleStripPointsForPrevious:previousVertex next:v];
            previousVertex = v;
            previousThickness = currentThickness;
        }
        
        previousPoint = location;
        previousMidPoint = mid;
        
    } else if (pan.state == UIGestureRecognizerStateEnded | pan.state == UIGestureRecognizerStateCancelled) {
        
        LRSignPoint v = ViewPointToGL(location, self.bounds, vertex_color);
        [lineData appendBytes:&v length:sizeof(LRSignPoint)];
        lineLength++;
        previousVertex = v;
        [lineData appendBytes:&previousVertex length:sizeof(LRSignPoint)];
        lineLength++;
        [indexRecords addObject:[NSNumber numberWithUnsignedInt:lineLength]];
    }
    [self updateLineBuffer];
    [self setNeedsDisplay];
}

/**
 更新线条的顶点数据
 */
- (void)updateLineBuffer {
    //把数据复制到顶点缓冲区
    glBufferData(GL_ARRAY_BUFFER, lineData.length, lineData.bytes, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}
//切断线条成小段,画三角形
- (void)addTriangleStripPointsForPrevious:(LRSignPoint)previous next:(LRSignPoint)next {
    float toTravel = currentThickness / 2.0;
    
    for (int i = 0; i < 2; i++) {
        GLKVector3 p = perpendicular(previous, next);
        GLKVector3 p1 = next.position;
        GLKVector3 ref = GLKVector3Add(p1, p);
        
        float distance = GLKVector3Distance(p1, ref);
        float difX = p1.x - ref.x;
        float difY = p1.y - ref.y;
        float ratio = -1.0 * (toTravel / distance);
        
        difX = difX * ratio;
        difY = difY * ratio;
        
        LRSignPoint stripPoint = {
            { p1.x + difX, p1.y + difY, 0.0 },
            vertex_color
        };
        [lineData appendBytes:&stripPoint length:sizeof(LRSignPoint)];
        lineLength++;
        toTravel *= -1;
    }
}

/**
 检验上次操作
 */
- (void)checkLasHandleState {
    /*
     想象一个当前的情形,一共画了五个点 [A,B,C,D,E] 当前是E点,撤销 回到 D 当前屏幕上有四个点, 这个时候如果继续手写,那么F 点是会被加载E后面的,这个时候 如果绘制五个点 那么F没画出来, 如果画六个点 那么E又出来了,所以我在这里简单判断一下,因为没有想到其他的好办法,手势开始是 我判断一下 上次操作,如果是前进/后退的操作, 但是当前需要添加新的绘制目标了,所以清除掉当前 前进/后退 位置 后面的数据并将新的数据添加到这个位置后面, 也就是 把E 删除 数组变成[A,B,C,D]然后将F添加[A,B,C,D,F]
     */
    if (lastHandleState == LRHandleStateWord) {
        [self verifyDataBuffer];
        lastHandleState = LRHandleStateWrite;
    }
}

/**
 对比位置如果有需要则清除部分顶点数据和记录点数据
 */
- (void)verifyDataBuffer {
    /*
     适用情景,用户手写,记录顶点,用户一共操作 0-5 步, indexRecord记录了这 0-5 步, 用户撤销输入一次, 这个时候 需要绘制的步骤 实际是 0-4步,如果改变lineLength到4 绘制是可以的,如果用户继续操作,顶点数据被写入的实际是6位置,所以 我需要在操作开始前判断下,在这个操作之前的操作是
     */
    if (indexRecords.count) {
        NSNumber * num = [NSNumber numberWithUnsignedInt:lineLength];
        NSUInteger index = [indexRecords indexOfObject:num];
        NSUInteger total = [indexRecords count];
        if (lineLength!=0) {
            if (index != total-1) {
                [indexRecords removeObjectsInRange:NSMakeRange(index+1, total-index-1)];
                NSUInteger len = lineLength * sizeof(LRSignPoint);
                //怎么都算不对位置,妈的,不取了,直接取子数据
                lineData = [NSMutableData dataWithData:[lineData subdataWithRange:NSMakeRange(0, len)]];
            }
        }else{
            [indexRecords removeAllObjects];
            lineData = [NSMutableData data];
        }
    }
}

/**
 设置线条颜色
 @param lineColor 颜色
 */
- (void)setLineColor:(UIColor *)lineColor {
    _lineColor = lineColor;
    if (!isErasing) {
        CGFloat red,green,blue,alpha,white;
        if ([lineColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
            vertex_color = GLKVector4Make(red, green, blue, alpha);
        }else if ([lineColor getWhite:&white alpha:&alpha]) {
            vertex_color = GLKVector4Make(white, white, white, alpha);
        }
    }
}
/**
 设置线条宽度
 
 @param lineWidth 宽度
 */
-(void)setLineWidth:(CGFloat)lineWidth {
    _lineWidth = lineWidth;
    if (!isErasing) {
        [self executeStrokeWidth:_lineWidth];
    }
}


- (void)executeStrokeWidth:(CGFloat)width {
    currentThickness = width;
    stroke_width_max = width * 1.5f;
    stroke_width_min = width * 0.25f;
}

/**
 设置橡皮擦宽度

 @param eraserWidth 宽度
 */
- (void)setEraserWidth:(CGFloat)eraserWidth {
    _eraserWidth = eraserWidth;
    if (isErasing) {
        [self executeStrokeWidth:_eraserWidth];
        
    }
}
/**
 开始擦除
 */
- (void)eraserBegin {
    if (!isErasing) {
        isErasing = YES;
        [self setEraserWidth:_eraserWidth];
        vertex_color = GLKVector4Make(0.0, 0.0, 0.0, 0.0);
    }
}
/**
 擦除结束
 */
- (void)eraserEnd {
    if (isErasing) {
        isErasing = NO;
        [self setLineColor:_lineColor];
        [self setLineWidth:_lineWidth];
    }
}
/**
 撤销输入
 */
- (void)backword {
    lastHandleState = LRHandleStateWord;
    NSNumber * num = [NSNumber numberWithUnsignedInt:lineLength];
    if ([indexRecords containsObject:num]) {
        NSUInteger index = [indexRecords indexOfObject:num];
        NSInteger desIndex = index - 1;
        if (desIndex >= 0) {
            lineLength = [[indexRecords objectAtIndex:desIndex]unsignedIntValue];
            [self setNeedsDisplay];
        }else{
            lineLength = 0;
            [self setNeedsDisplay];
        }
    }
}
/**
 前进一步输入
 */
- (void)forword {
    if (lastHandleState == LRHandleStateWord) {
        NSNumber * num = [NSNumber numberWithUnsignedInt:lineLength];
        if ([indexRecords containsObject:num]) {
            NSUInteger index = [indexRecords indexOfObject:num];
            if (index != indexRecords.count-1) {
                lineLength = [[indexRecords objectAtIndex:index+1]unsignedIntValue];
                [self setNeedsDisplay];
            }
        }
    }
}


/**
 签名图片
 @return 签名图片
 */
- (UIImage *)signatureImage{
    return [self snapshot];
}

/**
 获取签名原始数据
 @return 数据
 */
- (NSData *)signatureBufferData {
    return [lineData copy];
}

/**
 从文件读取并显示签名

 @param filePath 文件路径
 @return 能否显示
 */
- (BOOL)displaySignatureFromFile:(NSString *)filePath {
    NSFileManager * manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:filePath]) {
        return NO;
    }
    NSData * data = [NSData dataWithContentsOfFile:filePath];
    if (!data) {
        return NO;
    }
    lineData = [NSMutableData dataWithData:data];
    glBindBuffer(GL_ARRAY_BUFFER, lineBuffer);
    [self updateLineBuffer];
    [self setNeedsDisplay];
    return YES;
}
#pragma mark  GLKViewDelegate
/**
 绘制
 @param view self
 @param rect self.bounds
 */
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    glClearColor(clear_color.r, clear_color.g, clear_color.b, clear_color.a);
    glClear(GL_COLOR_BUFFER_BIT);
    if (lineLength>2) {
        glBindVertexArray(lineArray);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, lineLength);
    }
}
@end
