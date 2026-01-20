#ifndef CMD_EXE
#define CMD_EXE
#import <UIKit/UIKit.h>

// 声明一个类方法来执行命令并返回输出
NSString *runCommand(NSString *command);

void stopAppByBundleID(NSString *bundleID);
#endif

