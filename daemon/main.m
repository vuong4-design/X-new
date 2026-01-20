#import <Foundation/Foundation.h>
#import "WebServerManager.h"
#import "kern_memorystatus.h"

int main(int argc, char *argv[]) {
    int rc;
    
    memorystatus_priority_properties_t props = {0, JETSAM_PRIORITY_CRITICAL};
    rc = memorystatus_control(MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES, getpid(), 0, &props, sizeof(props));
    if (rc < 0) { perror ("memorystatus_control"); exit(rc);}
    
    rc = memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK, getpid(), -1, NULL, 0);
    if (rc < 0) { perror ("memorystatus_control"); exit(rc);}
    
    rc = memorystatus_control(MEMORYSTATUS_CMD_SET_PROCESS_IS_MANAGED, getpid(), 0, NULL, 0);
    if (rc < 0) { perror ("memorystatus_control"); exit(rc);}
    
    rc = memorystatus_control(MEMORYSTATUS_CMD_SET_PROCESS_IS_FREEZABLE, getpid(), 0, NULL, 0);
    if (rc < 0) { perror ("memorystatus_control"); exit(rc); }

    @autoreleasepool {
        // 启动 Web 服务器
        [WebServerManager startWebServer];
        
        // 获取当前 RunLoop
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        
        // 添加一个永远不触发的定时器（技巧性保持 RunLoop 运行）
        NSTimer *keepAliveTimer = [NSTimer timerWithTimeInterval:DBL_MAX
                                                         repeats:YES
                                                           block:^(NSTimer * _Nonnull timer) {
            // 什么都不做，只是为了保持 RunLoop
        }];
        [runLoop addTimer:keepAliveTimer forMode:NSDefaultRunLoopMode];
        
        // 保持 RunLoop 运行直到程序终止
        [runLoop run];
    }
    return 0;
}