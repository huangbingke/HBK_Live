//
//  HBK_LiveShowViewController.m
//  HBK_Live
//
//  Created by 黄冰珂 on 2018/1/2.
//  Copyright © 2018年 黄冰珂. All rights reserved.
//

#import "HBK_LiveShowViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "HBK_LiveStreamInfo.h"
#import "HBK_RTMPSocket.h"

#define NOW (CACurrentMediaTime()*1000)

@interface HBK_LiveShowViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate, HBK_RTMPSocketDelegate> {
    dispatch_queue_t videoQueue;
    dispatch_queue_t audioQueue;
    dispatch_queue_t videoEncoderQueeu;
    dispatch_queue_t audioEncoderQueue;
    
    FILE *_h264File;
    FILE *_accFile;
    dispatch_semaphore_t _lock;
}

/*AVCaptureSession是AVFoundation的核心类,用于捕捉视频和音频,协调视频和音频的输入和输出流 音视频录制期间管理者*/
@property (nonatomic, strong) AVCaptureSession *session;
/*视频管理者/音频管理者 */
@property (nonatomic, strong) AVCaptureDevice *videoDevice;
@property (nonatomic, strong) AVCaptureDevice *audioDevice;
/*视频输出数据管理者/音频输出数据管理者*/
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *audioOutput;
/*视频输入数据管理者/音频输入数据管理者*/
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
/*用来展示视频的图像*/
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
/*document文件路径*/
@property (nonatomic, strong) NSString *documentDictionary;

@property (nonatomic, strong) HBK_RTMPSocket *socket; // Rtmp 推流管理类

@property (nonatomic, assign) BOOL isFirstFrame;
@property (nonatomic, assign) BOOL uploading;
@property (nonatomic, assign) uint64_t timestamp;
@property (nonatomic, assign) uint64_t currentTimestamp;


@end

@implementation HBK_LiveShowViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.documentDictionary = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    
    
}



- (void)initAVCaptureSession {
    self.session = [[AVCaptureSession alloc] init];
    //设置录像的分辨率
    //先判断是否支持要设置的分辨率
    if (@available(iOS 9.0, *)) {
        if ([self.session canSetSessionPreset:AVCaptureSessionPreset3840x2160]) {
            [self.session canSetSessionPreset:AVCaptureSessionPreset3840x2160];
        } else if ([self.session canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
            [self.session canSetSessionPreset:AVCaptureSessionPreset1920x1080];
        } else if ([self.session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
            [self.session canSetSessionPreset:AVCaptureSessionPreset1280x720];
        } else if ([self.session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
            [self.session canSetSessionPreset:AVCaptureSessionPreset640x480];
        } else if ([self.session canSetSessionPreset:AVCaptureSessionPreset352x288]) {
            [self.session canSetSessionPreset:AVCaptureSessionPreset352x288];
        }
    } else {
        // Fallback on earlier versions
    }
    
    //开始配置
    [self.session beginConfiguration];
    
    //获取摄像头
    [self getDevice];
    
    //视频
    [self videoOutputAndInput];
    //音频
    [self audioOutputAndInput];
    
    //直播同时进行播放
    [self initPreviewLayer];
    
    
}

//获取摄像头设备
- (void)getDevice {
    //iOS10以后 指定摄像头方向获取摄像头
    AVCaptureDeviceDiscoverySession *devicesSession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:(AVCaptureDevicePositionFront)];
   
    for (AVCaptureDevice *device in devicesSession.devices) {
        if (device.position == AVCaptureDevicePositionFront) {
            self.videoDevice = device;
        } else {
            self.videoDevice = nil;
        }
    }
}
//音频输入输出
- (void)audioOutputAndInput {
    //获取声音设备
    self.audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    //创建对应音频设备输入对象
    self.audioInput = [AVCaptureDeviceInput deviceInputWithDevice:self.audioDevice error:nil];
    //添加音频
    if ([self.session canAddInput:self.audioInput]) {
        [self.session addInput:self.audioInput];
    }
    //获取音频数据输出对象
    self.audioOutput = [[AVCaptureVideoDataOutput alloc] init];
    audioQueue = dispatch_queue_create("Audio Capture Queue", DISPATCH_QUEUE_SERIAL);
    [self.audioOutput setSampleBufferDelegate:self queue:audioQueue];
    if ([self.session canAddOutput:self.audioOutput]) {
        [self.session addOutput:self.audioOutput];
        
    }
}

//视频输入输出
- (void)videoOutputAndInput {
    NSError *error;
    //创建对应视频设备输入对象
    self.videoInput = [AVCaptureDeviceInput deviceInputWithDevice:self.videoDevice error:&error];
    if (error) {
        NSLog(@"Error: 摄像头出错了---> %@", error);
        return;
    }
    //添加到会话中
    //添加视频
    if ([self.session canAddInput:self.videoInput]) {
        //管理者能够添加 才可以添加
        [self.session addInput:self.videoInput];
    }
    //获取视频数据输出对象
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    //是否允许卡顿时丢帧
    self.videoOutput.alwaysDiscardsLateVideoFrames = NO;
    //设置代理, 捕获视频样品数据
    //注意:队列必须是串行队列, 才能获取数据, 而且不能为空
    videoQueue = dispatch_queue_create("Video Capture Queue", DISPATCH_QUEUE_SERIAL);
    [self.videoOutput setSampleBufferDelegate:self queue:videoQueue];
    if ([self.session canAddOutput:self.videoOutput]) {
        [self.session addOutput:self.videoOutput];
        AVCaptureConnection *connection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
        //设置视频的方向
        connection.videoOrientation = AVCaptureVideoOrientationPortrait;
        if ([connection isVideoStabilizationSupported]) {
            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
        }
        connection.videoScaleAndCropFactor = connection.videoScaleAndCropFactor;
    }
}

- (void)initPreviewLayer {
    [self.view layoutIfNeeded];
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    self.previewLayer.connection.videoOrientation = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo].videoOrientation;
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.position = CGPointMake(kScreenWidth/2, kScreenHeight/2);
    
    CALayer *layer = self.view.layer;
    layer.masksToBounds = true;
    [layer addSublayer:self.previewLayer];
    
}


#pragma mark ---------------- Action ------------
//开始直播
- (IBAction)start_Live:(UIButton *)sender {
    _h264File = fopen([NSString stringWithFormat:@"%@/HBK_encodeVideo.h264", self.documentDictionary].UTF8String, "wb");
    _accFile = fopen([NSString stringWithFormat:@"%@/HBK_encodeAudio.acc", self.documentDictionary].UTF8String, "wb");
    
    HBK_LiveStreamInfo *stramInfo = [[HBK_LiveStreamInfo alloc] init];
    stramInfo.url = @"rtmp://192.168.0.103:1935/rtmplive/room";
    
    self.socket = [[HBK_RTMPSocket alloc] initWithStram:stramInfo];
    self.socket.delegate = self;
    [self.socket start];
    
    [self.session startRunning];
    sender.hidden = YES;
}
//返回
- (IBAction)back_StopLive:(UIButton *)sender {
    [self.socket stop];
    [self.session stopRunning];
//    self.vide
    
    
    fclose(_h264File);
    fclose(_accFile);
}


#pragma mark ---------- HBK_RTMPSocketDelegate
- (void)socketStatus:(HBK_RTMPSocket *)socket status:(HBK_LiveStatus)status {
    switch (status) {
        case HBK_LiveStatus_Error:
            NSLog(@"连接出错");
            break;
        case HBK_LiveStatus_Ready:
            NSLog(@"准备中");
            break;
        case HBK_LiveStatus_Pending:
            NSLog(@"连接中");
            break;
        case HBK_LiveStatus_Start:
            NSLog(@"已连接");
            break;
        case HBK_LiveStatus_Stop:
            NSLog(@"连接出错");
            break;
            
        default:
            break;
    }
}

- (uint64_t)currentTimestamp {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    uint64_t currentts = 0;
    if (_isFirstFrame == true) {
        _timestamp = NOW;
        _isFirstFrame = false;
        currentts = 0;
    } else {
        currentts = NOW - _timestamp;
    }
    dispatch_semaphore_signal(_lock);
    return currentts;
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
