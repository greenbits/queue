//
//  EDQueue.m
//  queue
//
//  Created by Andrew Sliwinski on 6/29/12.
//  Copyright (c) 2012 Andrew Sliwinski. All rights reserved.
//

#import "EDQueue.h"
#import "EDQueueStorageEngine.h"

NSString *const EDQueueDidStart = @"EDQueueDidStart";
NSString *const EDQueueDidStop = @"EDQueueDidStop";
NSString *const EDQueueJobDidSucceed = @"EDQueueJobDidSucceed";
NSString *const EDQueueJobDidFail = @"EDQueueJobDidFail";
NSString *const EDQueueDidDrain = @"EDQueueDidDrain";
NSString *const EDQueueDidBecomeStale = @"EDQueueDidBecomeStale";
NSString *const EDQueueDidBecomeFresh = @"EDQueueDidBecomeFresh";

@interface EDQueue ()
{
    BOOL _isReliable;
    BOOL _isRunning;
    BOOL _isActive;
    BOOL _isStale;
    BOOL _lastIsStale;
    NSUInteger _retryLimit;
    NSUInteger _staleThreshold;
}

@property (nonatomic) EDQueueStorageEngine *engine;
@property (nonatomic, readwrite) NSString *activeTask;

@end

//

@implementation EDQueue

@synthesize isReliable = _isReliable;
@synthesize isRunning = _isRunning;
@synthesize isActive = _isActive;
@synthesize isStale = _isStale;
@synthesize retryLimit = _retryLimit;
@synthesize staleThreshold = _staleThreshold;

#pragma mark - Singleton

+ (EDQueue *)sharedInstance
{
    static EDQueue *singleton = nil;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{
        singleton = [[self alloc] init];
    });
    return singleton;
}

#pragma mark - Init

- (id)init
{
    self = [super init];
    if (self) {
        _engine     = [[EDQueueStorageEngine alloc] init];
        _retryLimit = 4;
        _isReliable = NO;
        _staleThreshold = 300; // 5 minutes
    }
    return self;
}

- (void)dealloc
{
    self.delegate = nil;
    _engine = nil;
}

#pragma mark - Public methods

/**
 * Adds a new job to the queue.
 *
 * @param {id} Data
 * @param {NSString} Task label
 *
 * @return {void}
 */
- (void)enqueueWithData:(id)data forTask:(NSString *)task
{
    [self enqueueWithData:data forTask:task error:nil];
}

/**
 * Adds a new job to the queue.
 *
 * @param {id} Data
 * @param {NSString} Task label
 * @param {NSError * __autoreleasing *} Address of Error Pointer
 *
 * @return {void}
 */
- (void)enqueueWithData:(id)data forTask:(NSString *)task error:(NSError * __autoreleasing *)outError
{
    if (data == nil) data = @{};
    [self.engine createJob:data forTask:task error:outError];
    [self tick];
}

/**
 * Returns true if a job exists for this task.
 *
 * @param {NSString} Task label
 *
 * @return {Boolean}
 */
- (BOOL)jobExistsForTask:(NSString *)task
{
    BOOL jobExists = [self.engine jobExistsForTask:task];
    return jobExists;
}

/**
 * Returns true if the active job if for this task.
 *
 * @param {NSString} Task label
 *
 * @return {Boolean}
 */
- (BOOL)jobIsActiveForTask:(NSString *)task
{
    BOOL jobIsActive = [self.activeTask length] > 0 && [self.activeTask isEqualToString:task];
    return jobIsActive;
}

/**
 * Returns the list of jobs for this
 *
 * @param {NSString} Task label
 *
 * @return {NSArray}
 */
- (NSDictionary *)nextJobForTask:(NSString *)task
{
    NSDictionary *nextJobForTask = [self.engine fetchJobForTask:task];
    return nextJobForTask;
}

/**
 * Returns the count of jobs.
 *
 * @return {NSUInteger}
 */
- (NSUInteger)fetchJobCount
{
    return [_engine fetchJobCount];
}

/**
 * Returns the count of jobs.
 *
 * @return {NSArray}
 */
- (NSArray *)dumpAllJobs
{
    return [_engine dumpAllJobs];
}

/**
 * Starts the queue.
 *
 * @return {void}
 */
- (void)start
{
    DDLogInfo(@"EDQueue start");

    if (!self.isRunning) {
        _isRunning = YES;
        _isStale = NO;
        [self tick];
        [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueDidStart, @"name", nil, @"data", nil] waitUntilDone:false];
    }
}

/**
 * Stops the queue.
 * @note Jobs that have already started will continue to process even after stop has been called.
 *
 * @return {void}
 */
- (void)stop
{
    DDLogInfo(@"EDQueue stop");

    if (self.isRunning) {
        _isRunning = NO;
        [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueDidStop, @"name", nil, @"data", nil] waitUntilDone:false];
    }
}

/**
 * Skips the next job on the queue.
 *
 * @return {void}
 */
- (void)skipJob {
    id job = [self.engine fetchJob];
    [self.engine removeJob:[job objectForKey:@"id"]];
}


/**
 * Empties the queue.
 * @note Jobs that have already started will continue to process even after empty has been called.
 *
 * @return {void}
 */
- (void)empty
{
    [self.engine removeAllJobs];
    _isStale = NO;
    [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueDidBecomeFresh, @"name", nil, @"data", nil] waitUntilDone:false];
    [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueDidDrain, @"name", nil, @"data", nil] waitUntilDone:false];
}


#pragma mark - Private methods

/**
 * Checks the queue for available jobs, sends them to the processor delegate, and then handles the response.
 *
 * @return {void}
 */
- (void)tick
{
    dispatch_queue_t gcd = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_async(gcd, ^{
        if (self.isRunning && !self.isActive && [self.engine fetchJobCount] > 0) {
            // Start job
            _isActive = YES;
            id job = [self.engine fetchJob];
            self.activeTask = [(NSDictionary *)job objectForKey:@"task"];

            DDLogInfo(@"EDQueue delegate: %p", self.delegate);

            if (!self.delegate) {
                DDLogWarn(@"EDQueue delegate nil");
            }

            // Pass job to delegate
            if ([self.delegate respondsToSelector:@selector(queue:processJob:completion:)]) {
                [self.delegate queue:self processJob:job completion:^(EDQueueResult result) {
                    [self processJob:job withResult:result];
                    self.activeTask = nil;
                }];
            } else {
                EDQueueResult result = [self.delegate queue:self processJob:job];
                [self processJob:job withResult:result];
                self.activeTask = nil;
            }
        }
    });
}

- (void)processJob:(NSDictionary*)job withResult:(EDQueueResult)result
{
    DDLogInfo(@"processJob result: %d", result);

    // Check result
    switch (result) {
        case EDQueueResultSuccess:
            [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueJobDidSucceed, @"name", job, @"data", nil] waitUntilDone:false];
            [self.engine removeJob:[job objectForKey:@"id"]];
            break;
        case EDQueueResultFail:
            [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueJobDidFail, @"name", job, @"data", nil] waitUntilDone:true];
            NSUInteger currentAttempt = [[job objectForKey:@"attempts"] intValue] + 1;
            if (self.isReliable || currentAttempt < self.retryLimit) {
                [self.engine incrementAttemptForJob:[job objectForKey:@"id"]];
            } else {
                [self.engine removeJob:[job objectForKey:@"id"]];
            }
            break;
        case EDQueueResultCritical:
            [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueJobDidFail, @"name", job, @"data", nil] waitUntilDone:false];
            [self errorWithMessage:@"Critical error. Job canceled."];
            if (self.isReliable) {
                [self.engine incrementAttemptForJob:[job objectForKey:@"id"]];
            } else {
                [self.engine removeJob:[job objectForKey:@"id"]];
            }
            break;
    }

    long jobTimestamp = (long)[[(NSDictionary *)job objectForKey:@"stamp"] longLongValue];
    long currentTimestamp = [[NSDate date] timeIntervalSince1970];
    _isStale = result != EDQueueResultSuccess && (currentTimestamp - jobTimestamp) > _staleThreshold;

    if (_isStale && !_lastIsStale) {
        [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueDidBecomeStale, @"name", job, @"data", nil] waitUntilDone:false];
    } else if (!_isStale && _lastIsStale) {
        [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueDidBecomeFresh, @"name", job, @"data", nil] waitUntilDone:false];
    }

    // Clean-up
    _lastIsStale = _isStale;
    _isActive = NO;

    // Drain
    if ([self.engine fetchJobCount] == 0) {
        [self performSelectorOnMainThread:@selector(postNotification:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:EDQueueDidDrain, @"name", nil, @"data", nil] waitUntilDone:false];
    } else {
        [self performSelectorOnMainThread:@selector(tick) withObject:nil waitUntilDone:false];
    }
}

/**
 * Posts a notification (used to keep notifications on the main thread).
 *
 * @param {NSDictionary} Object
 *                          - name: Notification name
 *                          - data: Data to be attached to notification
 *
 * @return {void}
 */
- (void)postNotification:(NSDictionary *)object
{
    [[NSNotificationCenter defaultCenter] postNotificationName:[object objectForKey:@"name"] object:[object objectForKey:@"data"]];
}

/**
 * Writes an error message to the log.
 *
 * @param {NSString} Message
 *
 * @return {void}
 */
- (void)errorWithMessage:(NSString *)message
{
    NSLog(@"EDQueue Error: %@", message);
}

@end
