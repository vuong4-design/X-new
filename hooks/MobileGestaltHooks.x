#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <substrate.h>

#import "ProjectXLogging.h"
#import "PXHookOptions.h"

typedef CFTypeRef (*MGCopyAnswerFn)(CFStringRef property);
static MGCopyAnswerFn orig_MGCopyAnswer = NULL;

// Recursion guard (C-level)
static __thread int px_mg_depth = 0;

// Cached spoof values (retained)
static CFStringRef gProductType = NULL;        // ProductType -> deviceModel.modelName
static CFStringRef gMarketingName = NULL;      // MarketingName -> deviceModel.name
static CFStringRef gHWModelStr = NULL;         // HWModelStr/HardwareModel -> deviceModel.hwModel
static CFStringRef gProductVersion = NULL;     // ProductVersion -> iosVersion.version
static CFStringRef gBuildVersion = NULL;       // BuildVersion -> iosVersion.build
static CFStringRef gSerialNumber = NULL;       // SerialNumber
static CFStringRef gIMEI = NULL;               // InternationalMobileEquipmentIdentity
static CFStringRef gMEID = NULL;               // MobileEquipmentIdentifier
static CFStringRef gUniqueDeviceID = NULL;     // UniqueDeviceID -> systemBootUUID
static CFDataRef   gUniqueDeviceIDData = NULL; // UniqueDeviceIDData (optional)

static inline void PXReleaseIfNotNull(CFTypeRef obj) {
    if (obj) CFRelease(obj);
}

static CFStringRef PXCopyStringFromDictPath(CFDictionaryRef root,
                                           CFStringRef key1,
                                           CFStringRef key2) {
    if (!root) return NULL;
    CFTypeRef v1 = CFDictionaryGetValue(root, key1);
    if (!v1 || CFGetTypeID(v1) != CFDictionaryGetTypeID()) return NULL;

    CFDictionaryRef d = (CFDictionaryRef)v1;
    CFTypeRef v2 = CFDictionaryGetValue(d, key2);
    if (!v2 || CFGetTypeID(v2) != CFStringGetTypeID()) return NULL;

    // Copy (retain) to own it
    return CFStringCreateCopy(kCFAllocatorDefault, (CFStringRef)v2);
}

static CFStringRef PXCopyStringFromRoot(CFDictionaryRef root, CFStringRef key) {
    if (!root) return NULL;
    CFTypeRef v = CFDictionaryGetValue(root, key);
    if (!v || CFGetTypeID(v) != CFStringGetTypeID()) return NULL;
    return CFStringCreateCopy(kCFAllocatorDefault, (CFStringRef)v);
}

static CFDataRef PXCopyUUIDDataFromString(CFStringRef uuidStr) {
    if (!uuidStr) return NULL;

    // Parse UUID string using CoreFoundation (no Foundation)
    CFUUIDRef uuid = CFUUIDCreateFromString(kCFAllocatorDefault, uuidStr);
    if (!uuid) return NULL;

    CFUUIDBytes b = CFUUIDGetUUIDBytes(uuid);
    CFRelease(uuid);

    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)&b, (CFIndex)sizeof(CFUUIDBytes));
}

static void PXLoadPhoneInfoCacheFromPlist(void) {
    // Reset old cache
    PXReleaseIfNotNull(gProductType); gProductType = NULL;
    PXReleaseIfNotNull(gMarketingName); gMarketingName = NULL;
    PXReleaseIfNotNull(gHWModelStr); gHWModelStr = NULL;
    PXReleaseIfNotNull(gProductVersion); gProductVersion = NULL;
    PXReleaseIfNotNull(gBuildVersion); gBuildVersion = NULL;
    PXReleaseIfNotNull(gSerialNumber); gSerialNumber = NULL;
    PXReleaseIfNotNull(gIMEI); gIMEI = NULL;
    PXReleaseIfNotNull(gMEID); gMEID = NULL;
    PXReleaseIfNotNull(gUniqueDeviceID); gUniqueDeviceID = NULL;
    PXReleaseIfNotNull(gUniqueDeviceIDData); gUniqueDeviceIDData = NULL;

    // Load plist (CoreFoundation, no ObjC)
    CFStringRef path = CFSTR("/var/mobile/Library/Preferences/com.projectx.phoneinfo.plist");
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, path, kCFURLPOSIXPathStyle, false);
    if (!url) {
        PXLog(@"[MobileGestalt] ❌ Cannot create URL for plist path");
        return;
    }

    CFDataRef data = NULL;
    SInt32 err = 0;
    Boolean ok = CFURLCreateDataAndPropertiesFromResource(kCFAllocatorDefault, url, &data, NULL, NULL, &err);
    CFRelease(url);

    if (!ok || !data) {
        PXLog(@"[MobileGestalt] ❌ Failed to read plist (err=%d)", (int)err);
        return;
    }

    CFPropertyListFormat fmt = kCFPropertyListXMLFormat_v1_0;
    CFErrorRef parseErr = NULL;
    CFPropertyListRef plist = CFPropertyListCreateWithData(kCFAllocatorDefault, data, kCFPropertyListImmutable, &fmt, &parseErr);
    CFRelease(data);

    if (!plist || CFGetTypeID(plist) != CFDictionaryGetTypeID()) {
        if (parseErr) CFRelease(parseErr);
        if (plist) CFRelease(plist);
        PXLog(@"[MobileGestalt] ❌ Invalid plist format");
        return;
    }

    CFDictionaryRef root = (CFDictionaryRef)plist;

    // deviceModel.modelName -> ProductType
    gProductType = PXCopyStringFromDictPath(root, CFSTR("deviceModel"), CFSTR("modelName"));
    // deviceModel.name -> MarketingName
    gMarketingName = PXCopyStringFromDictPath(root, CFSTR("deviceModel"), CFSTR("name"));
    // deviceModel.hwModel -> HWModelStr/HardwareModel
    gHWModelStr = PXCopyStringFromDictPath(root, CFSTR("deviceModel"), CFSTR("hwModel"));

    // iosVersion.version/build
    gProductVersion = PXCopyStringFromDictPath(root, CFSTR("iosVersion"), CFSTR("version"));
    gBuildVersion   = PXCopyStringFromDictPath(root, CFSTR("iosVersion"), CFSTR("build"));

    // serial / imei / meid / uuid
    gSerialNumber  = PXCopyStringFromRoot(root, CFSTR("serialNumber"));
    gIMEI          = PXCopyStringFromRoot(root, CFSTR("IMEI"));
    gMEID          = PXCopyStringFromRoot(root, CFSTR("MEID"));
    gUniqueDeviceID = PXCopyStringFromRoot(root, CFSTR("systemBootUUID"));
    if (gUniqueDeviceID) {
        gUniqueDeviceIDData = PXCopyUUIDDataFromString(gUniqueDeviceID);
    }

    CFRelease(plist);

    PXLog(@"[MobileGestalt] ✅ Cache loaded. ProductType=%@ MarketingName=%@ HWModelStr=%@",
          gProductType ? gProductType : CFSTR("<null>"),
          gMarketingName ? gMarketingName : CFSTR("<null>"),
          gHWModelStr ? gHWModelStr : CFSTR("<null>"));
}

static inline Boolean PXKeyEquals(CFStringRef a, CFStringRef b) {
    if (!a || !b) return false;
    return (CFStringCompare(a, b, 0) == kCFCompareEqualTo);
}

static CFTypeRef hook_MGCopyAnswer(CFStringRef property) {
    return orig_MGCopyAnswer(property);
}

%group PX_mobilegestalt

%ctor {
    // Load cache once (safe, no ObjC)
    PXLoadPhoneInfoCacheFromPlist();

    void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!handle) {
        PXLog(@"[MobileGestalt] ❌ Failed to dlopen libMobileGestalt.dylib");
        return;
    }

    void *symA = dlsym(handle, "MGCopyAnswer");
    if (!symA) {
        PXLog(@"[MobileGestalt] ❌ Could not find MGCopyAnswer");
        return;
    }

    MSHookFunction(symA, (void *)hook_MGCopyAnswer, (void **)&orig_MGCopyAnswer);
    PXLog(@"[MobileGestalt] ✅ Hooked MGCopyAnswer (safe-cache mode)");
}

%end

%ctor {
    if (PXHookEnabled(@"devicemodel")) {
        %init(PX_mobilegestalt);
    }
}
