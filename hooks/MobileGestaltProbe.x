#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

#import "ProjectXLogging.h"
#import "PXHookOptions.h"
#import "../libs/fishhook.h"

#pragma mark - Rate limit (log each key once)

static CFMutableSetRef gSeenCFKeys = NULL;

static void PXEnsureSeenSet(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSeenCFKeys = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
    });
}

static Boolean PXShouldLogCFKey(CFStringRef key) {
    if (!key) return false;
    PXEnsureSeenSet();
    if (CFSetContainsValue(gSeenCFKeys, key)) return false;
    CFSetAddValue(gSeenCFKeys, key);
    return true;
}

static BOOL PXShouldLogNSKey(NSString *key) {
    static NSMutableSet *seen = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        seen = [NSMutableSet set];
    });
    if (!key) return NO;
    if ([seen containsObject:key]) return NO;
    [seen addObject:key];
    return YES;
}

static inline BOOL PXProbeEnabled(void) {
    return PXHookEnabled(@"mgprobe");
}

#pragma mark - Wrapper ObjC

@interface MobileGestalt : NSObject
+ (id)copyAnswer:(NSString *)key;
+ (NSDictionary *)copyMultipleAnswers:(NSArray *)keys options:(int)options;
@end

%hook MobileGestalt

+ (id)copyAnswer:(NSString *)key {
    if (PXProbeEnabled() && PXShouldLogNSKey(key)) {
        PXLog(@"[MG-WRAPPER] 🔍 copyAnswer key=%@", key);
    }
    return %orig;
}

+ (NSDictionary *)copyMultipleAnswers:(NSArray *)keys options:(int)options {
    if (PXProbeEnabled()) {
        for (NSString *k in keys) {
            if (PXShouldLogNSKey(k)) {
                PXLog(@"[MG-WRAPPER] 📦 multi key=%@", k);
            }
        }
    }
    return %orig;
}

%end

#pragma mark - C API via fishhook

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef property) = NULL;
static Boolean  (*orig_MGGetBoolAnswer)(CFStringRef property) = NULL;

static CFTypeRef hook_MGCopyAnswer(CFStringRef property) {
    if (PXProbeEnabled() && property && PXShouldLogCFKey(property)) {
        PXLog(@"[MG-CAPI] 🔍 MGCopyAnswer key=%@", property);
    }
    return orig_MGCopyAnswer ? orig_MGCopyAnswer(property) : NULL;
}

static Boolean hook_MGGetBoolAnswer(CFStringRef property) {
    if (PXProbeEnabled() && property && PXShouldLogCFKey(property)) {
        PXLog(@"[MG-CAPI] 🔍 MGGetBoolAnswer key=%@", property);
    }
    return orig_MGGetBoolAnswer ? orig_MGGetBoolAnswer(property) : false;
}

static struct rebinding gMGRebindings[2];
static dispatch_once_t gMGOnce;

%ctor {
    @autoreleasepool {
        %init;

        dispatch_once(&gMGOnce, ^{
            gMGRebindings[0] = (struct rebinding){
                "MGCopyAnswer",
                (void *)hook_MGCopyAnswer,
                (void **)&orig_MGCopyAnswer
            };
            gMGRebindings[1] = (struct rebinding){
                "MGGetBoolAnswer",
                (void *)hook_MGGetBoolAnswer,
                (void **)&orig_MGGetBoolAnswer
            };
            rebind_symbols(gMGRebindings, 2);
            PXLog(@"[MG-PROBE] ✅ Installed probes (safe static rebindings)");
        });
    }
}
