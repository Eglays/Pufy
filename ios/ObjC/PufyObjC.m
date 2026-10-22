#import "PufyObjC.h"

@implementation PufyObjC

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"⚠️ Yakalanan iOS istisnası: %@ — %@", exception.name, exception.reason);
        return NO;
    }
}

@end
