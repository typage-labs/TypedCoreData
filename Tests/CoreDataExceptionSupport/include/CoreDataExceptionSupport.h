#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Test-only bridge for comparing native Objective-C initializer exceptions.
FOUNDATION_EXPORT NSException * _Nullable TCDCaptureException(
    void (NS_NOESCAPE ^body)(void)
);

NS_ASSUME_NONNULL_END
