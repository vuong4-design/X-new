#import "DataGenManager.h"
#import <sys/sysctl.h> 
#import <ifaddrs.h>
#import <arpa/inet.h>
#import "DBManager.h"
#import "SettingManager.h"
#import <UIKit/UIKit.h>

static NSString *ProjectXSysctlString(const char *name) {
    size_t size = 0;
    sysctlbyname(name, NULL, &size, NULL, 0);
    if (size == 0) {
        return @"";
    }
    char *value = malloc(size);
    if (!value) {
        return @"";
    }
    sysctlbyname(name, value, &size, NULL, 0);
    NSString *result = [NSString stringWithUTF8String:value] ?: @"";
    free(value);
    return result;
}

@interface DataGenManager()
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSMutableArray <DeviceModel *> *deviceModels;
    
@end
@implementation DataGenManager
- (instancetype)init {
    if (self = [super init]) {
    }
    return self;
}
+ (instancetype)sharedManager {
    static DataGenManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (PhoneInfo *) generatePhoneInfo{
    PhoneInfo * phoneInfo = [[PhoneInfo alloc]init];
    phoneInfo.idfa = [[NSUUID UUID] UUIDString];
    phoneInfo.idfv = [[NSUUID UUID] UUIDString];
    phoneInfo.deviceName = [self generateDeviceName];
    phoneInfo.serialNumber = [self generateSerialNumber];
    phoneInfo.IMEI = [self generateIMEI];
    phoneInfo.MEID = [self generateMEID];
    [self generateIOSVersion:phoneInfo];

    phoneInfo.systemBootUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.dyldCacheUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.pasteboardUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.keychainUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.userDefaultsUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.appGroupUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.coreDataUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.appInstallUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.appContainerUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    
    // phoneInfo.storageInfo = [self generateStorage];

    phoneInfo.batteryInfo = [self generateBatteryInfo];

    phoneInfo.wifiInfo = [self generateWiFiInfo];
    // 启动时间
    phoneInfo.upTimeInfo = [self generateUpTimeInfo];

    phoneInfo.networkInfo = [self generateNetworkInfo];

    return phoneInfo;
}



-(UpTimeInfo *)generateUpTimeInfo{
    UpTimeInfo * upTimeInfo = [[UpTimeInfo alloc]init];
    NSTimeInterval minUptime = 12 * 3600; // 12 hours
    NSTimeInterval maxUptime = 48 * 3600; // 48 hours
    NSTimeInterval uptimeRange = maxUptime - minUptime;
    NSTimeInterval randomPart = arc4random_uniform((uint32_t)uptimeRange);
    NSTimeInterval extraSeconds = arc4random_uniform(60 * 45);
    NSTimeInterval uptime = minUptime + randomPart + extraSeconds;
    
    // Check real uptime to ensure spoofed value isn't higher
    struct timeval boottv = {0};
    size_t sz = sizeof(boottv);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    int sysctlResult = sysctl(mib, 2, &boottv, &sz, NULL, 0);
    if (sysctlResult == 0) {
        NSDate *realBoot = [NSDate dateWithTimeIntervalSince1970:boottv.tv_sec];
        NSTimeInterval realUptime = [[NSDate date] timeIntervalSinceDate:realBoot];
        if (uptime > realUptime - 60) {
            uptime = realUptime - 60;
        }
        if (uptime < minUptime) uptime = minUptime;
    }
    
    // Also save to system_uptime.plist for apps that might look there
    // NSString *uptimeString = [NSString stringWithFormat:@"%.0f", uptime];

    upTimeInfo.upTime = uptime;

    // Calculate boot time based on generated uptime
    NSDate *bootTime = [NSDate dateWithTimeIntervalSinceNow:-uptime];
    upTimeInfo.bootTime = bootTime;   
    return upTimeInfo;
}

- (WifiInfo *)generateWiFiInfo {
    self.error = nil;
    
    // Generate random US-style WiFi network information

    // US ISP providers
    NSArray *usProviders = @[
        // Major national ISPs
        @"Xfinity", @"Spectrum", @"ATT", @"Verizon", @"CenturyLink", @"Cox", @"Frontier",
        @"Optimum", @"Suddenlink", @"WOW", @"Mediacom", @"Windstream", @"Sparklight",
        // Regional ISPs
        @"RCN", @"Grande", @"Wave", @"Armstrong", @"WideOpenWest", @"MetroNet", @"Ziply",
        @"Sonic", @"Earthlink", @"HughesNet", @"TDS", @"Consolidated", @"Fairpoint",
        // Cable providers
        @"Comcast", @"TimeWarner", @"Charter", @"BrightHouse", @"Cablevision", @"GCI",
        // Fiber/specialized providers
        @"GoogleFiber", @"FiOS", @"AT&T-Fiber", @"CenturyLink-Fiber", @"Webpass",
        // Mobile hotspot providers
        @"TMobile", @"Sprint", @"USCellular", @"Cricket", @"MetroPCS", @"Boost"
    ];
    
    // US WiFi suffixes and modifiers
    NSArray *usSuffixes = @[
        // Empty/standard
        @"", @"WiFi", @"WLAN", @"Net", @"Network", @"Internet",
        // Band identifiers
        @"-5G", @"-5GHz", @"-2G", @"-2.4", @"-2.4GHz", @"-6G", @"-6GHz", @"_5G", @"_2G",
        // Location/purpose
        @"-Home", @"-Office", @"-Guest", @"-IoT", @"-ExtWifi", @"-Mesh", @"-Basement", 
        @"-Upstairs", @"-Kitchen", @"-Backyard", @"-Patio", @"-Garage", @"-Private", 
        @"-Family", @"-Apartment", @"-Condo", @"-Suite", @"-Lobby",
        // Security identifiers
        @"_Secure", @"-Secure", @"-Protected", @"-WPA2", @"-WPA3", @"_EXT", @"-EXT",
        // Dynamic additions
        @"-MESH", @"-AP", @"-Hub", @"-NODE1", @"-POD", @"-REPEATER", @"-EXTENDER"
    ];
    
    // Router brand names popular in the US
    NSArray *routerBrands = @[
        @"NETGEAR", @"Linksys", @"TP-Link", @"ASUS", @"ORBI", @"Eero", @"Google-WiFi",
        @"Nest-WiFi", @"Nighthawk", @"Apple", @"Amazon", @"ARRIS", @"Motorola", @"Ubiquiti",
        @"AmpliFi", @"D-Link", @"Belkin", @"Buffalo", @"Cisco", @"EnGenius", @"Tenda"
    ];
    
    // Common US last names
    NSArray *commonLastNames = @[
        @"Smith", @"Johnson", @"Williams", @"Jones", @"Brown", @"Miller", @"Davis",
        @"Wilson", @"Anderson", @"Thomas", @"Taylor", @"Moore", @"White", @"Harris",
        @"Martin", @"Thompson", @"Garcia", @"Martinez", @"Robinson", @"Clark", @"Rodriguez",
        @"Lewis", @"Lee", @"Walker", @"Hall", @"Allen", @"Young", @"King", @"Wright",
        @"Scott", @"Green", @"Baker", @"Adams", @"Nelson", @"Hill", @"Ramirez", @"Campbell",
        @"Mitchell", @"Roberts", @"Carter", @"Phillips", @"Evans", @"Turner", @"Torres"
    ];
    
    // Creative network names popular in the US
    NSArray *creativeNames = @[
        @"HideYoKids", @"HideYoWiFi", @"ItHurtsWhenIP", @"PrettyFlyForAWiFi",
        @"WiFiAintGonnaBreadItself", @"ThePromisedLAN", @"WhyFi", @"WiFiDoYouLoveMe",
        @"LANDownUnder", @"TheLANBeforeTime", @"WuTangLAN", @"ThisLANIsMyLAN", 
        @"BillWiTheScienceFi", @"TellMyWiFiLoveHer", @"NachoWiFi", @"GetOffMyLAN", 
        @"TheInternetBox", @"Series-of-Tubes", @"FBI-Surveillance", @"NSA-Van", 
        @"Area51", @"DEA-Monitoring", @"CIA-Spy-Van", @"NoWiFiForYou", 
        @"Password123", @"NotTheWiFiYoureLookingFor", @"VirusInfectedWiFi",
        @"PayMeToConnect", @"ICanHearYouHavingSex", @"WifiSoFastUCantSeeThis", 
        @"YourNeighborHasABetterRouter", @"WinternetIsComing", @"TwoGirlsOneRouter",
        @"DropItLikeItsHotspot", @"99ProblemsButWiFiAintOne", @"ThePasswordIsPASSWORD",
        @"Mom-Click-Here-For-Internet", @"ShoutingInTernetConspiracyTheories", 
        @"AllYourBandwidthAreBelongToUs", @"NewEnglandClamRouter", @"RouterIHardlyKnowHer"
    ];
    
    // Generate random SSID using one of three methods
    NSString *ssid;
    int networkStyle = arc4random_uniform(100);
    
    if (networkStyle < 45) {
        // ISP style (45% chance)
        NSString *provider = usProviders[arc4random_uniform((uint32_t)usProviders.count)];
        NSString *suffix = usSuffixes[arc4random_uniform((uint32_t)usSuffixes.count)];
        
        if ([suffix length] > 0) {
            ssid = [NSString stringWithFormat:@"%@%@", provider, suffix];
        } else {
            ssid = provider;
        }
        
        // Sometimes add numbers for uniqueness
        if (arc4random_uniform(100) < 40) {
            ssid = [ssid stringByAppendingFormat:@"-%d", arc4random_uniform(999) + 1];
        }
    } 
    else if (networkStyle < 70) {
        // Router brand style (25% chance)
        NSString *brand = routerBrands[arc4random_uniform((uint32_t)routerBrands.count)];
        NSString *suffix = usSuffixes[arc4random_uniform((uint32_t)usSuffixes.count)];
        
        if ([suffix length] > 0) {
            ssid = [NSString stringWithFormat:@"%@%@", brand, suffix];
        } else {
            ssid = brand;
        }
        
        // More likely to add model numbers for router brands
        if (arc4random_uniform(100) < 70) {
            // Different formats for model numbers
            int format = arc4random_uniform(5);
            if (format == 0) {
                ssid = [ssid stringByAppendingFormat:@"_%d", arc4random_uniform(1000)];
            } else if (format == 1) {
                ssid = [ssid stringByAppendingFormat:@"-%c%d", 'A' + arc4random_uniform(26), arc4random_uniform(100)];
            } else if (format == 2) {
                ssid = [ssid stringByAppendingFormat:@"_%dGHZ", (arc4random_uniform(2) == 0) ? 2 : 5];
            } else if (format == 3) {
                ssid = [ssid stringByAppendingFormat:@"-AC%d", 1000 + arc4random_uniform(9000)];
            } else {
                ssid = [ssid stringByAppendingFormat:@"_%X%X%X", arc4random_uniform(16), arc4random_uniform(16), arc4random_uniform(16)];
            }
        }
    }
    else {
        // Personal style (30% chance)
        int personalType = arc4random_uniform(100);
        NSString *base;
        
        if (personalType < 50) {
            // Family/Last name (50% of personal)
            base = commonLastNames[arc4random_uniform((uint32_t)commonLastNames.count)];
            
            // Add common variations
            int variation = arc4random_uniform(7);
            if (variation == 0) {
                base = [base stringByAppendingString:@"-Home"];
            } else if (variation == 1) {
                base = [base stringByAppendingString:@"-WiFi"];
            } else if (variation == 2) {
                base = [base stringByAppendingString:@"-Net"];
            } else if (variation == 3) {
                base = [base stringByAppendingString:@"Family"];
            } else if (variation == 4) {
                base = [base stringByAppendingString:@"House"];
            } else if (variation == 5) {
                base = [NSString stringWithFormat:@"The%@s", base];
            }
            // Otherwise leave as just the name
        } else {
            // Creative name (50% of personal)
            base = creativeNames[arc4random_uniform((uint32_t)creativeNames.count)];
        }
        
        // Sometimes add numbers for uniqueness
        if (arc4random_uniform(100) < 40) {
            ssid = [base stringByAppendingFormat:@"%d", arc4random_uniform(999) + 1];
        } else {
            ssid = base;
        }
    }
    
    // Generate random but valid BSSID (MAC address)
    // Common US router manufacturers OUIs (first 3 bytes)
    NSArray *commonOUIs = @[
        // Cisco/Linksys (popular in US)
        @"00:18:F8", // Cisco-Linksys
        @"00:1D:7E", // Cisco-Linksys
        @"00:23:69", // Cisco-Linksys
        @"E4:95:6E", // Cisco
        @"58:6D:8F", // Cisco-Linksys
        @"C8:BE:19", // Cisco-Linksys
        
        // NETGEAR (very popular in US market)
        @"00:14:6C", // NETGEAR
        @"00:26:F2", // NETGEAR
        @"08:BD:43", // NETGEAR
        @"20:E5:2A", // NETGEAR
        @"28:C6:8E", // NETGEAR
        @"3C:37:86", // NETGEAR
        @"D8:6C:63", // NETGEAR
        
        // Arris/Motorola (common in US cable modems)
        @"00:1A:DE", // Arris
        @"00:26:36", // Arris
        @"E4:64:E9", // Arris
        @"00:01:E3", // Motorola
        @"00:24:37", // Motorola
        
        // Comcast/Xfinity (US-specific)
        @"00:11:AE", // Xfinity
        @"00:14:6C", // Xfinity
        @"E4:64:E9", // Xfinity
        @"F8:F1:B6", // Xfinity
        
        // Charter/Spectrum (US-specific)
        @"68:A4:0E", // Spectrum
        @"00:FC:8D", // Spectrum
        
        // Apple (popular in US homes)
        @"00:1C:B3", // Apple WiFi
        @"88:41:FC", // Apple AirPort
        @"AC:BC:32", // Apple
        
        // Google/Nest (US market)
        @"F4:F5:D8", // Google WiFi
        @"F8:8F:CA", // Google Nest
        
        // Amazon/Eero (US market)
        @"04:F0:21", // Eero
        @"F8:BB:BF", // Eero
        @"FC:65:DE", // Amazon
        
        // TP-Link (common in US budget market)
        @"0C:80:63", // TP-Link
        @"54:A7:03", // TP-Link
        @"F8:1A:67", // TP-Link
        
        // ASUS (popular in US gaming/high-end)
        @"00:0C:6E", // ASUS
        @"30:85:A9", // ASUS
        @"AC:9E:17", // ASUS
        
        // Ubiquiti (popular for prosumers in US)
        @"44:E9:DD", // Ubiquiti
        @"78:8A:20", // Ubiquiti
        @"FC:EC:DA", // Ubiquiti
        
        // Belkin (common US brand)
        @"08:86:3B", // Belkin
        @"14:91:82", // Belkin
        @"94:10:3E", // Belkin
        
        // D-Link (budget US market)
        @"00:26:5A", // D-Link
        @"C0:A0:BB", // D-Link
        
        // Cable modems/gateways used by US ISPs
        @"00:90:D0", // Thomson/RCA (Spectrum)
        @"7C:BF:B1", // ARRIS (Comcast)
        @"00:15:63", // CableMatrix (various US cable)
        @"00:22:10"  // Motorola Solutions (US cable)
    ];
    
    // Select appropriate OUI based on SSID when possible
    NSString *oui = nil;
    
    // Match SSID provider with appropriate manufacturer
    if ([ssid containsString:@"Apple"] || [ssid containsString:@"Airport"]) {
        int appleIdx = 26 + arc4random_uniform(3);
        oui = commonOUIs[appleIdx]; // Apple OUIs
    } 
    else if ([ssid containsString:@"Google"] || [ssid containsString:@"Nest"]) {
        int googleIdx = 29 + arc4random_uniform(2);
        oui = commonOUIs[googleIdx]; // Google OUIs
    }
    else if ([ssid containsString:@"Linksys"] || [ssid containsString:@"Cisco"]) {
        int ciscoIdx = arc4random_uniform(6);
        oui = commonOUIs[ciscoIdx]; // Cisco OUIs (indices 0-5)
    }
    else if ([ssid containsString:@"NETGEAR"] || [ssid containsString:@"Nighthawk"]) {
        int netgearIdx = 6 + arc4random_uniform(7);
        oui = commonOUIs[netgearIdx]; // NETGEAR OUIs (indices 6-12)
    }
    else if ([ssid containsString:@"Motorola"] || [ssid containsString:@"ARRIS"]) {
        int arrisIdx = 13 + arc4random_uniform(5);
        oui = commonOUIs[arrisIdx]; // Arris OUIs (indices 13-17)
    }
    else if ([ssid containsString:@"Xfinity"] || [ssid containsString:@"Comcast"]) {
        int xfinityIdx = 18 + arc4random_uniform(4);
        oui = commonOUIs[xfinityIdx]; // Xfinity OUIs (indices 18-21)
    }
    else if ([ssid containsString:@"Spectrum"] || [ssid containsString:@"Charter"]) {
        int spectrumIdx = 22 + arc4random_uniform(2);
        oui = commonOUIs[spectrumIdx]; // Spectrum OUIs (indices 22-23)
    }
    else if ([ssid containsString:@"Eero"] || [ssid containsString:@"Amazon"]) {
        int eeroIdx = 31 + arc4random_uniform(3);
        oui = commonOUIs[eeroIdx]; // Eero/Amazon OUIs (indices 31-33)
    }
    else if ([ssid containsString:@"TP-Link"] || [ssid containsString:@"TPLink"]) {
        int tplinkIdx = 34 + arc4random_uniform(3);
        oui = commonOUIs[tplinkIdx]; // TP-Link OUIs (indices 34-36)
    }
    else if ([ssid containsString:@"ASUS"]) {
        int asusIdx = 37 + arc4random_uniform(3);
        oui = commonOUIs[asusIdx]; // ASUS OUIs (indices 37-39)
    }
    else if ([ssid containsString:@"Ubiquiti"] || [ssid containsString:@"UBNT"] || [ssid containsString:@"AmpliFi"]) {
        int ubiquitiIdx = 40 + arc4random_uniform(3);
        oui = commonOUIs[ubiquitiIdx]; // Ubiquiti OUIs (indices 40-42)
    }
    else if ([ssid containsString:@"Belkin"]) {
        int belkinIdx = 43 + arc4random_uniform(3);
        oui = commonOUIs[belkinIdx]; // Belkin OUIs (indices 43-45)
    }
    else if ([ssid containsString:@"DLink"] || [ssid containsString:@"D-Link"]) {
        int dlinkIdx = 46 + arc4random_uniform(2);
        oui = commonOUIs[dlinkIdx]; // D-Link OUIs (indices 46-47)
    }
    // ISP-specific cases
    else if ([ssid containsString:@"ATT"] || [ssid containsString:@"AT&T"]) {
        // Use Arris or Cisco (common AT&T suppliers)
        oui = commonOUIs[arc4random_uniform(2) == 0 ? 2 : 14];
    }
    else if ([ssid containsString:@"Verizon"] || [ssid containsString:@"FiOS"]) {
        // Use Actiontec or Motorola (common Verizon suppliers)
        oui = commonOUIs[16 + arc4random_uniform(2)];
    }
    else if ([ssid containsString:@"Cox"]) {
        // Use ARRIS or Cisco (common Cox suppliers)
        oui = commonOUIs[arc4random_uniform(2) == 0 ? 4 : 15];
    }
    else {
        // For all other cases, choose a random OUI
        oui = commonOUIs[arc4random_uniform((uint32_t)commonOUIs.count)];
    }
    
    // Generate the random part of the MAC address
    NSString *bssid = [NSString stringWithFormat:@"%@:%02X:%02X:%02X", 
                       oui,
                       arc4random_uniform(256),
                       arc4random_uniform(256),
                       arc4random_uniform(256)];
    
    // Set network type (usually "Infrastructure" for home networks)
    NSString *networkType = @"Infrastructure";
    
    // Set WiFi standard (802.11ac or 802.11ax most common in US now)
    NSArray *standards = @[@"802.11ax", @"802.11ac", @"802.11n"];
    NSString *wifiStandard = standards[arc4random_uniform(3)]; // Equally likely among the three
    
    // Set auto-join status (usually YES for home networks)
    BOOL autoJoin = YES;
    
    // Set last connection time (typically within the last day)
    NSDate *lastConnectionTime = [NSDate dateWithTimeIntervalSinceNow:-1 * arc4random_uniform(86400)];
    WifiInfo * wifiInfo = [[WifiInfo alloc] init];
    // Store values
    wifiInfo.ssid = ssid;
    wifiInfo.bssid = bssid;
    wifiInfo.networkType = networkType;
    wifiInfo.wifiStandard = wifiStandard;
    wifiInfo.autoJoin = @(autoJoin);
    wifiInfo.lastConnectionTime = lastConnectionTime;
    
    return wifiInfo;
}


- (NSString *)generateDeviceName {
    self.error = nil;
    
    // List of iPhone models from 8 Plus to 15 Pro Max
    NSArray *iPhoneModels = @[
        @"iPhone 8 Plus",
        @"iPhone X",
        @"iPhone XR",
        @"iPhone XS",
        @"iPhone XS Max",
        @"iPhone 11",
        @"iPhone 11 Pro",
        @"iPhone 11 Pro Max",
        @"iPhone 12",
        @"iPhone 12 mini",
        @"iPhone 12 Pro",
        @"iPhone 12 Pro Max",
        @"iPhone 13",
        @"iPhone 13 mini",
        @"iPhone 13 Pro",
        @"iPhone 13 Pro Max",
        @"iPhone 14",
        @"iPhone 14 Plus",
        @"iPhone 14 Pro",
        @"iPhone 14 Pro Max",
        @"iPhone 15",
        @"iPhone 15 Plus",
        @"iPhone 15 Pro",
        @"iPhone 15 Pro Max"
    ];
    
    // Common first names in the USA
    NSArray *usaFirstNames = @[
        @"Michael", @"Christopher", @"Jessica", @"Matthew", @"Ashley", @"Jennifer", 
        @"Joshua", @"Amanda", @"Daniel", @"David", @"James", @"Robert", @"John", 
        @"Joseph", @"Andrew", @"Ryan", @"Brandon", @"Jason", @"Justin", @"Sarah", 
        @"William", @"Jonathan", @"Stephanie", @"Brian", @"Nicole", @"Nicholas", 
        @"Anthony", @"Heather", @"Eric", @"Elizabeth", @"Adam", @"Megan", @"Melissa", 
        @"Kevin", @"Steven", @"Thomas", @"Timothy", @"Christina", @"Kyle", @"Rachel", 
        @"Laura", @"Lauren", @"Amber", @"Brittany", @"Danielle", @"Richard", @"Kimberly", 
        @"Jeffrey", @"Amy", @"Crystal", @"Michelle", @"Tiffany", @"Jeremy", @"Benjamin", 
        @"Mark", @"Emily", @"Aaron", @"Charles", @"Rebecca", @"Jacob", @"Stephen", 
        @"Patrick", @"Sean", @"Erin", @"Zachary", @"Jamie", @"Kelly", @"Samantha", 
        @"Nathan", @"Sara", @"Dustin", @"Paul", @"Angela", @"Tyler", @"Scott", 
        @"Katherine", @"Andrea", @"Gregory", @"Erica", @"Mary", @"Travis", @"Lisa", 
        @"Kenneth", @"Bryan", @"Lindsey", @"Kristen", @"Jose", @"Alexander", @"Jesse", 
        @"Katie", @"Lindsay", @"Shannon", @"Vanessa", @"Courtney", @"Christine", 
        @"Alicia", @"Cody", @"Allison", @"Bradley", @"Samuel", @"Emma", @"Noah", 
        @"Olivia", @"Liam", @"Ava", @"Ethan", @"Sophia", @"Isabella", @"Mason", 
        @"Mia", @"Lucas", @"Charlotte", @"Aiden", @"Harper", @"Elijah", @"Amelia", 
        @"Oliver", @"Abigail", @"Ella", @"Logan", @"Madison", @"Jackson", @"Lily", 
        @"Avery", @"Carter", @"Chloe", @"Grayson", @"Evelyn", @"Leo", @"Sofia", 
        @"Lincoln", @"Hannah", @"Henry", @"Aria", @"Gabriel", @"Grace", @"Owen",
        @"Victoria", @"Zoey", @"Isaac", @"Brooklyn", @"Levi", @"Zoe", @"Julian",
        @"Natalie", @"Caleb", @"Addison", @"Luke", @"Leah", @"Nathan", @"Aubrey", 
        @"Jack", @"Aurora", @"Isaiah", @"Savannah", @"Eli", @"Audrey", @"Dylan"
    ];
    
    // Common last names in the USA
    NSArray *usaLastNames = @[
        @"Smith", @"Johnson", @"Williams", @"Jones", @"Brown", @"Davis", @"Miller", 
        @"Wilson", @"Moore", @"Taylor", @"Anderson", @"Thomas", @"Jackson", @"White", 
        @"Harris", @"Martin", @"Thompson", @"Garcia", @"Martinez", @"Robinson", @"Clark", 
        @"Rodriguez", @"Lewis", @"Lee", @"Walker", @"Hall", @"Allen", @"Young", @"Hernandez", 
        @"King", @"Wright", @"Lopez", @"Hill", @"Scott", @"Green", @"Adams", @"Baker", 
        @"Gonzalez", @"Nelson", @"Carter", @"Mitchell", @"Perez", @"Roberts", @"Turner", 
        @"Phillips", @"Campbell", @"Parker", @"Evans", @"Edwards", @"Collins", @"Stewart", 
        @"Sanchez", @"Morris", @"Rogers", @"Reed", @"Cook", @"Morgan", @"Bell", @"Murphy", 
        @"Bailey", @"Rivera", @"Cooper", @"Richardson", @"Cox", @"Howard", @"Ward", @"Torres", 
        @"Peterson", @"Gray", @"Ramirez", @"James", @"Watson", @"Brooks", @"Kelly", @"Sanders", 
        @"Price", @"Bennett", @"Wood", @"Barnes", @"Ross", @"Henderson", @"Coleman", @"Jenkins", 
        @"Perry", @"Powell", @"Long", @"Patterson", @"Hughes", @"Flores", @"Washington", @"Butler", 
        @"Simmons", @"Foster", @"Gonzales", @"Bryant", @"Alexander", @"Russell", @"Griffin", 
        @"Diaz", @"Hayes"
    ];
    
    // Common US locations/states/cities for naming patterns
    NSArray *usaLocations = @[
        @"NYC", @"LA", @"Chicago", @"Houston", @"Phoenix", @"Philly", @"San Antonio", 
        @"San Diego", @"Dallas", @"Austin", @"Seattle", @"Denver", @"Boston", @"Vegas", 
        @"Miami", @"Oakland", @"Jersey", @"Portland", @"ATL", @"SF", @"NOLA", @"DC", 
        @"Nashville", @"SLC", @"Detroit", @"Columbus", @"Indy", @"Charlotte", @"Memphis", 
        @"AZ", @"CA", @"TX", @"FL", @"NY", @"PA", @"IL", @"OH", @"GA", @"NC", @"MI", 
        @"NJ", @"VA", @"WA", @"MN", @"CO", @"AL", @"SC", @"LA", @"KY", @"OR", @"OK", 
        @"CT", @"UT", @"IA", @"NV", @"AR", @"MS", @"KS", @"NE", @"WV", @"ID", @"HI", 
        @"NH", @"ME", @"MT", @"DE", @"SD", @"ND", @"AK", @"VT", @"WY", @"Home", @"Work", 
        @"Office"
    ];
    
    // Personalized descriptors
    NSArray *personalDescriptors = @[
        @"Personal", @"Pro", @"Work", @"Home", @"Main", @"Family", @"Mobile", @"Primary",
        @"New", @"Travel", @"Gaming", @"Backup", @"Private", @"", @"", @"", @"", @""
    ];
    
    // Generate a random device name
    NSMutableString *deviceName = [NSMutableString string];
    
    // Determine which naming pattern to use
    uint32_t patternSelector;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(patternSelector), (uint8_t *)&patternSelector) != errSecSuccess) {
        NSLog(@"Failed to generate secure random number");
        return nil;
    }
    
    switch (patternSelector % 5) {
        case 0: { 
            // Pattern: "[First Name]'s iPhone"
            uint32_t nameIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nameIndex), (uint8_t *)&nameIndex) != errSecSuccess) {
                // Fall back to a simpler deterministic behavior on error
                nameIndex = (uint32_t)time(NULL);
            }
            NSString *firstName = usaFirstNames[nameIndex % usaFirstNames.count];
            [deviceName appendFormat:@"%@'s iPhone", firstName];
            break;
        }
        case 1: { 
            // Pattern: "iPhone [First Name]" or "iPhone-[First Name]"
            uint32_t nameIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nameIndex), (uint8_t *)&nameIndex) != errSecSuccess) {
                nameIndex = (uint32_t)time(NULL);
            }
            NSString *firstName = usaFirstNames[nameIndex % usaFirstNames.count];
            
            uint32_t dashOrSpace;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(dashOrSpace), (uint8_t *)&dashOrSpace) != errSecSuccess) {
                dashOrSpace = (uint32_t)time(NULL);
            }
            
            if (dashOrSpace % 2 == 0) {
                [deviceName appendFormat:@"iPhone %@", firstName];
            } else {
                [deviceName appendFormat:@"iPhone-%@", firstName];
            }
            break;
        }
        case 2: { 
            // Pattern: "[First Name] [Last Name]'s iPhone"
            uint32_t firstNameIndex, lastNameIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(firstNameIndex), (uint8_t *)&firstNameIndex) != errSecSuccess) {
                firstNameIndex = (uint32_t)time(NULL);
            }
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(lastNameIndex), (uint8_t *)&lastNameIndex) != errSecSuccess) {
                lastNameIndex = (uint32_t)(time(NULL) + 1);
            }
            
            NSString *firstName = usaFirstNames[firstNameIndex % usaFirstNames.count];
            NSString *lastName = usaLastNames[lastNameIndex % usaLastNames.count];
            
            [deviceName appendFormat:@"%@ %@'s iPhone", firstName, lastName];
            break;
        }
        case 3: { 
            // Pattern: "iPhone [Location/State]"
            uint32_t locationIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(locationIndex), (uint8_t *)&locationIndex) != errSecSuccess) {
                locationIndex = (uint32_t)time(NULL);
            }
            NSString *location = usaLocations[locationIndex % usaLocations.count];
            
            [deviceName appendFormat:@"iPhone %@", location];
            break;
        }
        case 4: { 
            // Pattern: "[Specific iPhone Model] [Descriptor]"
            uint32_t modelIndex, descriptorIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(modelIndex), (uint8_t *)&modelIndex) != errSecSuccess) {
                modelIndex = (uint32_t)time(NULL);
            }
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(descriptorIndex), (uint8_t *)&descriptorIndex) != errSecSuccess) {
                descriptorIndex = (uint32_t)(time(NULL) + 1);
            }
            
            NSString *model = iPhoneModels[modelIndex % iPhoneModels.count];
            NSString *descriptor = personalDescriptors[descriptorIndex % personalDescriptors.count];
            
            if ([descriptor length] > 0) {
                [deviceName appendFormat:@"%@ %@", model, descriptor];
            } else {
                // If we got an empty descriptor, just use the model
                [deviceName appendString:model];
            }
            break;
        }
    }
    
    return deviceName;
  
}

- (NSString *)randomizeBatteryLevel {
    // Algorithm for realistic battery level distribution:
    // - 60% chance of battery level between 30-80%
    // - 20% chance of battery level between 80-100%
    // - 15% chance of battery level between 15-30%
    // - 5% chance of battery level between 5-15%
    
    int randomValue = arc4random_uniform(100);
    float level;
    
    if (randomValue < 60) {
        // 30-80% range (most common)
        level = (30 + arc4random_uniform(51)) / 100.0f;
    } else if (randomValue < 80) {
        // 80-100% range (fully charged state)
        level = (80 + arc4random_uniform(21)) / 100.0f;
    } else if (randomValue < 95) {
        // 15-30% range (low battery state)
        level = (15 + arc4random_uniform(16)) / 100.0f;
    } else {
        // 5-15% range (battery danger zone)
        level = (5 + arc4random_uniform(11)) / 100.0f;
    }
    
    // Format with 2 decimal places
    NSString *levelStr = [NSString stringWithFormat:@"%.2f", level];
    
    return levelStr;
}

- (BatteryInfo *)generateBatteryInfo {
    // Generate battery level first
    NSString *batteryLevel = [self randomizeBatteryLevel];

    
    // Create a dictionary with all battery info
    BatteryInfo *batteryInfo = [[BatteryInfo alloc]init];
    batteryInfo.batteryLevel = batteryLevel;
    batteryInfo.batteryPercentage = @((int)([batteryLevel floatValue] * 100));
    
    return batteryInfo;
}
- (NetworkInfo *) generateNetworkInfo{
    SettingManager * manager = [SettingManager sharedManager];
    [manager loadFromPrefs];
    NSString * carrierCountryCode = manager.carrierCountryCode;
    NSString *sql = [NSString stringWithFormat:
        @"SELECT * FROM operator where code = '%@' ORDER BY RANDOM() limit 1"
    ,carrierCountryCode];
    NSLog(@"[DEBUG] query sql: %@",sql);
    NSDictionary * carrier = [[DBManager sharedManager] queryOne:sql];

    NetworkInfo *networkInfo = [[NetworkInfo alloc] init];
    networkInfo.carrierName = carrier[@"name"];
    networkInfo.mcc = carrier[@"mcc"];
    networkInfo.mnc = carrier[@"mnc"];
    networkInfo.localIPAddress = [self generateSpoofedLocalIPAddressFromCurrent];
    networkInfo.localIPv6Address = [self generateSpoofedLocalIPv6AddressFromCurrent];
    // 获取最小值和最大值
    NetworkConnectionType minType = NetworkConnectionTypeAuto;    // 0
    NetworkConnectionType maxType = NetworkConnectionTypeCellular;    // 2

    // 生成随机数（包含 min 和 max）
    NetworkConnectionType randomType = arc4random_uniform(maxType - minType + 1) + minType;
    networkInfo.connectionType = randomType;
    return networkInfo;
}
- (NSString *)getCurrentLocalIPAddress {
    NSString *address = @"192.168.1.1"; // Default fallback
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    
    // Retrieve the current interfaces - returns 0 on success
    if (getifaddrs(&interfaces) == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on iOS
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}

- (NSString *)generateSpoofedLocalIPAddressFromCurrent {
    NSString *currentIP = [self getCurrentLocalIPAddress];
    NSArray<NSString *> *parts = [currentIP componentsSeparatedByString:@"."];
    if (parts.count == 4) {
        // Change the last octet to a random value (2-253), not the original
        int lastOctet = [parts[3] intValue];
        int newLastOctet = lastOctet;
        int attempts = 0;
        while (newLastOctet == lastOctet && attempts < 10) {
            newLastOctet = 2 + arc4random_uniform(252); // 2-253
            attempts++;
        }
        NSString *spoofedIP = [NSString stringWithFormat:@"%@.%@.%@.%d", parts[0], parts[1], parts[2], newLastOctet];
        return spoofedIP;
    }
    // Fallback to random if parsing fails
    return [self getCurrentLocalIPAddress];
}

- (NSString *)generateSpoofedLocalIPv6AddressFromCurrent {
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && temp_addr->ifa_addr->sa_family == AF_INET6) {
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    char ip6[INET6_ADDRSTRLEN];
                    struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)temp_addr->ifa_addr;
                    inet_ntop(AF_INET6, &sin6->sin6_addr, ip6, sizeof(ip6));
                    address = [NSString stringWithUTF8String:ip6];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    if (!address) {
        address = @"fe80::1234:abcd:5678:9abc";
    }
    // Spoof last segment
    NSArray *parts = [address componentsSeparatedByString:@":"];
    if (parts.count >= 2) {
        NSMutableArray *mutableParts = [parts mutableCopy];
        NSString *last = parts.lastObject;
        NSString *spoofedLast = [NSString stringWithFormat:@"%x", arc4random_uniform(0xFFFF)];
        if ([last length] > 0) {
            mutableParts[mutableParts.count-1] = spoofedLast;
        } else if (mutableParts.count > 1) {
            mutableParts[mutableParts.count-2] = spoofedLast;
        }
        return [mutableParts componentsJoinedByString:@":"];
    }
    return address;
}
- (NSString *)generateSerialNumber {

    self.error = nil;
    
    // Add random delay to avoid pattern detection
    usleep(arc4random_uniform(50000));  // 0-50ms delay
    
    // Define valid prefixes for USA-based Apple devices
    NSArray *prefixes = @[@"C02", @"FVF", @"DLXJ", @"GG78", @"HC79"];
    
    // Use pattern variation
    static int patternIndex = 0;
    patternIndex = (patternIndex + 1) % prefixes.count;
    NSString *prefix = prefixes[patternIndex];
    
    // Create a mutable string with the prefix
    NSMutableString *serialNumber = [NSMutableString stringWithString:prefix];
    
    // Generate random alphanumeric characters for the rest
    // Skip I, O, 1, 0 to avoid confusion (common in Apple serial numbers)
    const char *chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    NSInteger remainingLength = (prefix.length == 3) ? 8 : 7;
    
    for (int i = 0; i < remainingLength; i++) {
        uint32_t randomValue;
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomValue), (uint8_t *)&randomValue) == errSecSuccess) {
            [serialNumber appendFormat:@"%c", chars[randomValue % strlen(chars)]];
        } else {
            NSLog(@"Failed to generate secure random number for serial");
            return nil;
        }
    }
    
  
    return serialNumber;
  
}

- (NSString *)generateIMEI {
    // Use a realistic US iPhone TAC (Type Allocation Code)
    NSArray *usTACs = @[ @"353918", @"356938", @"359254", @"353915", @"353920", @"353929", @"353997", @"354994" ];
    NSString *tac = usTACs[arc4random_uniform((uint32_t)usTACs.count)];
    NSMutableString *imei = [NSMutableString stringWithString:tac];
    // 8 digits for SNR
    for (int i = 0; i < 8; i++) {
        [imei appendFormat:@"%d", arc4random_uniform(10)];
    }
    // Luhn check digit
    int sum = 0;
    for (int i = 0; i < 14; i++) {
        int digit = [imei characterAtIndex:i] - '0';
        if (i % 2 == 1) digit *= 2;
        if (digit > 9) digit -= 9;
        sum += digit;
    }
    int checkDigit = (10 - (sum % 10)) % 10;
    [imei appendFormat:@"%d", checkDigit];
    return imei;
}

- (NSString *)generateMEID {
    // Use a realistic US MEID prefix (A00000, A10000, 990000)
    NSArray *usMEIDPrefixes = @[ @"A00000", @"A10000", @"990000" ];
    NSString *prefix = usMEIDPrefixes[arc4random_uniform((uint32_t)usMEIDPrefixes.count)];
    NSMutableString *meid = [NSMutableString stringWithString:prefix];
    // 8 hex digits for the rest
    for (int i = 0; i < 8; i++) {
        [meid appendFormat:@"%X", arc4random_uniform(16)];
    }
    return meid;
}

// 把版本号转成 AAA.BBB.CCC
NSString *NormalizeVersion(NSString *version)
{
    if (version.length == 0) return @"000.000.000";

    // 拆分
    NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
    
    // 不足 3 段补 0（如 11.0 -> 11.0.0）
    NSMutableArray<NSNumber *> *nums = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        if (i < parts.count) {
            [nums addObject:@(parts[i].intValue)];
        } else {
            [nums addObject:@0];
        }
    }

    // 统一格式化：每段 3 位
    return [NSString stringWithFormat:@"%03d.%03d.%03d",
            nums[0].intValue,
            nums[1].intValue,
            nums[2].intValue];
}

-(IosVersion *) generateIOSVersion:(PhoneInfo *)phoneInfo{
    SettingManager * manager = [SettingManager sharedManager];
    [manager loadFromPrefs];
    NSString * minVersion = manager.minVersion;
    NSString * maxVersion = manager.maxVersion;
    
    NSMutableString *queryVersionSql =
        [NSMutableString stringWithString:@"SELECT * FROM KMOS"];

    NSMutableArray *conditions = [NSMutableArray array];
    if (minVersion.length > 0) {
        [conditions addObject:[NSString stringWithFormat:@"sortVersion >= '%@'",NormalizeVersion(minVersion)]];
    }

    if (maxVersion.length > 0) {
        [conditions addObject:[NSString stringWithFormat:@"sortVersion <= '%@'",NormalizeVersion(maxVersion)]];
    }

    if (conditions.count > 0) {
        [queryVersionSql appendFormat:@" WHERE %@", [conditions componentsJoinedByString:@" AND "]];
    }

    [queryVersionSql appendString:@" ORDER BY RANDOM() LIMIT 1"];

    NSLog(@"[DEBUG] query verion %@",queryVersionSql);
    // 先随机一个版本号 再根据版本号找可选的设备 TODO 根据sortVersion筛选
    NSDictionary * versionInfo = [[DBManager sharedManager] queryOne:queryVersionSql];
    if (!versionInfo) {
        IosVersion *fallbackVersion = [[IosVersion alloc] init];
        fallbackVersion.version = [[UIDevice currentDevice] systemVersion] ?: @"";
        fallbackVersion.build = @"unknown";
        fallbackVersion.kernelVersion = ProjectXSysctlString("kern.version");
        fallbackVersion.darwin = ProjectXSysctlString("kern.osrelease");

        DeviceModel *fallbackModel = [[DeviceModel alloc] init];
        fallbackModel.modelName = ProjectXSysctlString("hw.machine");
        fallbackModel.name = [[UIDevice currentDevice] model] ?: @"";
        fallbackModel.cpuArchitecture = @"arm64";
        fallbackModel.gpuFamily = @"Apple GPU";
        fallbackModel.webGLInfo = [[WebGLInfo alloc] init];
        fallbackModel.webGLInfo.unmaskedVendor = @"Apple Inc.";
        fallbackModel.webGLInfo.webglVendor = @"Apple";
        fallbackModel.webGLInfo.webglRenderer = @"Apple GPU";
        fallbackModel.webGLInfo.webglVersion = @"WebGL 2.0";
        fallbackModel.webGLInfo.maxTextureSize = @8192;
        fallbackModel.webGLInfo.maxRenderBufferSize = @8192;

        StorageInfo *fallbackStorage = [[StorageInfo alloc] init];
        fallbackStorage.totalStorage = @"128";
        fallbackStorage.freeStorage = @"32.0";
        fallbackStorage.filesystemType = @"0x1A";

        phoneInfo.iosVersion = fallbackVersion;
        phoneInfo.deviceModel = fallbackModel;
        phoneInfo.storageInfo = fallbackStorage;
        return fallbackVersion;
    }
    // @"kernel_version": @"Darwin Kernel Version ${KMOS.kernelversion}: ${KMOS.kernelversiontime}/RELEASE_ARM64_${cpu.mode}"
    
    IosVersion * iosVersion = [[IosVersion alloc]init];
   
    iosVersion.version = versionInfo[@"version"];
    iosVersion.build = versionInfo[@"OSBuild"];


    NSString *sql = [NSString stringWithFormat:
        @"SELECT * FROM KMDevices d left join CPU c on d.CPU = c.name WHERE defaultOSV <= '%@' AND '%@' <= maxOSV ORDER BY RANDOM() limit 1"
    ,versionInfo[@"sortVersion"],versionInfo[@"sortVersion"]];

    NSDictionary * device = [[DBManager sharedManager] queryOne:sql];

    if (device) {
        iosVersion.kernelVersion = [NSString stringWithFormat:@"Darwin Kernel Version %@: %@/RELEASE_ARM64_%@",versionInfo[@"kernelversion"],versionInfo[@"kernelversiontime"],device[@"mode"]];
    } else {
        iosVersion.kernelVersion = ProjectXSysctlString("kern.version");
    }
    iosVersion.darwin = versionInfo[@"kernelversion"] ?: ProjectXSysctlString("kern.osrelease");
    DeviceModel *deviceModel = [[DeviceModel alloc] init];
    
    
    deviceModel.modelName = device[@"identifier"] ?: ProjectXSysctlString("hw.machine");
    deviceModel.name = device[@"generation"] ?: [[UIDevice currentDevice] model];
    deviceModel.resolution = device[@"sc_pixel_size"] ?: @"";
    deviceModel.viewportResolution = device[@"sc_viewport"] ?: @"";
    deviceModel.devicePixelRatio = device[@"sc_pixel_ratio"] ? @([device[@"sc_pixel_ratio"] doubleValue]) : @1;
    deviceModel.screenDensity = device[@"sc_pixel"] ?: @"";
    deviceModel.cpuArchitecture = device[@"cpuArchitecture"] ?: @"arm64";
    deviceModel.hwModel = device[@"internal_name"] ?: ProjectXSysctlString("hw.model");
    // Additional specs from addSpecsForDevice
    deviceModel.deviceMemory = device[@"RAM"] ?: @0;
    deviceModel.cpuCoreCount = device[@"count"] ?: @0;
    deviceModel.gpuFamily = device[@"CPU"] ? [NSString stringWithFormat:@"Apple %@ GPU",device[@"CPU"]] : @"Apple GPU";
    WebGLInfo *webGL = [[WebGLInfo alloc] init];
    webGL.unmaskedVendor = @"Apple Inc.";
    webGL.unmaskedRenderer = device[@"CPU"] ? [NSString stringWithFormat:@"Apple %@ GPU",device[@"CPU"]] : @"Apple GPU";
    webGL.webglVendor = @"Apple";
    webGL.webglRenderer = @"Apple GPU";
    webGL.webglVersion = @"WebGL 2.0";
    if([deviceModel.modelName hasPrefix:@"iPhone11"] || [deviceModel.modelName hasPrefix:@"iPhone10"] 
        || [deviceModel.modelName hasPrefix:@"iPhone9"] || [deviceModel.modelName hasPrefix:@"iPhone8"]){
        webGL.maxTextureSize = @8192;
        webGL.maxRenderBufferSize = @8192;
    }else{
        webGL.maxTextureSize = @16384;
        webGL.maxRenderBufferSize = @16384;
    }
    deviceModel.webGLInfo = webGL;
    // 假设字符串来自某个字典
    NSString *value = device[@"storage"]; // @"64+256+512"

    // 1. 以 "+" 号分隔字符串
    NSArray *components = value.length > 0 ? [value componentsSeparatedByString:@"+"] : @[];


    // 3. 生成随机索引
    NSString *capacity = @"128";
    if (components.count > 0) {
        NSInteger randomIndex = arc4random_uniform((uint32_t)components.count);
        capacity = components[randomIndex];
    }
    
    // 4. 获取随机值并转换为整数（如果需要数字类型）
    double totalGB = [capacity doubleValue];
    double freePercent;
    
    // Calculate realistic free space based on capacity
    if (totalGB <= 32) {
        // 64GB devices typically have less free space (15-30%)
        freePercent = (arc4random_uniform(15) + 15) / 100.0;
    } else {
        // 128GB devices (25-40%)
        freePercent = (arc4random_uniform(15) + 25) / 100.0;
    }
    
    double freeGB = totalGB * freePercent;
    
    // Add some variability to the decimal points
    double decimalVariation = (arc4random_uniform(10) / 10.0);
    freeGB = freeGB + decimalVariation;
    
    // Round to one decimal place
    freeGB = round(freeGB * 10) / 10;
    StorageInfo * storageInfo = [[StorageInfo alloc]init];
    storageInfo.totalStorage = capacity;
    storageInfo.freeStorage = [NSString stringWithFormat:@"%.1f", freeGB];
    storageInfo.filesystemType = @"0x1A"; // APFS for modern iOS        
    phoneInfo.storageInfo = storageInfo;
    phoneInfo.deviceModel = deviceModel;
    phoneInfo.iosVersion = iosVersion;

    return iosVersion;
}


@end
