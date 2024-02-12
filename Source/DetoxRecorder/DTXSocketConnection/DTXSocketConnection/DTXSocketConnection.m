//
//  DTXSocketConnection.m
//  DTXSocketConnection
//
//  Created by Leo Natan (Wix) on 18/07/2017.
//  Copyright © 2017 LeoNatan. All rights reserved.
//

#import "DTXSocketConnection.h"

#if ! defined(__cplusplus) && ! defined(auto)
#define auto __auto_type
#endif

@interface DTXSocketConnection () <NSStreamDelegate>

@end

#if defined(__IPHONE_14_0) || defined(__MAC_10_16) || defined(__TVOS_14_0) || defined(__WATCHOS_7_0)
__attribute__((objc_direct_members))
#endif
@implementation DTXSocketConnection
{
	NSInputStream* _inputStream;
	NSOutputStream* _outputStream;
	dispatch_queue_t _workQueue;
	
	BOOL _inputWaitingForHeader;
	BOOL _inputWaitingForData;
	uint64_t _inputTotalDataLength;
	uint8_t* _inputBytes;
	uint64_t _inputCurrentBytesLength;
	BOOL _inputPendingClose;
	
	NSMutableArray<NSData*>* _outputPendingDatasToBeWritten;
	BOOL _outputWaitingForHeader;
	BOOL _outputWaitingForData;
	NSData* _outputData;
	uint64_t _outputCurrentBytesLength;
	BOOL _outputPendingClose;
	
	NSMutableArray<void (^)(NSData *data, NSError *error)>* _pendingReads;
	NSMutableArray<void (^)(NSError *error)>* _pendingWrites;
}

- (void)_setupQueuesWithDelegateQueue:(dispatch_queue_t)delegateQueue
{
	_workQueue = dispatch_queue_create("com.wix.DTXSocketConnectionQueue", dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_SERIAL, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM));
	_delegateQueue = delegateQueue ?: _workQueue;
}

- (instancetype)initWithInputStream:(NSInputStream*)inputStream outputStream:(NSOutputStream*)outputStream delegateQueue:(nullable dispatch_queue_t)delegateQueue
{
	NSAssert(inputStream != nil && outputStream != nil, @"Streams must not be nil.");
	NSAssert(inputStream.streamStatus == NSStreamStatusNotOpen && outputStream.streamStatus == NSStreamStatusNotOpen, @"Streams must not be opened.");
	
	self = [super init];
	
	if(self)
	{
		[self _setupQueuesWithDelegateQueue:delegateQueue];
		_inputStream = inputStream;
		_outputStream = outputStream;
		
		[self _commonInit];
	}
	
	return self;
}

- (instancetype)initWithHostName:(NSString*)hostName port:(NSInteger)port delegateQueue:(nullable dispatch_queue_t)delegateQueue
{
	NSAssert(hostName != nil, @"Host name must not be nil.");
	NSAssert(port > 0, @"Invalid port number %@", @(port));
	
	self = [super init];
	
	if(self)
	{
		CFReadStreamRef readStream;
		CFWriteStreamRef writeStream;
		CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)hostName, (UInt32)port, &readStream, &writeStream);
		
		[self _setupQueuesWithDelegateQueue:delegateQueue];
		_inputStream = CFBridgingRelease(readStream);
		_outputStream = CFBridgingRelease(writeStream);
		
		[self _commonInit];
		
		
	}
	
	return self;
}

- (instancetype)init
{
	[self doesNotRecognizeSelector:_cmd];
	
	return nil;
}

+ (instancetype)new
{
	[self doesNotRecognizeSelector:_cmd];
	
	return nil;
}

- (void)_commonInit
{
	_pendingReads = [NSMutableArray new];
	_pendingWrites = [NSMutableArray new];
	_outputPendingDatasToBeWritten = [NSMutableArray new];
	
	dispatch_queue_set_specific(_workQueue, (__bridge void*)self, (__bridge void*)self, NULL);
}

- (void)open
{
	dispatch_async(_workQueue, ^{
		NSAssert(self->_inputStream.streamStatus == NSStreamStatusNotOpen && self->_outputStream.streamStatus == NSStreamStatusNotOpen, @"Streams must not be opened.");
		CFReadStreamSetDispatchQueue((__bridge CFReadStreamRef)self->_inputStream, self->_workQueue);
		CFWriteStreamSetDispatchQueue((__bridge CFWriteStreamRef)self->_outputStream, self->_workQueue);
		
		self->_inputStream.delegate = self;
		self->_outputStream.delegate = self;
		
		[self->_inputStream open];
		[self->_outputStream open];
	});
}

- (void)closeRead
{
	dispatch_async(_workQueue, ^{
		if(self->_pendingReads.count == 0)
		{
			[self->_inputStream close];
			return;
		}
		
		self->_inputPendingClose = YES;
	});
}

- (void)closeWrite
{
	dispatch_async(_workQueue, ^{
		if(self->_pendingWrites.count == 0)
		{
			[self->_outputStream close];
			return;
		}
		
		self->_outputPendingClose = YES;
	});
}

- (void)_startReadingHeader
{
	if(_inputBytes == NULL)
	{
		_inputBytes = malloc(sizeof(uint64_t));
	}
	
	if(_inputStream.hasBytesAvailable == NO)
	{
		//No bytes are available. Wait for delegate to notify on bytes availability.
		return;
	}
	
	static uint64_t headerLength = sizeof(uint64_t);
	uint64_t bytesRemaining = headerLength - _inputCurrentBytesLength;
	_inputCurrentBytesLength += [_inputStream read:(_inputBytes + _inputCurrentBytesLength) maxLength:(NSUInteger)bytesRemaining];
	
	if(_inputCurrentBytesLength < headerLength)
	{
		return;
	}
	
	uint64_t header;
	memcpy(&header, _inputBytes, headerLength);
	//Convert to host byte order.
	NTOHLL(header);
	
	free(_inputBytes);
	_inputBytes = NULL;
	_inputCurrentBytesLength = 0;
	
	_inputTotalDataLength = header;
	_inputWaitingForHeader = NO;
	
	if(_inputTotalDataLength == 0)
	{
		//Empty packet ignore. Load next header instead.
		
		_inputWaitingForHeader = YES;
		[self _startReadingHeader];
		
		return;
	}
	
	_inputWaitingForData = YES;
	
	[self _startReadingData];
}

- (void)_startReadingData
{
	if(_inputBytes == NULL)
	{
		_inputBytes = malloc((size_t)_inputTotalDataLength);
	}
	
	if(_inputStream.hasBytesAvailable == NO)
	{
		//No bytes are available. Wait for delegate to notify on bytes availability.
		return;
	}
	
	uint64_t bytesRemaining = _inputTotalDataLength - _inputCurrentBytesLength;
	_inputCurrentBytesLength += [_inputStream read:(_inputBytes + _inputCurrentBytesLength) maxLength:(NSUInteger)bytesRemaining];
	
	if(_inputCurrentBytesLength < _inputTotalDataLength)
	{
		return;
	}
	
	NSData* dataForUser = [NSData dataWithBytesNoCopy:_inputBytes length:(NSUInteger)_inputTotalDataLength];
	
	void (^pendingTask)(NSData *data, NSError *error) = _pendingReads.firstObject;
	
	dispatch_async(_delegateQueue, ^{
		pendingTask(dataForUser, nil);
	});
	
	[_pendingReads removeObjectAtIndex:0];
	
	_inputBytes = NULL;
	_inputTotalDataLength = 0;
	_inputCurrentBytesLength = 0;
	_inputWaitingForData = NO;
	
	if(_pendingReads.count > 0)
	{
		_inputWaitingForHeader = YES;
		[self _startReadingHeader];
		
		return;
	}
	
	if(_inputPendingClose == YES)
	{
		[_inputStream close];
	}
}

- (void)_errorOutForReadRequest:(void (^)(NSData *data, NSError *error))request
{
	if(_inputStream.streamStatus == NSStreamStatusClosed || _inputPendingClose)
	{
		dispatch_async(_delegateQueue, ^{
			request(nil, [NSError errorWithDomain:@"DTXSocketConnectionErrorDomain" code:10 userInfo:@{NSLocalizedDescriptionKey: @"Reading is closed."}]);
		});
		return;
	}
	
	if(_inputStream.streamStatus == NSStreamStatusError)
	{
		NSError* error = _inputStream.streamError;
		dispatch_async(_delegateQueue, ^{
			request(nil, error);
		});
		return;
	}
}

- (void)_errorOutAllPendingReadRequests
{
	for (void (^obj)(NSData *, NSError *) in _pendingReads)
	{
		[self _errorOutForReadRequest:obj];
	}
}

- (void)receiveMessageWithCompletionHandler:(void (^)(NSData* _Nullable, NSError * _Nullable))completionHandler
{
	[self _readDataWithCompletionHandler:completionHandler];
}

- (void)_readDataWithCompletionHandler:(void (^ _Nonnull)(NSData *data, NSError *error))completionHandler
{
	if(completionHandler == nil)
	{
		completionHandler = ^ (NSData *data, NSError* error) {};
	}
	
	dispatch_async(_workQueue, ^{
		BOOL readsPending = self->_pendingReads.count > 0;
		
		if(self->_inputStream.streamStatus >= NSStreamStatusClosed)
		{
			[self _errorOutForReadRequest:completionHandler];
			return;
		}
		
		if(self->_inputPendingClose)
		{
			[self _errorOutForReadRequest:completionHandler];
			return;
		}
		
		//Queue the pending read request.
		[self->_pendingReads addObject:completionHandler];
		
		//If there were pending reads, the system should attempt to handle this request in the future.
		if(readsPending)
		{
			return;
		}
		
		//Start reading
		self->_inputWaitingForHeader = YES;
		
		if(self->_inputStream.streamStatus >= NSStreamStatusOpen)
		{
			[self _startReadingHeader];
		}
	});
}

- (void)_prepareHeaderDataForData:(NSData*)data
{
	uint64_t length = data.length;
	HTONLL(length);
	_outputData = [NSData dataWithBytes:&length length:sizeof(uint64_t)];
}

- (void)_startWritingHeader
{
	if(_outputStream.hasSpaceAvailable == NO)
	{
		//No space is available. Wait for delegate to notify on space availability.
		return;
	}
	
	static uint64_t headerLength = sizeof(uint64_t);
	uint64_t bytesRemaining = headerLength - _outputCurrentBytesLength;
	
	_outputCurrentBytesLength += [_outputStream write:(_outputData.bytes + _outputCurrentBytesLength) maxLength:(NSUInteger)bytesRemaining];
	
	if(_outputCurrentBytesLength < headerLength)
	{
		return;
	}
	
	_outputWaitingForHeader = NO;
	_outputCurrentBytesLength = 0;
	
	_outputData = _outputPendingDatasToBeWritten.firstObject;
	[_outputPendingDatasToBeWritten removeObjectAtIndex:0];
	
	_outputWaitingForData = YES;
	
	[self _startWritingData];
}

- (void)_startWritingData
{
	if(_outputStream.hasSpaceAvailable == NO)
	{
		//No space is available. Wait for delegate to notify on space availability.
		return;
	}
	
	uint64_t bytesRemaining = _outputData.length - _outputCurrentBytesLength;
	if(bytesRemaining > 0)
	{
		_outputCurrentBytesLength += [_outputStream write:(_outputData.bytes + _outputCurrentBytesLength) maxLength:(NSUInteger)bytesRemaining];
	}
	
	if(_outputCurrentBytesLength < _outputData.length)
	{
		return;
	}
	
	void (^pendingTask)(NSError *error) = _pendingWrites.firstObject;
	
	dispatch_async(_delegateQueue, ^{
		pendingTask(nil);
	});
	
	[_pendingWrites removeObjectAtIndex:0];
	
	_outputData = NULL;
	_outputCurrentBytesLength = 0;
	_outputWaitingForData = NO;
	
	if(_pendingWrites.count > 0)
	{
		_outputWaitingForHeader = YES;
		[self _prepareHeaderDataForData:_outputPendingDatasToBeWritten.firstObject];
		[self _startWritingHeader];
		
		return;
	}
	
	if(_outputPendingClose == YES)
	{
		[_outputStream close];
	}
}

- (void)_errorOutForWriteRequest:(void (^)(NSError* __nullable error))request
{
	if(_outputStream.streamStatus == NSStreamStatusClosed || _outputPendingClose)
	{
		dispatch_async(_delegateQueue, ^{
			request([NSError errorWithDomain:@"DTXSocketConnectionErrorDomain" code:10 userInfo:@{NSLocalizedDescriptionKey: @"Writing is closed."}]);
		});
		return;
	}
	
	if(_outputStream.streamStatus == NSStreamStatusError)
	{
		NSError* error = _outputStream.streamError;
		dispatch_async(_delegateQueue, ^{
			request(error);
		});
		return;
	}
}

- (void)_errorOutAllPendingWriteRequests
{
	for (void (^obj)(NSError *) in _pendingWrites)
	{
		[self _errorOutForWriteRequest:obj];
	}
}

- (void)_writeDataNow:(NSData*)data completionHandler:(void(^)(NSError* _Nullable))completionHandler
{
	BOOL writesPending = _pendingWrites.count > 0;
	
	if(_outputStream.streamStatus >= NSStreamStatusClosed)
	{
		[self _errorOutForWriteRequest:completionHandler];
		return;
	}
	
	if(_outputPendingClose)
	{
		[self _errorOutForWriteRequest:completionHandler];
		return;
	}
	
	//Queue the pending write request.
	[_pendingWrites addObject:completionHandler];
	[_outputPendingDatasToBeWritten addObject:data];
	
	//If there were pending writes, the system should attempt to handle this request in the future.
	if(writesPending)
	{
		return;
	}
	
	[self _prepareHeaderDataForData:data];
	
	//Start reading
	_outputWaitingForHeader = YES;
	
	if(_outputStream.streamStatus >= NSStreamStatusOpen)
	{
		[self _startWritingHeader];
	}
}

- (void)sendMessage:(NSData*)message completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
	[self _writeData:message completionHandler:completionHandler];
}

- (void)_writeData:(NSData *)data completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler
{
	if(data == nil)
	{
		return;
	}
	
	if(completionHandler == nil)
	{
		completionHandler = ^ (NSError* error) {};
	}
	
	dispatch_async(_workQueue, ^{
		[self _writeDataNow:data completionHandler:completionHandler];
	});
}

#pragma mark NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
	__strong auto strongSelf = self;
	
	if(aStream == _inputStream)
	{
		switch (eventCode) {
			case NSStreamEventOpenCompleted:
				if(_inputWaitingForHeader)
				{
					[self _startReadingHeader];
				}
				break;
			case NSStreamEventHasBytesAvailable:
				if(_inputWaitingForHeader)
				{
					[self _startReadingHeader];
				}
				else if(_inputWaitingForData)
				{
					[self _startReadingData];
				}
				break;
			case NSStreamEventErrorOccurred:
			case NSStreamEventEndEncountered:
			{
				[self _errorOutAllPendingReadRequests];
				dispatch_async(_delegateQueue, ^{
					if([self.delegate respondsToSelector:@selector(readClosedForSocketConnection:)])
					{
						[self.delegate readClosedForSocketConnection:self];
					}
				});
			}	break;
			default:
				break;
		}
	}
	else
	{
		switch (eventCode) {
			case NSStreamEventOpenCompleted:
				if(_outputWaitingForHeader)
				{
					[self _startWritingHeader];
				}
				break;
			case NSStreamEventHasSpaceAvailable:
				if(_outputWaitingForHeader)
				{
					[self _startWritingHeader];
				}
				else if(_outputWaitingForData)
				{
					[self _startWritingData];
				}
				break;
			case NSStreamEventErrorOccurred:
			case NSStreamEventEndEncountered:
			{
				[self _errorOutAllPendingWriteRequests];
				dispatch_async(_delegateQueue, ^{
					if([self.delegate respondsToSelector:@selector(writeClosedForSocketConnection:)])
					{
						[self.delegate writeClosedForSocketConnection:self];
					}
				});
			}	break;
			default:
				break;
		}
	}
	
	strongSelf = nil;
}

- (void)dealloc
{
	NSInputStream* inputStream = _inputStream;
	NSOutputStream* outputStream = _outputStream;
	
	void (^block)(void) = ^{
		inputStream.delegate = nil;
		outputStream.delegate = nil;
		
		if(inputStream.streamStatus < NSStreamStatusClosed)
		{
			[inputStream close];
		}
		if(outputStream.streamStatus < NSStreamStatusClosed)
		{
			[outputStream close];
		}
	};
	
	if(dispatch_get_specific((__bridge void*)self) == (__bridge void*)self)
	{
		block();
	}
	else
	{
		dispatch_sync(_workQueue, block);
	}
	
	dispatch_queue_set_specific(_workQueue, (__bridge void*)self, NULL, NULL);
	
	_inputStream = nil;
	_outputStream = nil;
}

@end

@implementation DTXSocketConnection (Deprecated)

- (instancetype)initWithInputStream:(NSInputStream*)inputStream outputStream:(NSOutputStream*)outputStream queue:(nullable dispatch_queue_t)queue
{
	return [self initWithInputStream:inputStream outputStream:outputStream delegateQueue:queue];
}

- (instancetype)initWithHostName:(NSString*)hostName port:(NSInteger)port queue:(nullable dispatch_queue_t)queue
{
	return [self initWithHostName:hostName port:port delegateQueue:queue];
}

- (void)writeData:(NSData *)data completionHandler:(void (^ _Nonnull)(NSError * _Nullable))completionHandler
{
	[self _writeData:data completionHandler:completionHandler];
}

- (void)readDataWithCompletionHandler:(void (^)(NSData * _Nullable, NSError * _Nullable))completionHandler
{
	[self _readDataWithCompletionHandler:completionHandler];
}

@end
