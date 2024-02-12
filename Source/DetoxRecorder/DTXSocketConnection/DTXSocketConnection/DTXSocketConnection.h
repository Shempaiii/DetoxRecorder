//
//  DTXSocketConnection.h
//  DTXSocketConnection
//
//  Created by Leo Natan (Wix) on 18/07/2017.
//  Copyright © 2017 LeoNatan. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DTXSocketConnection;

@protocol DTXSocketConnectionDelegate <NSObject>

@optional

/**
 * Tells the delegate that the read side of the underlying socket has been closed.
 *
 * This method may be called even if no reads are currently in progress. This method does not indicate that the stream reached end-of-file (EOF), such that no more data can be read.
 *
 * @param socketConnection The socket connection that closed reads.
 */
- (void)readClosedForSocketConnection:(DTXSocketConnection*)socketConnection;
/**
 * Tells the delegate that the write side of the underlying socket has been closed.
 *
 * This method may be called even if no writes are currently in progress.
 *
 * @param socketConnection The socket connection that closed writes.
 */
- (void)writeClosedForSocketConnection:(DTXSocketConnection*)socketConnection;

@end

@interface DTXSocketConnection : NSObject

/**
 * Creates a bidirectional TCP/IP connection using the provided input and output streams.
 *
 * After you create the connection, you must start it by calling its @c open method.
 *
 * @note The streams provided must not be opened.
 *
 * @param inputStream The input stream.
 *
 * @param outputStream The output stream.
 *
 * @param delegateQueue A queue for scheduling the delegate calls and completion handlers. The queue must be a serial queue, in order to ensure the correct ordering of callbacks. If @c nil, the session creates a serial queue for performing all delegate method calls and completion handler calls.
 */
- (instancetype)initWithInputStream:(NSInputStream*)inputStream outputStream:(NSOutputStream*)outputStream delegateQueue:(nullable dispatch_queue_t)delegateQueue NS_DESIGNATED_INITIALIZER;
/**
 * Creates a bidirectional TCP/IP connection to a specified hostname and port.
 *
 * After you create the connection, you must start it by calling its @c open method.
 *
 * @param hostName The hostname of the connection endpoint.
 *
 * @param port The hostname of the connection endpoint.
 *
 * @param delegateQueue A queue for scheduling the delegate calls and completion handlers. The queue must be a serial queue, in order to ensure the correct ordering of callbacks. If @c nil, the session creates a serial queue for performing all delegate method calls and completion handler calls.
 */
- (instancetype)initWithHostName:(NSString*)hostName port:(NSInteger)port delegateQueue:(nullable dispatch_queue_t)delegateQueue NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * The queue provided when this object was created.
 *
 * All delegate method calls and completion handlers related to the connection are performed on this queue. The connection object keeps a strong reference to this queue until your app exits or the connection object is deallocated.
 *
 * @note This queue must be set at object creation time and may not be changed.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t delegateQueue;

/**
 * The connection delegate.
 */
@property (nonatomic, nullable, weak) id<DTXSocketConnectionDelegate> delegate;

/**
 * Opens the connection's read and write streams.
 */
- (void)open;
/**
 * Completes any enqueued reads and writes, and then closes the read side of the underlying socket.
 *
 * You may continue to write data using the @c writeData:completionHandler: method after calling this method. Any calls to @c readDataWithCompletionHandler: after calling this method will result in an error.
 */
- (void)closeRead;
/**
 * Completes any enqueued reads and writes, and then closes the write side of the underlying socket.
 *
 * You may continue to read data using the @c readDataWithCompletionHandler: method after calling this method. Any calls to @c writeData:completionHandler: after calling this method will result in an error.
 */
- (void)closeWrite;

/**
 * Sends a message.
 *
 * If an error occurs, any outstanding work will also fail.
 *
 * Note that invocation of the completion handler does not guarantee that the remote side has received all the bytes, only that they have been written to the kernel.
 *
 * @param message The message to be sent.
 * @param completionHandler A block that receives an NSError that indicates an error encountered while sending, or @c nil if no error occurred. This block is executed on the work queue.
 */
- (void)sendMessage:(NSData*)message completionHandler:(void (^)(NSError* __nullable error))completionHandler NS_SWIFT_NAME(send(_:completionHandler:));

/**
 * Reads a message once all the frames of the message are available.
 *
 * If an error occurs, any outstanding work will also fail.
 *
 * @param completionHandler A block that receives two parameters: the message, and an NSError that indicates an error encountered while receiving the message. The error is @c nil if no error occurred. This handler is executed on the work queue.
 */
- (void)receiveMessageWithCompletionHandler:(void (^)(NSData* __nullable message, NSError* __nullable error))completionHandler NS_SWIFT_NAME(receive(completionHandler:));

@end

@interface DTXSocketConnection (Deprecated)

/**
 * Creates a bidirectional TCP/IP connection using the provided input and output streams.
 *
 * After you create the connection, you must start it by calling its @c open method.
 *
 * @note The streams provided must not be opened.
 *
 * @param inputStream The input stream.
 *
 * @param outputStream The output stream.
 *
 * @param queue A queue for scheduling the delegate calls and completion handlers. The queue must be a serial queue, in order to ensure the correct ordering of callbacks. If @c nil, the session creates a serial queue for performing all delegate method calls and completion handler calls.
 */
- (instancetype)initWithInputStream:(NSInputStream*)inputStream outputStream:(NSOutputStream*)outputStream queue:(nullable dispatch_queue_t)queue DEPRECATED_MSG_ATTRIBUTE("Use initWithInputStream:outputStream:delegateQueue: instead.");
/**
 * Creates a bidirectional TCP/IP connection to a specified hostname and port.
 *
 * After you create the connection, you must start it by calling its @c open method.
 *
 * @param hostName The hostname of the connection endpoint.
 *
 * @param port The hostname of the connection endpoint.
 *
 * @param queue A queue for scheduling the delegate calls and completion handlers. The queue must be a serial queue, in order to ensure the correct ordering of callbacks. If @c nil, the session creates a serial queue for performing all delegate method calls and completion handler calls.
 */
- (instancetype)initWithHostName:(NSString*)hostName port:(NSInteger)port queue:(nullable dispatch_queue_t)queue DEPRECATED_MSG_ATTRIBUTE("Use initWithHostName:port:delegateQueue: instead.");

/**
 * Asynchronously writes the specified data to the stream, and calls a handler upon completion.
 *
 * There is no guarantee that the remote side of the stream has received all of the written data at the time that @c completionHandler is called, only that all of the data has been written to the kernel.
 *
 * @param data The data to be written.
 * @param completionHandler The completion handler to call when all bytes are written, or an error occurs. This handler is executed on the work queue.
 */
- (void)writeData:(NSData*)data completionHandler:(void (^ __nonnull)(NSError* __nullable error))completionHandler NS_SWIFT_NAME(write(_:completionHandler:)) DEPRECATED_MSG_ATTRIBUTE("Use sendMessage:completionHandler: instead.");

/**
 * Asynchronously reads data from the stream, and calls a handler upon completion.
 *
 * @param completionHandler The completion handler to call when data is read, or an error occurs. This handler is executed on the work queue.
 */
- (void)readDataWithCompletionHandler:(void (^ __nonnull)(NSData* __nullable data, NSError* __nullable error))completionHandler NS_SWIFT_NAME(read(completionHandler:)) DEPRECATED_MSG_ATTRIBUTE("Use receiveMessageWithCompletionHandler: instead.");

@end

NS_ASSUME_NONNULL_END
