#import "ProjectXLogging.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/arch.h>
#import <dlfcn.h>
#import "DataManager.h"


// Original function pointers
#import "PXHookOptions.h"
static kern_return_t (*orig_host_statistics64)(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count);
static NXArchInfo* (* orig_nx_get_local_arch_info)();



// Cache to track which memory hooks have been called for logging
static NSMutableSet *hookedMemoryAPIs;

// Cache for bundle decisions
static const NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes

// Helper for logging memory hook invocations only once
static void logMemoryHook(NSString *apiName);

// Function declarations

static float getFreeMemoryPercentage(void);
static void getConsistentMemoryStats(unsigned long long totalMemory, 
                                    unsigned long long *freeMemory,
                                    unsigned long long *wiredMemory,
                                    unsigned long long *activeMemory,
                                    unsigned long long *inactiveMemory);
static kern_return_t hook_host_statistics64(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count);
static NXArchInfo* hook_nx_get_local_arch_info();

static CGSize parseResolution(NSString *resolutionString);

#pragma mark - Helper Functions


// Parse resolution string (e.g., "2556x1179") into CGSize
static CGSize parseResolution(NSString *resolutionString) {
    if (!resolutionString) return CGSizeZero;
    
    NSArray *components = [resolutionString componentsSeparatedByString:@"x"];
    if (components.count != 2) return CGSizeZero;
    
    CGFloat width = [components[0] floatValue];
    CGFloat height = [components[1] floatValue];
    
    return CGSizeMake(width, height);
}
// 这堆修改屏幕大小的功能会导致部分应用闪退，后续作为可选配置打开
#pragma mark - UIScreen Hooks

%group PX_devicespec




%hook UIScreen

// Hook for bounds (controls size of the screen in points)
- (CGRect)bounds {
    CGRect originalBounds = %orig;
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return originalBounds;
    }
    
    // Get the viewport resolution and device pixel ratio from specs
    NSString *viewportResString = model.viewportResolution;
    CGFloat pixelRatio = [model.devicePixelRatio floatValue];
    
    if (!viewportResString || pixelRatio <= 0) {
        return originalBounds;
    }
    
    // Parse the viewport resolution
    CGSize viewportSize = parseResolution(viewportResString);
    if (CGSizeEqualToSize(viewportSize, CGSizeZero)) {
        return originalBounds;
    }
    
    // Calculate bounds in points (logical pixels)
    CGFloat width = viewportSize.width / pixelRatio;
    CGFloat height = viewportSize.height / pixelRatio;
    
    // Log the change the first time
    static BOOL loggedScreenBounds = NO;
    if (!loggedScreenBounds) {
        PXLog(@"[DeviceSpec] Spoofing UIScreen bounds from %@ to %@",
             NSStringFromCGRect(originalBounds),
             NSStringFromCGRect(CGRectMake(0, 0, width, height)));
        loggedScreenBounds = YES;
    }
    
    return CGRectMake(0, 0, width, height);
}

// Hook for nativeBounds (actual pixels)
- (CGRect)nativeBounds {
    CGRect originalNativeBounds = %orig;
    
    
    // Get the screen resolution from specs
    NSString *screenResString = CurrentPhoneInfo().deviceModel.resolution;
    if (!screenResString) {
        return originalNativeBounds;
    }
    
    // Parse the screen resolution
    CGSize screenSize = parseResolution(screenResString);
    if (CGSizeEqualToSize(screenSize, CGSizeZero)) {
        return originalNativeBounds;
    }
    
    // Log the change the first time
    static BOOL loggedNativeBounds = NO;
    if (!loggedNativeBounds) {
        PXLog(@"[DeviceSpec] Spoofing UIScreen nativeBounds from %@ to %@",
             NSStringFromCGRect(originalNativeBounds),
             NSStringFromCGRect(CGRectMake(0, 0, screenSize.width, screenSize.height)));
        loggedNativeBounds = YES;
    }
    
    return CGRectMake(0, 0, screenSize.width, screenSize.height);
}

// Hook for scale (affects UI element sizes)
- (CGFloat)scale {
    CGFloat originalScale = %orig;
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return originalScale;
    }
    
    // Get the device pixel ratio from specs
    CGFloat pixelRatio = [model.devicePixelRatio floatValue];
    if (pixelRatio <= 0) {
        return originalScale;
    }
    
    // Log the change the first time
    static BOOL loggedScale = NO;
    if (!loggedScale) {
        PXLog(@"[DeviceSpec] Spoofing UIScreen scale from %.2f to %.2f", originalScale, pixelRatio);
        loggedScale = YES;
    }
    
    return pixelRatio;
}



%end
#pragma mark - Screen Density (DPI) Hooks

%hook UIScreen

// For screen density
- (CGFloat)native_scale {
    CGFloat originalScale = %orig;
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return originalScale;
    }
    
    // Calculate from screen density (PPI)
    NSInteger screenDensity = [model.screenDensity integerValue];
    if (screenDensity <= 0) {
        return originalScale;
    }
    
    // iPhone reference point is 163 PPI for scale 1.0
    CGFloat spoofedScale = screenDensity / 163.0;
    
    // Log the change the first time
    static BOOL loggedNativeScale = NO;
    if (!loggedNativeScale) {
        PXLog(@"[DeviceSpec] Spoofing native scale from %.2f to %.2f (density: %ld PPI)",
             originalScale, spoofedScale, (long)screenDensity);
        loggedNativeScale = YES;
    }
    
    return spoofedScale;
}

%end

#pragma mark - NSProcessInfo Hooks

%hook NSProcessInfo

// Hook for physical memory (RAM)
- (unsigned long long)physicalMemory {
    unsigned long long originalMemory = %orig;  
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return originalMemory;
    }
    
    // Get the device memory from specs (in GB)
    NSInteger deviceMemoryGB = [model.deviceMemory integerValue];
    if (deviceMemoryGB <= 0) {
        return originalMemory;
    }
    
    // Convert GB to bytes
    unsigned long long spoofedMemory = deviceMemoryGB * 1024 * 1024 * 1024;
    
    // Log the change the first time
    static BOOL loggedMemory = NO;
    if (!loggedMemory) {
        PXLog(@"[DeviceSpec] Spoofing device memory from %llu bytes to %llu bytes (%ld GB)",
             originalMemory, spoofedMemory, (long)deviceMemoryGB);
        loggedMemory = YES;
    }
    
    return spoofedMemory;
}

// Add hook for macOS compatibility - similar to iOS physicalMemory
- (unsigned long long)physicalMemorySize {
    logMemoryHook(@"physicalMemorySize");
    return [self physicalMemory]; // Reuse the physicalMemory hook
}

// Add hook for total memory (used on some iOS versions)
- (unsigned long long)totalPhysicalMemory {
    logMemoryHook(@"totalPhysicalMemory");
    return [self physicalMemory]; // Reuse the physicalMemory hook
}

// Hook for available memory
- (unsigned long long)availableMemory {
    unsigned long long originalAvailableMemory = %orig;
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return originalAvailableMemory;
    }
    
    // Get the device memory from specs (in GB)
    NSInteger deviceMemoryGB = [model.deviceMemory integerValue];
    if (deviceMemoryGB <= 0) {
        return originalAvailableMemory;
    }
    
    // Calculate total memory
    unsigned long long totalMemory = deviceMemoryGB * 1024 * 1024 * 1024;
    
    // Calculate free memory based on typical iOS behavior
    float freePercentage = getFreeMemoryPercentage();
    unsigned long long spoofedAvailableMemory = (unsigned long long)(totalMemory * freePercentage);
    
    // Log the change the first time
    static BOOL loggedAvailableMemory = NO;
    if (!loggedAvailableMemory) {
        PXLog(@"[DeviceSpec] Spoofing available memory from %llu bytes to %llu bytes (%.1f%% of %ld GB)",
             originalAvailableMemory, spoofedAvailableMemory, freePercentage * 100, (long)deviceMemoryGB);
        loggedAvailableMemory = YES;
    }
    
    return spoofedAvailableMemory;
}

// Hook for processor count
- (NSUInteger)processorCount {
    NSUInteger originalCount = %orig;
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return originalCount;
    }
    
    // Get CPU core count from specs
    NSInteger cpuCoreCount = [model.cpuCoreCount integerValue];
    if (cpuCoreCount <= 0) {
        return originalCount;
    }
    
    // Log the change the first time
    static BOOL loggedProcessorCount = NO;
    if (!loggedProcessorCount) {
        PXLog(@"[DeviceSpec] Spoofing processor count from %lu to %ld",
             (unsigned long)originalCount, (long)cpuCoreCount);
        loggedProcessorCount = YES;
    }
    
    return cpuCoreCount;
}

// Add hook for CPU architecture information
- (NSString *)machineHardwareName {
    NSString *originalName = %orig;
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return originalName;
    }
    
    // Get CPU architecture from specs
    NSString *cpuArchitecture = model.cpuArchitecture;
    if (!cpuArchitecture || cpuArchitecture.length == 0) {
        return originalName;
    }
    
    // Log the change the first time
    static BOOL loggedMachineHardwareName = NO;
    if (!loggedMachineHardwareName) {
        PXLog(@"[DeviceSpec] Spoofing machine hardware name from '%@' to '%@'",
             originalName, cpuArchitecture);
        loggedMachineHardwareName = YES;
    }
    
    return cpuArchitecture;
}

%end

#pragma mark - Device Memory JS API Hooks

// JavaScript deviceMemory API hook
%hook WKWebView

// Inject JavaScript to override navigator.deviceMemory
- (void)_didFinishLoadForFrame:(WKFrameInfo *)frame {
    %orig;
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return;
    }
    
    // Get the device memory from specs (in GB)
    NSInteger deviceMemoryGB = [model.deviceMemory integerValue];
    if (deviceMemoryGB <= 0) {
        return;
    }
    
    // Create JavaScript to override navigator.deviceMemory
    NSString *script = [NSString stringWithFormat:
                      @"(function() {"
                      @"  Object.defineProperty(navigator, 'deviceMemory', {"
                      @"    value: %ld,"
                      @"    writable: false,"
                      @"    configurable: true"
                      @"  });"
                      @"})();", (long)deviceMemoryGB];
    
    // Execute the script
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[DeviceSpec] Error injecting deviceMemory script: %@", error);
        } else {
            static BOOL loggedDeviceMemory = NO;
            if (!loggedDeviceMemory) {
                PXLog(@"[DeviceSpec] Successfully spoofed navigator.deviceMemory to %ld GB", (long)deviceMemoryGB);
                loggedDeviceMemory = YES;
            }
        }
    }];
}

%end

#pragma mark - WebGL Info Hooks

%hook WebGLRenderingContext

// Hook for WebGL vendor and renderer strings
- (NSString *)getParameter:(unsigned)pname {
    NSString *original = %orig;
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return original;
    }
    
    WebGLInfo *webGLInfo = model.webGLInfo;
    if (!webGLInfo) {
        return original;
    }
    
    // Map WebGL parameter constants to our stored values
    // VENDOR = 0x1F00, RENDERER = 0x1F01, VERSION = 0x1F02
    NSString *spoofedValue = nil;
    
    if (pname == 0x1F00) { // VENDOR
        spoofedValue = webGLInfo.webglVendor;
    } else if (pname == 0x1F01) { // RENDERER
        spoofedValue = webGLInfo.webglRenderer;
    } else if (pname == 0x1F02) { // VERSION
        spoofedValue = webGLInfo.webglVersion;
    } else if (pname == 0x8B4F || pname == 0x8B4E) { // UNMASKED_VENDOR_WEBGL or UNMASKED_RENDERER_WEBGL
        spoofedValue = (pname == 0x8B4F) ? webGLInfo.unmaskedVendor : webGLInfo.unmaskedRenderer;
    } else if (pname == 0x0D33) { // MAX_TEXTURE_SIZE
        return [NSString stringWithFormat:@"%@", webGLInfo.maxTextureSize];
    } else if (pname == 0x8D57) { // MAX_RENDERBUFFER_SIZE
        return [NSString stringWithFormat:@"%@", webGLInfo.maxRenderBufferSize];
    }
    
    if (spoofedValue) {
        static NSMutableSet *loggedParameters = nil;
        if (!loggedParameters) {
            loggedParameters = [NSMutableSet set];
        }
        
        NSString *paramKey = [NSString stringWithFormat:@"%u", pname];
        if (![loggedParameters containsObject:paramKey]) {
            [loggedParameters addObject:paramKey];
            PXLog(@"[DeviceSpec] Spoofing WebGL parameter 0x%X from '%@' to '%@'", pname, original, spoofedValue);
        }
        
        return spoofedValue;
    }
    
    return original;
}

%end

#pragma mark - Metal API Hooks

%hook MTLDevice

// Hook for name property
- (NSString *)name {
    NSString *originalName = %orig;
    
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return originalName;
    }
    
    NSString *gpuFamily = model.gpuFamily;
    if (!gpuFamily) {
        return originalName;
    }
    
    // Log the change the first time
    static BOOL loggedGPUName = NO;
    if (!loggedGPUName) {
        PXLog(@"[DeviceSpec] Spoofing GPU name from '%@' to '%@'", originalName, gpuFamily);
        loggedGPUName = YES;
    }
    
    return gpuFamily;
}

// Also hook the family name property
- (NSString *)familyName {
    NSString *originalFamilyName = %orig;
    
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return originalFamilyName;
    }
    
    NSString *gpuFamily = model.gpuFamily;
    if (!gpuFamily) {
        return originalFamilyName;
    }
    
    // Log the change the first time
    static BOOL loggedGPUFamilyName = NO;
    if (!loggedGPUFamilyName) {
        PXLog(@"[DeviceSpec] Spoofing GPU family name from '%@' to '%@'", originalFamilyName, gpuFamily);
        loggedGPUFamilyName = YES;
    }
    
    return gpuFamily;
}

%end


#pragma mark - JavaScript WebKit Feature Detection Hooks

%hook WKWebView

// Hook document.load to inject our custom JavaScript for device spoofing
- (void)_documentDidFinishLoadForFrame:(WKFrameInfo *)frame {
    %orig;
    
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if(!model){
        return;
    }
    
    NSString *deviceModel = model.modelName;
    if (!deviceModel) {
        return;
    }
    
    // Prepare values from specs
    NSString *screenResolution = model.resolution ?: @"";
    CGFloat devicePixelRatio = [model.devicePixelRatio floatValue];
    NSInteger deviceMemory = [model.deviceMemory integerValue];
    NSInteger cpuCoreCount = [model.cpuCoreCount integerValue];
    
    // Create a comprehensive JavaScript to override browser properties
    NSString *script = [NSString stringWithFormat:
                      @"(function() {"
                      // Device memory
                      @"  if ('deviceMemory' in navigator) {"
                      @"    Object.defineProperty(navigator, 'deviceMemory', { value: %ld, writable: false });"
                      @"  }"
                      
                      // Hardware concurrency (CPU cores)
                      @"  if ('hardwareConcurrency' in navigator) {"
                      @"    Object.defineProperty(navigator, 'hardwareConcurrency', { value: %ld, writable: false });"
                      @"  }"
                      
                      // Device pixel ratio
                      @"  if ('devicePixelRatio' in window) {"
                      @"    Object.defineProperty(window, 'devicePixelRatio', { value: %.2f, writable: false });"
                      @"  }"
                      
                      // Screen properties
                      @"  if ('screen' in window) {"
                      @"    var res = '%@'.split('x');"
                      @"    var w = parseInt(res[0], 10) || screen.width;"
                      @"    var h = parseInt(res[1], 10) || screen.height;"
                      @"    Object.defineProperty(screen, 'width', { value: w, writable: false });"
                      @"    Object.defineProperty(screen, 'height', { value: h, writable: false });"
                      @"    Object.defineProperty(screen, 'availWidth', { value: w, writable: false });"
                      @"    Object.defineProperty(screen, 'availHeight', { value: h, writable: false });"
                      @"  }"
                      
                      // Window dimensions - critical for browser fingerprinting
                      @"  if ('innerWidth' in window) {"
                      @"    var res = '%@'.split('x');"
                      @"    var w = parseInt(res[0], 10) / %.2f || window.innerWidth;"
                      @"    var h = parseInt(res[1], 10) / %.2f || window.innerHeight;"
                      @"    Object.defineProperty(window, 'innerWidth', { "
                      @"      get: function() { return Math.floor(w); },"
                      @"      configurable: true"
                      @"    });"
                      @"    Object.defineProperty(window, 'innerHeight', { "
                      @"      get: function() { return Math.floor(h); },"
                      @"      configurable: true"
                      @"    });"
                      @"  }"
                      
                      // Outer window dimensions
                      @"  if ('outerWidth' in window) {"
                      @"    var res = '%@'.split('x');"
                      @"    var w = parseInt(res[0], 10) / %.2f || window.outerWidth;"
                      @"    var h = parseInt(res[1], 10) / %.2f || window.outerHeight;"
                      @"    // Add small offset to simulate browser chrome"
                      @"    Object.defineProperty(window, 'outerWidth', { "
                      @"      get: function() { return Math.floor(w) + 16; },"
                      @"      configurable: true"
                      @"    });"
                      @"    Object.defineProperty(window, 'outerHeight', { "
                      @"      get: function() { return Math.floor(h) + 88; },"
                      @"      configurable: true"
                      @"    });"
                      @"  }"
                      
                      // User agent manipulation if needed
                      // Note: Generally better to spoof UA at the HTTP header level
                      
                      // Additional WebGL spoofing if needed
                      @"})();",
                      (long)deviceMemory,
                      (long)cpuCoreCount,
                      devicePixelRatio,
                      screenResolution,
                      // Parameters for inner window size
                      screenResolution,
                      devicePixelRatio,
                      devicePixelRatio,
                      // Parameters for outer window size
                      screenResolution,
                      devicePixelRatio,
                      devicePixelRatio];
    
    // Execute the script
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[DeviceSpec] Error injecting device properties script: %@", error);
        } else {
            static BOOL loggedJSInjection = NO;
            if (!loggedJSInjection) {
                PXLog(@"[DeviceSpec] Successfully injected device properties for %@", deviceModel);
                loggedJSInjection = YES;
            }
        }
    }];
}

%end

#pragma mark - Notification Handlers



#pragma mark - Canvas Fingerprinting Protection

// Add hooks for canvas toDataURL and getImageData to prevent canvas fingerprinting
%hook WKWebView

// Add JavaScript to protect against canvas fingerprinting 
- (void)_didCreateMainFrame:(WKFrameInfo *)frame {
    %orig;
    
    
    NSString *deviceModel = CurrentPhoneInfo().deviceModel.modelName;
    if (!deviceModel) {
        return;
    }
    
    // Create a hash value from the device model to generate consistent noise
    NSUInteger deviceModelHash = [deviceModel hash];
    
    // This script adds noise to canvas operations in a way that's consistent for the same device model
    NSString *canvasProtectionScript = [NSString stringWithFormat:
                                       @"(function() {"
                                       // Store original methods before modifying them
                                       @"  const origToDataURL = HTMLCanvasElement.prototype.toDataURL;"
                                       @"  const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;"
                                       @"  const origReadPixels = WebGLRenderingContext.prototype.readPixels;"
                                       
                                       // Define a noise function based on spoofed device model
                                       @"  const deviceSeed = %lu;"
                                       @"  function generateNoise(input) {"
                                       @"    let hash = (deviceSeed * 131 + input) & 0xFFFFFFFF;"
                                       @"    return (hash / 0xFFFFFFFF) * 2 - 1;"  // -1 to +1 range
                                       @"  }"
                                       
                                       // Hook 2D Canvas toDataURL
                                       @"  HTMLCanvasElement.prototype.toDataURL = function() {"
                                       @"    try {"
                                       @"      const context = this.getContext('2d');"
                                       @"      if (context && this.width > 16 && this.height > 16) {"
                                       @"        // Subtly modify the canvas content in a consistent way"
                                       @"        const imgData = context.getImageData(0, 0, 2, 2);"
                                       @"        if (imgData && imgData.data) {"
                                       @"          // Add subtle, deterministic noise to a small portion"
                                       @"          for (let i = 0; i < imgData.data.length; i += 4) {"
                                       @"            const noise = generateNoise(i) * 0.5;"
                                       @"            imgData.data[i] = Math.min(255, Math.max(0, imgData.data[i] + noise));"
                                       @"          }"
                                       @"          context.putImageData(imgData, 0, 0);"
                                       @"        }"
                                       @"      }"
                                       @"    } catch(e) {}"
                                       @"    return origToDataURL.apply(this, arguments);"
                                       @"  };"
                                       
                                       // Hook 2D Canvas getImageData
                                       @"  CanvasRenderingContext2D.prototype.getImageData = function() {"
                                       @"    const imgData = origGetImageData.apply(this, arguments);"
                                       @"    try {"
                                       @"      // Add consistent noise to the image data"
                                       @"      if (imgData && imgData.data && imgData.data.length > 0) {"
                                       @"        // Only modify a small percentage of pixels to avoid visual detection"
                                       @"        for (let i = 0; i < imgData.data.length; i += 40) {"
                                       @"          const noise = generateNoise(i) * 1.0;"
                                       @"          imgData.data[i] = Math.min(255, Math.max(0, imgData.data[i] + noise));"
                                       @"        }"
                                       @"      }"
                                       @"    } catch(e) {}"
                                       @"    return imgData;"
                                       @"  };"
                                       
                                       // Hook WebGL readPixels
                                       @"  WebGLRenderingContext.prototype.readPixels = function(x, y, width, height, format, type, pixels) {"
                                       @"    // First perform the regular pixel read"
                                       @"    origReadPixels.apply(this, arguments);"
                                       @"    try {"
                                       @"      // Then apply consistent noise to the output"
                                       @"      if (pixels && pixels.length > 0) {"
                                       @"        for (let i = 0; i < pixels.length; i += 50) {"
                                       @"          const pixelIndex = i %% pixels.length;"
                                       @"          const noise = generateNoise(pixelIndex) * 1.0;"
                                       @"          pixels[pixelIndex] = Math.min(255, Math.max(0, pixels[pixelIndex] + noise));"
                                       @"        }"
                                       @"      }"
                                       @"    } catch(e) {}"
                                       @"    return;"
                                       @"  };"
                                       
                                       // Prevent canvas font fingerprinting
                                       @"  const origMeasureText = CanvasRenderingContext2D.prototype.measureText;"
                                       @"  CanvasRenderingContext2D.prototype.measureText = function(text) {"
                                       @"    const result = origMeasureText.apply(this, arguments);"
                                       @"    // Add tiny noise to font measurement consistent with device model"
                                       @"    const noise = (generateNoise(text.length) * 0.1) + 1.0;"
                                       @"    const origWidth = result.width;"
                                       @"    Object.defineProperty(result, 'width', { value: origWidth * noise });"
                                       @"    return result;"
                                       @"  };"
                                       
                                       // Extra protection for text rendering
                                       @"  const origFillText = CanvasRenderingContext2D.prototype.fillText;"
                                       @"  CanvasRenderingContext2D.prototype.fillText = function(text, x, y, maxWidth) {"
                                       @"    // Add subtle position variation consistent with device model"
                                       @"    const xNoise = generateNoise(text.length * 31) * 0.2;"
                                       @"    const yNoise = generateNoise(text.length * 37) * 0.2;"
                                       @"    const newX = x + xNoise;"
                                       @"    const newY = y + yNoise;"
                                       @"    if (arguments.length < 4) {"
                                       @"      return origFillText.call(this, text, newX, newY);"
                                       @"    } else {"
                                       @"      return origFillText.call(this, text, newX, newY, maxWidth);"
                                       @"    }"
                                       @"  };"
                                       
                                       @"})();",
                                       (unsigned long)deviceModelHash];
    
    // Execute the script
    [self evaluateJavaScript:canvasProtectionScript completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[DeviceSpec] Error injecting canvas protection script: %@", error);
        } else {
            static BOOL loggedCanvasProtection = NO;
            if (!loggedCanvasProtection) {
                PXLog(@"[DeviceSpec] Successfully injected canvas fingerprinting protection for %@", deviceModel);
                loggedCanvasProtection = YES;
            }
        }
    }];
}

%end

#pragma mark - CPU Core Spoofing Enhancements

// Add an early hook to ensure CPU core count is spoofed as early as possible
%hook WKWebView

// Hook page initialization to spoof cores early
- (void)_didStartProvisionalLoadForFrame:(WKFrameInfo *)frame {
    %orig;
    
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return;
    }
    
    NSInteger cpuCoreCount = [model.cpuCoreCount integerValue];
    if (cpuCoreCount <= 0) {
        return;
    }
    
    // Immediately inject CPU core count at load start
    NSString *script = [NSString stringWithFormat:
                        @"(function() {"
                        @"  if ('hardwareConcurrency' in navigator) {"
                        @"    Object.defineProperty(navigator, 'hardwareConcurrency', {"
                        @"      value: %ld,"
                        @"      writable: false,"
                        @"      configurable: true"
                        @"    });"
                        @"  }"
                        @"})();", (long)cpuCoreCount];
    
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[DeviceSpec] Early CPU core spoof error: %@", error);
        }
    }];
}

// Hook JavaScript context creation to spoof core count at the earliest possible moment
- (void)_didCreateJavaScriptContext:(id)context {
    %orig;
    
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return;
    }
    
    NSInteger cpuCoreCount = [model.cpuCoreCount integerValue];
    if (cpuCoreCount <= 0) {
        return;
    }
    
    NSString *script = [NSString stringWithFormat:
                        @"if ('hardwareConcurrency' in navigator) {"
                        @"  Object.defineProperty(navigator, 'hardwareConcurrency', {"
                        @"    value: %ld,"
                        @"    writable: false,"
                        @"    configurable: true"
                        @"  });"
                        @"}", (long)cpuCoreCount];
    
    [self evaluateJavaScript:script completionHandler:nil];
}

%end

// Hook lower-level CPU detection APIs for native apps
%hook host_basic_info

- (unsigned int)max_cpus {
    unsigned int original = %orig;
    
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return original;
    }
    
    NSInteger cpuCoreCount = [model.cpuCoreCount integerValue];
    if (cpuCoreCount <= 0) {
        return original;
    }
    
    static BOOL loggedCoreAPI = NO;
    if (!loggedCoreAPI) {
        PXLog(@"[DeviceSpec] Spoofing low-level CPU API from %u to %ld", original, (long)cpuCoreCount);
        loggedCoreAPI = YES;
    }
    
    return (unsigned int)cpuCoreCount;
}

%end


// Helper for logging memory hook invocations only once
static void logMemoryHook(NSString *apiName) {
    if (!hookedMemoryAPIs) {
        hookedMemoryAPIs = [NSMutableSet set];
    }
    
    if (![hookedMemoryAPIs containsObject:apiName]) {
        [hookedMemoryAPIs addObject:apiName];
        PXLog(@"[DeviceSpec] Memory spoofing API '%@' was accessed", apiName);
    }
}
// Function to calculate free memory percentage based on device specs
static float getFreeMemoryPercentage(void) {
    // Default free memory percentage (typical for iOS devices under normal usage)
    float defaultFreePercentage = 0.35; // 35% free
    
    
    // Get device specs
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return defaultFreePercentage;
    }
    
    
    // Otherwise use a realistic value based on device memory
    NSInteger deviceMemoryGB = [model.deviceMemory integerValue];
    if (deviceMemoryGB <= 0) {
        return defaultFreePercentage;
    }
    
    // Larger memory devices typically have higher free percentage
    if (deviceMemoryGB >= 6) {
        return 0.45; // 45% free for 6GB+ devices
    } else if (deviceMemoryGB >= 4) {
        return 0.40; // 40% free for 4GB devices
    } else if (deviceMemoryGB >= 3) {
        return 0.35; // 35% free for 3GB devices
    } else {
        return 0.30; // 30% free for smaller memory devices
    }
}

// Function to get consistent free/wired/active memory values based on total memory
static void getConsistentMemoryStats(unsigned long long totalMemory, 
                                    unsigned long long *freeMemory,
                                    unsigned long long *wiredMemory,
                                    unsigned long long *activeMemory,
                                    unsigned long long *inactiveMemory) {
    
    float freePercentage = getFreeMemoryPercentage();
    float wiredPercentage = 0.20; // 20% wired (kernel, system)
    float activePercentage = 0.30; // 30% active (running apps)
    float inactivePercentage = 1.0 - freePercentage - wiredPercentage - activePercentage;
    
    if (freeMemory) {
        *freeMemory = (unsigned long long)(totalMemory * freePercentage);
    }
    
    if (wiredMemory) {
        *wiredMemory = (unsigned long long)(totalMemory * wiredPercentage);
    }
    
    if (activeMemory) {
        *activeMemory = (unsigned long long)(totalMemory * activePercentage);
    }
    
    if (inactiveMemory) {
        *inactiveMemory = (unsigned long long)(totalMemory * inactivePercentage);
    }
}
static NXArchInfo* hook_nx_get_local_arch_info()
{
    if (!orig_nx_get_local_arch_info) {
        return NULL;
    }
    NXArchInfo* original = orig_nx_get_local_arch_info();
    
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return original;
    }
    
    NSString *cpuArchitecture = model.cpuArchitecture;
    if (!cpuArchitecture) {
        return original;
    }
    
    // 创建新的结构体，不要修改原始结构体
    static NXArchInfo customArchInfo;
    customArchInfo = *original; // 复制原始值
    
    // 安全地设置 subtype
    cpu_subtype_t cpuSubtype = original->cpusubtype; // 保持原始值
    const char *customDescription = original->description; // 默认使用原始描述
    
    // 根据架构设置 subtype 和描述
    if ([cpuArchitecture containsString:@"A9"]) {
        cpuSubtype = 2;
    } else if ([cpuArchitecture containsString:@"A10"]) {
        cpuSubtype = 3;
    } else if ([cpuArchitecture containsString:@"A11"]) {
        cpuSubtype = 4;
        customDescription = "ARM64E";
    } else if ([cpuArchitecture containsString:@"A12"]) {
        cpuSubtype = 5;
        customDescription = "ARM64E";
    } else if ([cpuArchitecture containsString:@"A13"]) {
        cpuSubtype = 6;
        customDescription = "ARM64E";
    } else if ([cpuArchitecture containsString:@"A14"]) {
        cpuSubtype = 7;
        customDescription = "ARM64E";
    } else if ([cpuArchitecture containsString:@"A15"]) {
        cpuSubtype = 8;
        customDescription = "ARM64E";
    } else if ([cpuArchitecture containsString:@"A16"]) {
        cpuSubtype = 9;
        customDescription = "ARM64E";
    } else if ([cpuArchitecture containsString:@"A17"]) {
        cpuSubtype = 10;
        customDescription = "ARM64E";
    } else if ([cpuArchitecture containsString:@"A18"]) {
        cpuSubtype = 11;
        customDescription = "ARM64E";
    } else if ([cpuArchitecture containsString:@"M1"]) {
        cpuSubtype = 12;
        customDescription = "arm64v8 Apple M1";
    } else if ([cpuArchitecture containsString:@"M2"]) {
        cpuSubtype = 13;
        customDescription = "arm64v8 Apple M2";
    } else if ([cpuArchitecture containsString:@"M3"]) {
        cpuSubtype = 14;
        customDescription = "arm64v8 Apple M3";
    } else if ([cpuArchitecture containsString:@"M4"]) {
        cpuSubtype = 15;
        customDescription = "arm64v8 Apple M4";
    }
    // 如果没有匹配，保持原始 subtype 和描述
    
    customArchInfo.cpusubtype = cpuSubtype;
    customArchInfo.description = customDescription;
    
    PXLog(@"[DeviceSpec] ArchInfo hook - name:%s cputype:%d cpusubtype:%d->%d description:%s->%s",
          customArchInfo.name, 
          customArchInfo.cputype, 
          original->cpusubtype, 
          cpuSubtype,
          original->description,
          customDescription);
    
    return &customArchInfo;
}
// Host statistics hook for memory stats
static kern_return_t hook_host_statistics64(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count) {
    // Call original function first
    if (!orig_host_statistics64) {
        return KERN_FAILURE;
    }
    kern_return_t result = orig_host_statistics64(host, flavor, info, count);
    
    // Check if we should modify the result
    if (result != KERN_SUCCESS || !info) {
        return result;
    }
    
    // Get device specs
    DeviceModel *model = CurrentPhoneInfo().deviceModel;
    if (!model) {
        return result;
    }
    
    // Get the device memory from specs (in GB)
    NSInteger deviceMemoryGB = [model.deviceMemory integerValue];
    if (deviceMemoryGB <= 0) {
        return result;
    }
    
    // Calculate total memory in bytes
    unsigned long long totalMemory = deviceMemoryGB * 1024 * 1024 * 1024;
    
    // Handle specific host info types
    if (flavor == HOST_VM_INFO64 || flavor == HOST_VM_INFO) {
        // VM statistics (free memory, etc.)
        if (flavor == HOST_VM_INFO64 && *count >= HOST_VM_INFO64_COUNT) {
            vm_statistics64_data_t *vmStats = (vm_statistics64_data_t *)info;
            
            // Calculate consistent memory values
            unsigned long long freeMemory, wiredMemory, activeMemory, inactiveMemory;
            getConsistentMemoryStats(totalMemory, &freeMemory, &wiredMemory, &activeMemory, &inactiveMemory);
            
            // page size is typically 4096 or 16384 depending on device
            vm_size_t pageSize = 4096;
            host_page_size(host, &pageSize);
            
            // Convert bytes to pages
            uint64_t freePages = freeMemory / pageSize;
            uint64_t wiredPages = wiredMemory / pageSize;
            uint64_t activePages = activeMemory / pageSize;
            uint64_t inactivePages = inactiveMemory / pageSize;
            
            // Update stats consistently
            vmStats->free_count = freePages;
            vmStats->wire_count = wiredPages;
            vmStats->active_count = activePages;
            vmStats->inactive_count = inactivePages;
            
            // Log the change the first time
            static BOOL loggedVMStats = NO;
            if (!loggedVMStats) {
                PXLog(@"[DeviceSpec] Spoofed vm_statistics64 with %llu free pages (%.1f%% of total memory)",
                    freePages, (float)freeMemory * 100.0 / totalMemory);
                loggedVMStats = YES;
            }
        } else if (flavor == HOST_VM_INFO && *count >= HOST_VM_INFO_COUNT) {
            vm_statistics_data_t *vmStats = (vm_statistics_data_t *)info;
            
            // Calculate consistent memory values
            unsigned long long freeMemory, wiredMemory, activeMemory, inactiveMemory;
            getConsistentMemoryStats(totalMemory, &freeMemory, &wiredMemory, &activeMemory, &inactiveMemory);
            
            // page size is typically 4096 or 16384 depending on device
            vm_size_t pageSize = 4096;
            host_page_size(host, &pageSize);
            
            // Convert bytes to pages
            unsigned int freePages = (unsigned int)(freeMemory / pageSize);
            unsigned int wiredPages = (unsigned int)(wiredMemory / pageSize);
            unsigned int activePages = (unsigned int)(activeMemory / pageSize);
            unsigned int inactivePages = (unsigned int)(inactiveMemory / pageSize);
            
            // Update stats consistently
            vmStats->free_count = freePages;
            vmStats->wire_count = wiredPages;
            vmStats->active_count = activePages;
            vmStats->inactive_count = inactivePages;
            
            // Log the change the first time
            static BOOL loggedVMStats32 = NO;
            if (!loggedVMStats32) {
                PXLog(@"[DeviceSpec] Spoofed vm_statistics with %u free pages (%.1f%% of total memory)",
                    freePages, (float)freeMemory * 100.0 / totalMemory);
                loggedVMStats32 = YES;
            }
        }
    } else if (flavor == HOST_BASIC_INFO) {
        // Basic host info including memory size
        if (*count >= HOST_BASIC_INFO_COUNT) {
            host_basic_info_t basicInfo = (host_basic_info_t)info;
            
            // Spoof max memory to match our deviceMemory value
            basicInfo->max_mem = totalMemory;
            
            // Log the change the first time
            static BOOL loggedBasicInfo = NO;
            if (!loggedBasicInfo) {
                PXLog(@"[DeviceSpec] Spoofed host_basic_info max_mem to %llu bytes (%ld GB)",
                    totalMemory, (long)deviceMemoryGB);
                loggedBasicInfo = YES;
            }
        }
    }
    
    return result;
}




#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        @try {
            PXLog(@"[DeviceSpec] Initializing device specifications spoofing hooks");
                        
            // Initialize memory hook function pointers for scoped apps only
            void *libSystem = dlopen("/usr/lib/libSystem.dylib", RTLD_NOW);
            if (libSystem) {
                
                // Hook host_statistics64 for VM stats spoofing
                orig_host_statistics64 = dlsym(libSystem, "host_statistics64");
                if (orig_host_statistics64) {
                    MSHookFunction(orig_host_statistics64, (void *)hook_host_statistics64, (void **)&orig_host_statistics64);
                    PXLog(@"[DeviceSpec] Successfully hooked host_statistics64 for memory stats spoofing");
                }
                
                orig_nx_get_local_arch_info = dlsym(libSystem, "NXGetLocalArchInfo");
                if(orig_nx_get_local_arch_info){
                    MSHookFunction(orig_nx_get_local_arch_info, (void *)hook_nx_get_local_arch_info, (void **)&orig_nx_get_local_arch_info);
                    PXLog(@"[DeviceSpec] Successfully hooked nx_get_local_arch_info for memory stats spoofing");
                }
                dlclose(libSystem);
            }
            
            // Initialize Objective-C hooks for scoped apps only
            %init;
            
            PXLog(@"[DeviceSpec] Device specification hooks successfully initialized for scoped app");
            
        } @catch (NSException *e) {
            PXLog(@"[DeviceSpec] ❌ Exception in constructor: %@", e);
        }
    }
}

%end

%ctor {
    if (PXHookEnabled(@"devicespec")) {
        %init(PX_devicespec);
    }
}
