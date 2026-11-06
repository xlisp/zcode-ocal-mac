#import <Foundation/Foundation.h>

// Swift 无法捕获 ObjC 异常；AVFoundation 对 UVC(DAL) 设备的部分配置调用
// 可能抛 NSException（如 setActiveVideoMinFrameDuration:），此处提供
// @try/@catch 包装供 Swift 直接调用。
NS_ASSUME_NONNULL_BEGIN
BOOL ocal_try(void (NS_NOESCAPE ^block)(void), NSString **outName, NSString **outReason);
NS_ASSUME_NONNULL_END
