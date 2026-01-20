#import <Foundation/Foundation.h>

@class Profile;

NS_ASSUME_NONNULL_BEGIN

@interface Profile : NSObject <NSSecureCoding>

@property (nonatomic, strong) NSString *id;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSDate *createdDate;
- (NSDictionary *)toDictionary;
@end

@interface ProfileManager : NSObject

@property (nonatomic, strong) NSMutableArray<Profile *> *mutableProfiles;
@property (nonatomic, strong) NSString *currentId;
+ (instancetype)sharedManager;
- (NSString *)genBackupDirectory;

// Profile ID generation
- (NSString *)generateProfileID;
- (NSString *)profileIdentityPath;
- (NSString *)getActiveProfileId;
- (NSString *)getActiveDataPath;
- (Profile *) getProfileById:(NSString *) id;

- (void)switchToProfile:(Profile *)profile;
- (void)renameProfile:(NSString *)id to:(NSString *)newName;
- (BOOL)remove:(Profile *)profile;
- (BOOL)isCurrent:(Profile *)profile;
- (BOOL) removeProfileById:(NSString *) id;

- (BOOL)saveData;
- (BOOL)loadData;
- (BOOL)clearData;

@end

NS_ASSUME_NONNULL_END 