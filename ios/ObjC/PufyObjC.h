#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift, Objective-C istisnalarını (NSException) yakalayamaz; iOS'un bazı API'leri (ör. BGTaskScheduler)
/// hata döndürmek yerine istisna fırlatıp uygulamayı çökertebiliyor. Bu yardımcı bloğu güvenle çalıştırır.
@interface PufyObjC : NSObject
/// Blok istisnasız biterse YES, istisna fırlatırsa NO döner (istisna konsola yazılır)
+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block NS_SWIFT_NAME(attempt(_:));
@end

NS_ASSUME_NONNULL_END
