//
//  HBK_RTMPSocket.m
//  HBK_Live
//
//  Created by 黄冰珂 on 2018/1/3.
//  Copyright © 2018年 黄冰珂. All rights reserved.
//

#import "HBK_RTMPSocket.h"


#define DATA_ITEMS_MAX_COUNT 100
#define RTMP_DATA_RESERVE_SIZE 400

#define RTMP_CONNECTION_TIMEOUT 1500
#define RTMP_RECEIVE_TIMEOUT    2

#define RTMP_HEAD_SIZE ()

static const NSUInteger defaultFrameListMaxCount = 10;


/*
 GCD 信号量控制并发 （dispatch_semaphore）
 　dispatch_semaphore_create　　　创建一个semaphore
 　　dispatch_semaphore_signal　　　发送一个信号
 　　dispatch_semaphore_wait　　　　等待信号
 */
@interface HBK_RTMPSocket () {
    RTMP *_HBK_RTMP;
    dispatch_semaphore_t _lock;
}

@property (nonatomic, strong) HBK_LiveStreamInfo *stream;

@property (nonatomic, strong) dispatch_queue_t socketQueue;

@property (nonatomic, assign) NSInteger retryTimes4netWorkBreaken;

@property (nonatomic, assign) BOOL isSending;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isConnecting;
@property (nonatomic, assign) BOOL isReconnecting;

@property (nonatomic, assign) BOOL sendVideoHead;
@property (nonatomic, assign) BOOL sendAudioHead;

@property (nonatomic, assign) NSMutableArray <HBK_Frame *> *frameList;
@property (nonatomic, strong) NSMutableArray <HBK_Frame *> *list;

@end

@implementation HBK_RTMPSocket

- (NSMutableArray<HBK_Frame *> *)frameList {
    if (!_frameList) {
        self.frameList = [NSMutableArray arrayWithCapacity:0];
    }
    return _frameList;
}
- (NSMutableArray<HBK_Frame *> *)list {
    if (!_list) {
        self.list = [NSMutableArray arrayWithCapacity:0];
    }
    return _list;
}
- (instancetype)initWithStram:(HBK_LiveStreamInfo *)stream {
    if (!stream) {
        //抛出来一个异常
        @throw [NSException exceptionWithName:@"JFRtmpSocket init error" reason:@"stream is nil" userInfo:nil];
    }
    if (self = [super init]) {
        self.stream = stream;
    }
    _lock = dispatch_semaphore_create(1);
    return self;
}

- (dispatch_queue_t)socketQueue {
    if (!_socketQueue) {
        _socketQueue = dispatch_queue_create("com.huangbingke.HBK.live.socketQueue", NULL);
    }
    return _socketQueue;
}

//开始连接
- (void)start {
    dispatch_async(self.socketQueue, ^{
        if (!_stream) {
            return ;
        }
        if (_isConnecting) {
            return;
        }
        if (_HBK_RTMP != NULL) {
            return;
        }
        [self HBK_RTMP264_Connect:(char *)[self.stream.url cStringUsingEncoding:NSASCIIStringEncoding]];
    });
}
//暂停连接
- (void)stop {
    dispatch_async(self.socketQueue, ^{
        if (_HBK_RTMP != NULL) {
            RTMP_Close(_HBK_RTMP);
            RTMP_Free(_HBK_RTMP);
            _HBK_RTMP = NULL;
        }
        [self resetParameter];
    });
}
//发送帧数据
- (void)sendFrame:(HBK_Frame *)frame {
    __weak typeof (self) weakSelf = self;
    dispatch_async(self.socketQueue, ^{
        __strong typeof (weakSelf) self = weakSelf;
        if (!frame) {
            return ;
        }
        [self appendObject:frame];
        [self sendFrame:frame];
    });
}

- (void)appendObject:(HBK_Frame *)frame {
    if (!frame) {
        return;
    }
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    if (self.frameList.count < defaultFrameListMaxCount) {
        [self.frameList addObject:frame];
    } else {
        // < 排序
        [self.frameList addObject:frame];
        NSArray *sortedSendQuery = [self.frameList sortedArrayUsingFunction:frameDataCompare context:NULL];
        [self.frameList removeAllObjects];
        [self.frameList addObjectsFromArray:sortedSendQuery];
        //丢帧
        [self removeExpireFrame];
        HBK_Frame *firstFrame = self.frameList.firstObject;
        [self.frameList removeObjectAtIndex:0];
        if (firstFrame) {
            [self.list addObject:firstFrame];
        }
    }
    dispatch_semaphore_signal(_lock);
}

- (void)removeExpireFrame {
    if (self.list.count < defaultFrameListMaxCount) {
        return;
    }
    NSArray *pFrame = [self expirePFrames];//第一个p到第二个I之间的p帧
    if (pFrame && pFrame.count > 0) {
        [self.list removeObjectsInArray:pFrame];
        return;
    }
    HBK_Frame *firstIFrame = [self firstIFrame];
    if (firstIFrame) {
        [self.list removeObject:firstIFrame];
        return;
    }
    [self.list removeAllObjects];
}

- (NSArray *)expirePFrames {
    NSMutableArray *pFrames = [NSMutableArray new];
    for (NSInteger index = 0; index < self.list.count; index++) {
        HBK_Frame *frame = [self.list objectAtIndex:index];
        if ([frame isKindOfClass:[HBK_VideoFrame class]]) {
            HBK_VideoFrame *videoFrame = (HBK_VideoFrame *)frame;
            if (videoFrame.isKeyFrame && pFrames.count > 0) {
                break;
            } else {
                [pFrames addObject:frame];
            }
        }
    }
    return pFrames;
}

- (HBK_Frame *)firstIFrame {
    for (NSInteger index = 0; index < self.list.count; index++) {
        HBK_Frame *frame = [self.list objectAtIndex:index];
        if ([frame isKindOfClass:[HBK_VideoFrame class]] && ((HBK_VideoFrame *) frame).isKeyFrame) {
            return frame;
        }
    }
    return nil;
}


NSInteger frameDataCompare(id obj1, id obj2, void *context) {
    HBK_Frame *frame1 = (HBK_Frame *)obj1;
    HBK_Frame *frame2 = (HBK_Frame *)obj2;
    if (frame1.timestamp == frame2.timestamp) {
        return NSOrderedSame;
    } else if (frame1.timestamp > frame2.timestamp) {
        return NSOrderedDescending;
    }
    return NSOrderedAscending;
}

- (NSInteger)HBK_RTMP264_Connect:(char *)push_url {
    //由于摄像头的timestamp是一直在累加, 需要每次得到相应的时间戳
    //分配与初始化
    if (_isConnecting) {
        return -1;
    }
    _isConnecting = YES;
    //代理回调网络状态
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:HBK_LiveStatus_Pending];
    }
    if (_HBK_RTMP != NULL) {
        RTMP_Close(_HBK_RTMP);
        RTMP_Free(_HBK_RTMP);
    }
    _HBK_RTMP = RTMP_Alloc();//创建一个remp会话的句柄
    RTMP_Init(_HBK_RTMP);//初始化句柄
    
    //设置会话参数 URL
    if (RTMP_SetupURL(_HBK_RTMP, push_url) < 0) {
        goto Failed;//程序跳转, 叫做goto, goto可以跳转到程序的任意地方
    }
    //设置发布流, 这个函数必须在连接前使用, 否则无限
    RTMP_EnableWrite(_HBK_RTMP);
    //在几秒钟内连接超时
    _HBK_RTMP->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    //连接服务器
    if (RTMP_Connect(_HBK_RTMP, NULL) < 0) {
        goto Failed;
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:HBK_LiveStatus_Start];
    }
    _isConnected = YES;
    _isConnecting = YES;
    _isReconnecting = YES;
    _isSending = YES;
    _retryTimes4netWorkBreaken = 0;
    return 0;
Failed:
    RTMP_Close(_HBK_RTMP);
    RTMP_Free(_HBK_RTMP);
    [self resetParameter];
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)]) {
        [self.delegate socketStatus:self status:HBK_LiveStatus_Error];
    }
    return -1;
}

- (void)sendFrame {
    if (!self.isSending && self.list.count > 0) {
        self.isSending = YES;
        if (!_isConnected || _isReconnecting || _isConnecting || !_HBK_RTMP) {
            return;
        }
        HBK_Frame *frame = [self popFirstObject];
        if ([frame isKindOfClass:[HBK_VideoFrame class]]) {//
            HBK_VideoFrame *videoFrame = (HBK_VideoFrame *)frame;
            if (!self.sendVideoHead) {
                self.sendVideoHead = YES;
                [self sendVideoHeaderWithSpsData:videoFrame.sps ppsData:videoFrame.sps];
            } else {
                [self sendVideo:videoFrame];
            }
        } else {
            HBK_AudioFrame *audioFrame = (HBK_AudioFrame *)frame;
            if (!self.sendAudioHead) {
                self.sendAudioHead = YES;
                [self sendAudioHeader:audioFrame];
            } else {
                [self sendAudio:frame];
            }
        }
    }
}
- (HBK_Frame *)popFirstObject {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    HBK_Frame *firstFrame = self.list.firstObject;
    [self.list removeObjectAtIndex:0];
    dispatch_semaphore_signal(_lock);
    return firstFrame;
}
//重置参数
- (void)resetParameter {
    _isConnecting = NO;
    _isReconnecting = NO;
    _isSending = NO;
    _isConnected = NO;
    _sendAudioHead = NO;
    _sendVideoHead = NO;
    self.retryTimes4netWorkBreaken = 0;
    [self removeAllObjects];
}

- (void)removeAllObjects {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    [self.list removeAllObjects];
    dispatch_semaphore_signal(_lock);
}


#pragma mark 发送视频包
// 发送视频包头
// H.264 的编码信息帧是发送给 RTMP 服务器称为 AVC sequence header，RTMP 服务器只有收到 AVC sequence header 中的 sps, pps 才能解析后续发送的 H264 帧
- (void)sendVideoHeaderWithSpsData:(NSData *)spsData ppsData:(NSData *)ppsData{
    if(!spsData || !ppsData) return;
    
    unsigned char * body    =NULL;
    NSInteger iIndex        = 0;
    NSInteger rtmpLength    = 1024;
    const char *sps         = spsData.bytes;
    const char *pps         = ppsData.bytes;
    NSInteger sps_len       = spsData.length;
    NSInteger pps_len       = ppsData.length;
    
    body = (unsigned char*)malloc(rtmpLength);
    memset(body,0,rtmpLength);  // 函数常用于内存空间初始化 用来对一段内存空间全部设置为某个字符，一般用在对定义的字符串进行初始化为‘ ’或‘/0’
    
    body[iIndex++] = 0x17;
    body[iIndex++] = 0x00;
    
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    
    body[iIndex++] = 0x01;
    body[iIndex++] = sps[1];
    body[iIndex++] = sps[2];
    body[iIndex++] = sps[3];
    body[iIndex++] = 0xff;
    
    /*sps*/
    body[iIndex++]   = 0xe1;
    body[iIndex++] = (sps_len >> 8) & 0xff;
    body[iIndex++] = sps_len & 0xff;
    memcpy(&body[iIndex],sps,sps_len);  // 用来做内存拷贝，你可以拿它拷贝任何数据类型的对象，可以指定拷贝的数据长度
    iIndex +=  sps_len;
    
    /*pps*/
    body[iIndex++]   = 0x01;
    body[iIndex++] = (pps_len >> 8) & 0xff;
    body[iIndex++] = (pps_len) & 0xff;
    memcpy(&body[iIndex], pps, pps_len);
    iIndex +=  pps_len;
    
    /*调用发送接口*/
    [self sendPacket:RTMP_PACKET_TYPE_VIDEO data:body size:iIndex nTimestamp:0];
    free(body);
}
// 发送视频包
- (void)sendVideo:(HBK_VideoFrame *)frame{
    if(!frame || !frame.data || frame.data.length < 11) return;
    
    NSInteger i = 0;
    NSInteger rtmpLength = frame.data.length+9;
    unsigned char *body = (unsigned char*)malloc(rtmpLength);
    memset(body,0,rtmpLength);
    
    if(frame.isKeyFrame){
        body[i++] = 0x17;// 1:Iframe  7:AVC
    } else{
        body[i++] = 0x27;// 2:Pframe  7:AVC
    }
    body[i++] = 0x01;// AVC NALU
    body[i++] = 0x00;
    body[i++] = 0x00;
    body[i++] = 0x00;
    body[i++] = (frame.data.length >> 24) & 0xff;
    body[i++] = (frame.data.length >> 16) & 0xff;
    body[i++] = (frame.data.length >>  8) & 0xff;
    body[i++] = (frame.data.length ) & 0xff;
    memcpy(&body[i],frame.data.bytes,frame.data.length);
    
    [self sendPacket:RTMP_PACKET_TYPE_VIDEO data:body size:(rtmpLength) nTimestamp:frame.timestamp];
    free(body);
}

#pragma mark 发送语音
// 发送语音包头
- (void)sendAudioHeader:(HBK_AudioFrame *)audioFrame{
    if(!audioFrame || !audioFrame.audioInfo) return;
    
    NSInteger rtmpLength = audioFrame.audioInfo.length + 2;/*spec data长度,一般是2*/
    unsigned char * body = (unsigned char*)malloc(rtmpLength);
    memset(body,0,rtmpLength);
    
    /*AF 00 + AAC RAW data*/
    body[0] = 0xAF;
    body[1] = 0x00;
    memcpy(&body[2],audioFrame.audioInfo.bytes,audioFrame.audioInfo.length); /*spec_buf是AAC sequence header数据*/
    [self sendPacket:RTMP_PACKET_TYPE_AUDIO data:body size:rtmpLength nTimestamp:0];
    free(body);
}


// 发送语音包
- (void)sendAudio:(HBK_Frame *)frame{
    if(!frame) return;
    NSInteger rtmpLength = frame.data.length + 2;/*spec data长度,一般是2*/
    unsigned char * body = (unsigned char*)malloc(rtmpLength);
    memset(body,0,rtmpLength);
    
    /*AF 01 + AAC RAW data*/
    body[0] = 0xAF;
    body[1] = 0x01;
    memcpy(&body[2],frame.data.bytes,frame.data.length);
    [self sendPacket:RTMP_PACKET_TYPE_AUDIO data:body size:rtmpLength nTimestamp:frame.timestamp];
    free(body);
}

#pragma mark -- Rtmp Send

/**
 根据包类型 来发送包, 这里主要分为 视频包和语音包
 
 @param nPacketType 包类型  RTMP_PACKET_TYPE_VIDEO(视频包类型) RTMP_PACKET_TYPE_AUDIO(音频包类型)
 @param data 包内容
 @param size 包的大小
 @param nTimestamp 时间戳
 @return 返回int 值, 来判断是否发送成功
 */
-(NSInteger) sendPacket:(unsigned int)nPacketType data:(unsigned char *)data size:(NSInteger) size nTimestamp:(uint64_t) nTimestamp{
    NSInteger rtmpLength = size;
    RTMPPacket rtmp_pack;   // 创建RTMP 包
    /*分配包内存和初始化*/
    RTMPPacket_Reset(&rtmp_pack);
    RTMPPacket_Alloc(&rtmp_pack,(uint32_t)rtmpLength);
    
    rtmp_pack.m_nBodySize = (uint32_t)size;
    memcpy(rtmp_pack.m_body,data,size);
    rtmp_pack.m_hasAbsTimestamp = 0;
    rtmp_pack.m_packetType = nPacketType;
    if(_HBK_RTMP) rtmp_pack.m_nInfoField2 = _HBK_RTMP->m_stream_id;
    rtmp_pack.m_nChannel = 0x04;
    rtmp_pack.m_headerType = RTMP_PACKET_SIZE_LARGE;
    if (RTMP_PACKET_TYPE_AUDIO == nPacketType && size !=4){
        rtmp_pack.m_headerType = RTMP_PACKET_SIZE_MEDIUM;
    }
    rtmp_pack.m_nTimeStamp = (uint32_t)nTimestamp;
    
    NSInteger nRet;
    if (RTMP_IsConnected(_HBK_RTMP)){
        int success = RTMP_SendPacket(_HBK_RTMP,&rtmp_pack,0);    // true 为放进发送队列, false 不放进发送队列直接发送
        if(success){
            self.isSending = NO;
            [self sendFrame];
        }
        nRet = success;
    } else {
        nRet = -1;
    }
    RTMPPacket_Free(&rtmp_pack);
    return nRet;
}

@end
