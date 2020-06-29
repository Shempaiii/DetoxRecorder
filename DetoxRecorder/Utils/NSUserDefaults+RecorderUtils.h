//
//  NSUserDefaults+RecorderUtils.h
//  DetoxRecorder
//
//  Created by Leo Natan (Wix) on 5/17/20.
//  Copyright © 2020 Wix. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSUserDefaults (RecorderUtils)

@property (nonatomic, assign, setter=dtxrec_setAttemptXYRecording:) BOOL dtxrec_attemptXYRecording;
@property (nonatomic, assign, setter=dtxrec_setCoalesceScrollEvents:) BOOL dtxrec_coalesceScrollEvents;
@property (nonatomic, assign, setter=dtxrec_setDisableVisualizations:) BOOL dtxrec_disableVisualizations;
@property (nonatomic, assign, setter=dtxrec_setDisableAnimations:) BOOL dtxrec_disableAnimations;

@end

NS_ASSUME_NONNULL_END
