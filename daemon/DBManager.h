#import <Foundation/Foundation.h>
#import <sqlite3.h>

@interface DBManager : NSObject {
    sqlite3 *_db;
}
+ (instancetype)sharedManager;

- (NSDictionary *)queryOne:(NSString *)sql;


/// SELECT 语句，返回数组（字典）
- (NSArray<NSDictionary *> *)query:(NSString *)sql;

@end