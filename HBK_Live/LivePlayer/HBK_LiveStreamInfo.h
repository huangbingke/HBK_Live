//
//  HBK_LiveStreamInfo.h
//  HBK_Live
//
//  Created by 黄冰珂 on 2018/1/3.
//  Copyright © 2018年 黄冰珂. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, HBK_LiveStatus) {
    HBK_LiveStatus_Ready = 0,//准备
    HBK_LiveStatus_Pending,//连接中
    HBK_LiveStatus_Start,//已连接
    HBK_LiveStatus_Stop,//已断开
    HBK_LiveStatus_Error//连接出错
};

typedef NS_ENUM(NSUInteger, HBK_LiveSocketErrorCode) {
    HBK_LiveSocketError_PreView = 201,
    HBK_LiveSocketError_GetSteamInfo,
    HBK_LiveSocketError_ConnectSocket,
    HBK_LiveSocketError_Verification,
    HBK_LiveSocketError_ReconnectTimeOut
};



@interface HBK_LiveStreamInfo : NSObject


/**
 流id
 */
@property (nonatomic, copy) NSString *stramId;


/**
 token
 */
@property (nonatomic, copy) NSString *token;


/**
 上传地址 RTMP
 */
@property (nonatomic, copy) NSString *url;



/**
 上传ip
 */
@property (nonatomic, copy) NSString *host;


/**
 上传端口
 */
@property (nonatomic, copy) NSString *port;


















@end
