import Foundation
import CExceptionGuard

/// ObjC 异常防护：AVFoundation 配置 UVC(DAL) 设备时可能抛 NSException，
/// Swift 的 do/catch 接不住，会直接终止进程。经 csrc/ExceptionGuard.m 的
/// ocal_try() 在 ObjC 层捕获。
enum ObjCGuard {

    /// 执行 block；若抛 ObjC 异常则捕获并记录，返回是否成功
    @discardableResult
    static func catching(_ context: String, _ block: () -> Void) -> Bool {
        var name: NSString? = nil
        var reason: NSString? = nil
        let ok = ocal_try(block, &name, &reason)
        if !ok {
            NSLog("ObjCGuard[\(context)] 捕获异常: \(name ?? "?") — \(reason ?? "?")")
        }
        return ok
    }
}
