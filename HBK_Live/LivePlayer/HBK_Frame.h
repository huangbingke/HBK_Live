//
//  HBK_Frame.h
//  HBK_Live
//
//  Created by 黄冰珂 on 2018/1/3.
//  Copyright © 2018年 黄冰珂. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HBK_Frame : NSObject
@property (nonatomic, assign) uint64_t timestamp;
@property (nonatomic, strong) NSData *data;
//flv或者rtmp包头
@property (nonatomic, strong) NSData *header;

@end


@interface HBK_VideoFrame : HBK_Frame

@property (nonatomic, assign) BOOL isKeyFrame;
@property (nonatomic, assign) NSData *sps;
@property (nonatomic, strong) NSData *pps;


@end



@interface HBK_AudioFrame : HBK_Frame

//flv打包中acc的header
@property (nonatomic, strong) NSData *audioInfo;

@end
