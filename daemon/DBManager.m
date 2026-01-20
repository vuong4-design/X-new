#import "DBManager.h"
#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

@implementation DBManager

static NSString *PXNullableStringFromCString(const char *value) {
    if (!value) {
        return nil;
    }
    return [NSString stringWithUTF8String:value];
}

+ (instancetype)sharedManager {
    static DBManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}
- (instancetype) init{
    self = [super init];
    NSString * path = jbroot(@"/Library/IOS.db");
    if(self){
        if (sqlite3_open(path.UTF8String, &_db) != SQLITE_OK) {
            NSLog(@"[DB] 打开数据库失败: %s", sqlite3_errmsg(_db));
            _db = NULL;
        } else {
            NSLog(@"[DB] 数据库打开成功: %@", path);
        }

    }
    return self;
}
- (NSDictionary *)queryOne:(NSString *)sql {
    if (!_db || sql.length == 0) return nil;

    // 如果外部没写 LIMIT，自动补上
    if (![sql.lowercaseString containsString:@"limit"]) {
        sql = [sql stringByAppendingString:@" LIMIT 1"];
    }

    sqlite3_stmt *stmt = NULL;

    if (sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        NSLog(@"[DB] SQL 预处理失败: %s", sqlite3_errmsg(_db));
        return nil;
    }

    NSDictionary *rowDict = nil;

    if (sqlite3_step(stmt) == SQLITE_ROW) {

        int columnCount = sqlite3_column_count(stmt);
        NSMutableDictionary *row = [NSMutableDictionary dictionary];

        for (int i = 0; i < columnCount; i++) {
            const char *colNameC = sqlite3_column_name(stmt, i);
            if (!colNameC) continue;

            NSString *colName = PXNullableStringFromCString(colNameC);
            if (!colName) {
                continue;
            }
            id value = [NSNull null];

            switch (sqlite3_column_type(stmt, i)) {
                case SQLITE_INTEGER:
                    value = @(sqlite3_column_int64(stmt, i));
                    break;
                case SQLITE_FLOAT:
                    value = @(sqlite3_column_double(stmt, i));
                    break;
                case SQLITE_TEXT:
                    value = PXNullableStringFromCString((const char *)sqlite3_column_text(stmt, i)) ?: [NSNull null];
                    break;
                case SQLITE_NULL:
                    value = [NSNull null];
                    break;
                default:
                    value = [NSNull null];
            }

            row[colName] = value;
        }

        rowDict = row;
    }

    sqlite3_finalize(stmt);
    return rowDict;
}

- (NSArray<NSDictionary *> *)query:(NSString *)sql {
    NSMutableArray *result = [NSMutableArray array];
    if (!_db || sql.length == 0) return result;

    sqlite3_stmt *stmt = NULL;

    if (sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        NSLog(@"[DB] SQL 预处理失败: %s", sqlite3_errmsg(_db));
        return result;
    }

    int columnCount = sqlite3_column_count(stmt);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];

        for (int i = 0; i < columnCount; i++) {
            const char *colNameC = sqlite3_column_name(stmt, i);
            if (!colNameC) continue;

            NSString *colName = PXNullableStringFromCString(colNameC);
            if (!colName) {
                continue;
            }
            id value = [NSNull null];

            switch (sqlite3_column_type(stmt, i)) {
                case SQLITE_INTEGER:
                    value = @(sqlite3_column_int64(stmt, i));
                    break;
                case SQLITE_FLOAT:
                    value = @(sqlite3_column_double(stmt, i));
                    break;
                case SQLITE_TEXT:
                    value = PXNullableStringFromCString((const char *)sqlite3_column_text(stmt, i)) ?: [NSNull null];
                    break;
                case SQLITE_NULL:
                    value = [NSNull null];
                    break;
                default:
                    value = [NSNull null];
            }

            row[colName] = value;
        }

        [result addObject:row];
    }

    sqlite3_finalize(stmt);
    return result;
}

- (void)dealloc {
    if (_db) {
        sqlite3_close(_db);
        _db = NULL;
        NSLog(@"[DB] 数据库已关闭");
    }
}

@end
