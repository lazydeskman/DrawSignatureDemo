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
//定义每个点的数据结构(位置x,y,z(0.0),颜色r,g,b,a)
typedef struct {
    GLKVector3 position;//{x,y,z(1.0)}
    GLKVector4 color;//{r,g,b,a}
}AWSignPoint;

//定义能保存的最大顶点数目
static uint max_count;// = 屏幕像素点的数目
//static GLKVector4 vertex_color = {0.0,0.0,0.0,1.0};//线条颜色(黑色)
//static GLKVector4 clear_color = {1.0,1.0,1.0,0.0};//清除颜色(透明)


/**
 将点数据添加到缓冲区
 @param length 长度
 @param point 点数据
 */
static inline void addSignPoint(uint * length,AWSignPoint point){
    if (*length >= max_count) {
        printf("lenth beyond max_count");
        return;
    }
    GLvoid * data = glMapBufferRange(GL_ARRAY_BUFFER, (*length)*sizeof(AWSignPoint), sizeof(AWSignPoint), GL_MAP_READ_BIT|GL_MAP_WRITE_BIT);
    memcpy(data, &point, sizeof(AWSignPoint));
    glUnmapBuffer(GL_ARRAY_BUFFER);
    (*length)++;
}

static inline CGPoint QuadraticPointInCurve(CGPoint start,CGPoint end,CGPoint controlPoint,float percent){
    double a = pow((1.0 - percent), 2.0);
    double b = 2.0 * percent * (1.0 - percent);
    double c = pow(percent, 2.0);
    return CGPointMake(a * start.x + b * controlPoint.x + c * end.x, a * start.y + b * controlPoint.y + c * end.y);
}

static inline float generateRandom(float from,float to){
    return random() % 10000 / 10000.0 * (to - from) + from;
}

static inline float clamp(float min, float max, float value){
    return fmaxf(min, fminf(max, value));
}

static inline GLKVector3 perpendicular(AWSignPoint p1, AWSignPoint p2){
    
    return  GLKVector3Make(p2.position.y - p1.position.y,-1 * (p2.position.x - p1.position.x), 0);
}

static inline AWSignPoint ViewPointToGL(CGPoint viewPoint,CGRect bounds,GLKVector4 color){
    return (AWSignPoint) {
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
 二、CPU保存顶点数据,每次产生新的顶点后,通过glGenBuffer重新申请GPU空间,然后写入保存的所有顶点
 优势:不会受限于一的方式申请的最大数
 缺点:每次写入的顶点数据会随着顶点数的增加而增加
 */

@interface LRSignView () <GLKViewDelegate>
{
    GLuint lineBuffer;//线条缓冲句柄
    GLuint lineArray;//线条缓冲区
    uint lineLength;//线条长度
    GLuint dotBuffer;//点缓冲句柄
    GLuint dotArray;//点缓冲区
    uint dotLength;//点长度
    float currentThickness;//线条宽度
    float previousThickness;
    float stroke_width_max;//线条最宽处的宽度
    float stroke_width_min;//线条最窄处的宽度
    float stroke_width_smooth;//线条平滑值
    float velocity_clamp_max;
    float velocity_clamp_min;
    float quadratic_distance_tolerance;
    GLKVector4 vertex_color;
    GLKVector4 clear_color;
    CGPoint previousPoint;
    CGPoint previousMidPoint;
    
    AWSignPoint previousVertex;
    AWSignPoint currentVelocity;
    NSMutableData * lineData;//保存线条 顶点数据
    NSMutableData * dotData;//保存点  顶点数据

}
@end


@implementation LRSignView

+ (void)load {
    [super load];
    max_count = ([UIScreen mainScreen].scale*[UIScreen mainScreen].bounds.size.width) * ([UIScreen mainScreen].scale*[UIScreen mainScreen].bounds.size.height);//初始化一下最大顶点数
}

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
    [self generateDotBufferData];//初始化用来画点的缓冲
    [self configGesutreRecognizeies];//初始化手势

}

/**
 初始化参数
 */
- (void)initParameters {
    currentThickness = 0.006;
    stroke_width_min = 0.002;
    stroke_width_max = 0.009;
    stroke_width_smooth = 0.5;
    velocity_clamp_min = 10.0;
    velocity_clamp_max = 5000.0;
    quadratic_distance_tolerance = 3.0;
    lineLength = 0;
    dotLength = 0;
    previousPoint = CGPointMake(-100, -100);
    dotData = [NSMutableData data];
    lineData = [NSMutableData data];
    vertex_color = GLKVector4Make(0.0, 0.0, 0.0, 1.0);
    clear_color = GLKVector4Make(1.0, 1.0, 1.0, 0.0);

}

/**
 编译 顶点/片段着色器和程序
 */
- (void)compileShaderAndProgram {
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
    glDeleteShader(vShader);
    glDeleteShader(fShader);
    glUseProgram(programObj);
    
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
    glGenVertexArrays(1, &lineArray);//生成缓冲对象
    glBindVertexArray(lineArray);//绑定缓冲对象
    glGenBuffers(1, &lineBuffer);//生成会缓冲去
    glBindBuffer(GL_ARRAY_BUFFER, lineBuffer);//绑定缓冲区
//    glBufferData(GL_ARRAY_BUFFER, sizeof(AWSignPoint)*max_count, NULL, GL_DYNAMIC_DRAW);//将数据写入缓冲区,这里写入空,缓冲区大小为sizeof(AWSignPoint)*max_count
    [self bindVertexAttribute];//绑定属性
    glBindVertexArray(0);//解除缓冲对象绑定
}

/**
 生成点缓冲
 */
- (void)generateDotBufferData {
    glGenVertexArrays(1, &dotArray);
    glBindVertexArray(dotArray);
    glGenBuffers(1, &dotBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, dotBuffer);
//    glBufferData(GL_ARRAY_BUFFER, sizeof(AWSignPoint)*max_count, NULL, GL_DYNAMIC_DRAW);
    [self bindVertexAttribute];
    glBindVertexArray(0);
}

/**
 启动顶点属性
 */
- (void)bindVertexAttribute {
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(AWSignPoint), (GLvoid*)NULL);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(AWSignPoint), (GLvoid*)NULL+offsetof(AWSignPoint, color));
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
        glBindBuffer(GL_ARRAY_BUFFER, dotArray);
        AWSignPoint touchPoint = ViewPointToGL(location, self.bounds,vertex_color);
        [dotData appendBytes:&touchPoint length:sizeof(AWSignPoint)];
        AWSignPoint centerPoint = touchPoint;
        centerPoint.color = vertex_color;
        [dotData appendBytes:&centerPoint length:sizeof(AWSignPoint)];
        static int segments = 15;
        GLKVector2 radius = (GLKVector2){
            clamp(0.00001, 0.02, currentThickness * generateRandom(0.5, 1.5)),
            clamp(0.00001, 0.02, currentThickness * generateRandom(0.5, 1.5))
        };
        GLKVector2 velocityRadius = radius;
        float angle = 0;
        
        for (int i = 0; i <= segments; i++) {
            
            AWSignPoint p = centerPoint;
            p.color = GLKVector4Make(vertex_color.r, vertex_color.g, vertex_color.b, vertex_color.a*stroke_width_smooth);
            p.position.x += velocityRadius.x * cosf(angle);
            p.position.y += velocityRadius.y * sinf(angle);
            [dotData appendBytes:&p length:sizeof(AWSignPoint)];
            [dotData appendBytes:&centerPoint length:sizeof(AWSignPoint)];
            dotLength += 2;
            angle += M_PI * 2.0 / segments;
        }
        [dotData appendBytes:&touchPoint length:sizeof(AWSignPoint)];
        dotLength += 3;
        [self updateDotBuffer];
       
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
    
    currentVelocity = ViewPointToGL(velocity, self.bounds, vertex_color);
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
        
        previousPoint = location;
        previousMidPoint = location;
        
        AWSignPoint startPoint = ViewPointToGL(location, self.bounds, vertex_color);
        previousVertex = startPoint;
        previousThickness = currentThickness;
        [lineData appendBytes:&startPoint length:sizeof(AWSignPoint)];
        [lineData appendBytes:&previousVertex length:sizeof(AWSignPoint)];
        lineLength += 2;
        
    } else if ([pan state] == UIGestureRecognizerStateChanged) {
        
        CGPoint mid = CGPointMake((location.x + previousPoint.x) / 2.0, (location.y + previousPoint.y) / 2.0);
        
        if (distance > quadratic_distance_tolerance) {
            // Plot quadratic bezier instead of line
            unsigned int i;
            
            int segments = (int) distance / 1.5;
            
            float startPenThickness = previousThickness;
            float endPenThickness = currentThickness;
            previousThickness = currentThickness;
            
            for (i = 0; i < segments; i++)
            {
                currentThickness = startPenThickness + ((endPenThickness - startPenThickness) / segments) * i;
                
                CGPoint quadPoint = QuadraticPointInCurve(previousMidPoint, mid, previousPoint, (float)i / (float)(segments));
                
                AWSignPoint v = ViewPointToGL(quadPoint, self.bounds, vertex_color);
                [self addTriangleStripPointsForPrevious:previousVertex next:v];
                
                previousVertex = v;
            }
        } else if (distance > 1.0) {
            
            AWSignPoint v = ViewPointToGL(location, self.bounds, vertex_color);
            [self addTriangleStripPointsForPrevious:previousVertex next:v];
            previousVertex = v;
            previousThickness = currentThickness;
        }
        
        previousPoint = location;
        previousMidPoint = mid;
        
    } else if (pan.state == UIGestureRecognizerStateEnded | pan.state == UIGestureRecognizerStateCancelled) {
        
        AWSignPoint v = ViewPointToGL(location, self.bounds, vertex_color);
        [lineData appendBytes:&v length:sizeof(AWSignPoint)];
        lineLength++;
        previousVertex = v;
        [lineData appendBytes:&previousVertex length:sizeof(AWSignPoint)];
        lineLength++;
    }
    [self updateLineBuffer];
    [self setNeedsDisplay];
}

/**
 更新点的顶点数据
 */
- (void)updateDotBuffer {
    glBufferData(GL_ARRAY_BUFFER, dotData.length, dotData.bytes, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

/**
 更新线条的顶点数据
 */
- (void)updateLineBuffer {
    glBufferData(GL_ARRAY_BUFFER, lineData.length, lineData.bytes, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

- (void)addTriangleStripPointsForPrevious:(AWSignPoint)previous next:(AWSignPoint)next {
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
        
        AWSignPoint stripPoint = {
            { p1.x + difX, p1.y + difY, 0.0 },
            vertex_color
        };
        [lineData appendBytes:&stripPoint length:sizeof(AWSignPoint)];
        lineLength++;
        toTravel *= -1;
    }
}
/**
 设置线条颜色
 @param lineColor 颜色
 */
- (void)setLineColor:(UIColor *)lineColor {
    double red,green,blue,alpha,white;
    if ([lineColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
        vertex_color = GLKVector4Make(red, green, blue, alpha);
    }else if ([lineColor getWhite:&white alpha:&alpha]) {
        vertex_color = GLKVector4Make(white, white, white, alpha);
    }
    _lineColor = lineColor;
}
#pragma mark  GLKViewDelegate
/**
 绘制
 @param view self
 @param rect self.bounds
 */
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    glViewport(0, 0, rect.size.width*[UIScreen mainScreen].scale, rect.size.height*[UIScreen mainScreen].scale);
    glClearColor(clear_color.r, clear_color.g, clear_color.b, clear_color.a);
    glClear(GL_COLOR_BUFFER_BIT);
    if (dotLength>2) {
        glBindVertexArray(dotArray);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, dotLength);
    }
    if (lineLength>2) {
        glBindVertexArray(lineArray);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, lineLength);
    }
}

@end
