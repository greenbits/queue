//
//  EDQueue.h
//  queue
//
//  Created by Andrew Sliwinski on 6/29/12.
//  Copyright (c) 2012 Andrew Sliwinski. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, EDQueueResult) {
    EDQueueResultSuccess = 0,
    EDQueueResultFail,
    EDQueueResultCritical
};

typedef void (^EDQueueCompletionBlock)(EDQueueResult result);

extern NSString *const EDQueueDidStart;
extern NSString *const EDQueueDidStop;
extern NSString *const EDQueueJobDidSucceed;
extern NSString *const EDQueueJobDidFail;
extern NSString *const EDQueueDidDrain;
extern NSString *const EDQueueDidBecomeStale;
extern NSString *const EDQueueDidBecomeFresh;

@protocol EDQueueDelegate;
@interface EDQueue : NSObject

+ (EDQueue *)sharedInstance;

@property (nonatomic, weak) id<EDQueueDelegate> delegate;

@property (nonatomic) BOOL isReliable;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) BOOL isActive;
@property (nonatomic, readonly) BOOL isStale;
@property (nonatomic) NSUInteger retryLimit;
@property (nonatomic) NSUInteger staleThreshold;

- (void)enqueueWithData:(id)data forTask:(NSString *)task error:(NSError * __autoreleasing *)outError;
- (void)enqueueWithData:(id)data forTask:(NSString *)task;
- (void)start;
- (void)stop;
- (void)empty;
- (void)skipJob;

- (BOOL)jobExistsForTask:(NSString *)task;
- (BOOL)jobIsActiveForTask:(NSString *)task;
- (NSDictionary *)nextJobForTask:(NSString *)task;
- (NSUInteger)fetchJobCount;
- (NSArray *)dumpAllJobs;

@end

@protocol EDQueueDelegate <NSObject>
@optional
- (EDQueueResult)queue:(EDQueue *)queue processJob:(NSDictionary *)job;
- (void)queue:(EDQueue *)queue processJob:(NSDictionary *)job completion:(EDQueueCompletionBlock)block;
@end
