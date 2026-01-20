#import "SysExecutor.h"
#include <spawn.h>
#include <stdlib.h>
#import <UIKit/UIKit.h>
#import "ProjectXLogging.h"
#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

NSString *runCommand(NSString *command) {
    if ([command containsString:@"rm -rf"] &&
        ([command containsString:@"/var/lib/"] ||
         [command containsString:@"/private/var/lib/"] ||
         [command containsString:@" rm -rf /var"] ||
         [command containsString:@" rm -rf /private/var"])) {
        PXLog(@"[ProjectXDaemon] Refusing to run unsafe command: %@", command);
        return @"Refused unsafe command";
    }
    // 设置管道用于捕获输出
    int pipefd[2];
    pipe(pipefd);

    pid_t pid;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);

    // 将标准输出和错误输出重定向到管道
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);

    // 分割命令
    const char *argv[] = {jbroot("/bin/sh"), "-c", [command UTF8String], NULL};
    int status = posix_spawn(&pid, jbroot("/bin/sh"), &actions, NULL, (char *const *)argv, NULL);
    close(pipefd[1]);

    // 读取命令输出
    NSMutableData *outputData = [NSMutableData data];
    char buffer[1024];
    ssize_t bytesRead;
    while ((bytesRead = read(pipefd[0], buffer, sizeof(buffer) - 1)) > 0) {
        [outputData appendBytes:buffer length:bytesRead];
    }
    close(pipefd[0]);

    posix_spawn_file_actions_destroy(&actions);

    // 等待子进程结束
    if (status == 0) {
        int exitStatus;
        waitpid(pid, &exitStatus, 0);
    }

    // 将输出数据转换为字符串
    NSString *rawOutput = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    
    return rawOutput;
}
