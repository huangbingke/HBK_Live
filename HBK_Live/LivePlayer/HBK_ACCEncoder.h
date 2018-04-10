//
//  HBK_ACCEncoder.h
//  HBK_Live
//
//  Created by 黄冰珂 on 2018/1/3.
//  Copyright © 2018年 黄冰珂. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>


@protocol HBK_ACCEncoderDelegate <NSObject>



@end

//---------------->> ACC编码 -------------
@interface HBK_ACCEncoder : NSObject

@property (nonatomic) dispatch_queue_t encoderQueue;
@property (nonatomic) dispatch_queue_t callbackQueue;
@property (nonatomic, assign) id<HBK_ACCEncoderDelegate> delegate;

- (void)encoderSampleBuffer:(CMSampleBufferRef)sampleBuffer
                  timeStamp:(uint64_t)timeStamp
            completionBlock:(void(^)(NSData *encodedData, NSError *error))completionBlock;



@end
