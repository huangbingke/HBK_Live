//
//  HBK_RTMPSocket.h
//  HBK_Live
//
//  Created by 黄冰珂 on 2018/1/3.
//  Copyright © 2018年 黄冰珂. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <rtmp.h>
#import "HBK_LiveStreamInfo.h"
#import "HBK_Frame.h"




@class HBK_RTMPSocket;
@protocol HBK_RTMPSocketDelegate <NSObject>

/*回调当前网络情况*/
- (void)socketStatus:(HBK_RTMPSocket *)socket status:(HBK_LiveStatus)status;

@end

@interface HBK_RTMPSocket : NSObject

@property (nonatomic, assign) id <HBK_RTMPSocketDelegate>delegate;

- (instancetype)initWithStram:(HBK_LiveStreamInfo *)stream;

- (void)start;
- (void)stop;
- (void)sendFrame:(HBK_Frame *)frame;

@end
