// China Fly 1.0.0 — 設置頁（PreferenceLoader）。
// 從 v43.42（SeaDragon Split 1.0.115，頭 653fcaa）改過來的設置頁：
// 歌詞播放器、激活、檢查更新、狀態頁已拿掉；備份／恢復留下；
// 選擇應用加搜索欄＋首次默認開影片裡的 8 個；菜單編輯是新的
// GHCFMenuEditListController（UITableViewController，可拖動排序）；
// 觸發鈕圖默認改成代碼畫的紙飛機。子頁是獨立 plist（Dial／
// SplitSettings／MenuEdit／Trigger／ActionButtonTap／
// ActionButtonLongPress／FloatingIcon），由 PreferenceLoader 的預設
// 控制器載入；「選擇應用」是動態頁（GHCFAppPickerListController，
// 下面），按後台緩存的已安裝 App 清單即時建開關；日誌查看器、
// 菜單編輯、觸發鈕圖也是動態頁（下面）。
//
// 注意（2026-11-12）：这个文件以前用写死字串和 CFSTR，设置一打开
// 就闪退——和 SpringBoard 那边一样，咱们这套工具链编出来的写死
// 字串是坏的。所以这里一个写死的字串都不能用：名字、路径、键名
// 全在运行时现做（CFStringCreateWithCString / stringWithCString），
// 读写开关直接用 CFPreferences（v13 证实过这条路是通的）。
// 備份／恢復是真的做檔案（設定目錄裡的固定檔案），不是擺設；
// 備份改從 live 設定現取值建檔。
// 下面 7 個控制器都是 prefs bundle 裡的自訂類（prefs bundle 不受
// dylib「禁自訂 ObjC 類」那條限；主插件 Tweak.xm 裡還是只能用
// Apple 類＋GHCFLauncher 一個自訂類）。
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>
#import <notify.h>

// 运行时现做一个 NSString（不用写死字串）。
static NSString *GHCFRuntimeString(const char *cstr) {
    return [NSString stringWithCString:cstr encoding:NSUTF8StringEncoding];
}

// 运行时现做一个 CFStringRef（不用 CFSTR），用完要 CFRelease。
static CFStringRef GHCFRuntimeCFString(const char *cstr) {
    return CFStringCreateWithCString(NULL, cstr, kCFStringEncodingUTF8);
}

// 設定檔目錄（設定 App 的 mobile 用戶可寫）。
static NSString *GHCFPrefsDir(void) {
    return GHCFRuntimeString("/var/mobile/Library/Preferences");
}

static NSString *GHCFBackupFilePath(void) {
    return [GHCFPrefsDir() stringByAppendingPathComponent:GHCFRuntimeString("ChinaFly-backup.plist")];
}

static NSString *GHCFAppCacheFilePath(void) {
    return [GHCFPrefsDir() stringByAppendingPathComponent:GHCFRuntimeString("ChinaFly-apps.plist")];
}

// 讀一個 prefs BOOL（沒設就回預設值）。
static BOOL GHCFPrefsBool(const char *key, BOOL defaultValue) {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    CFStringRef keyRef = GHCFRuntimeCFString(key);
    BOOL out = defaultValue;
    if (domain && keyRef) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(keyRef, domain);
        if (v) {
            if (CFGetTypeID(v) == CFBooleanGetTypeID()) out = CFBooleanGetValue((CFBooleanRef)v);
            CFRelease(v);
        }
    }
    if (domain) CFRelease(domain);
    if (keyRef) CFRelease(keyRef);
    return out;
}

// 讀一個 prefs 字串（沒設就回 NULL，調用處要 free）。
static char *GHCFPrefsCString(const char *key) {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    CFStringRef keyRef = GHCFRuntimeCFString(key);
    char *out = NULL;
    if (domain && keyRef) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(keyRef, domain);
        if (v) {
            if (CFGetTypeID(v) == CFStringGetTypeID()) {
                CFIndex len = CFStringGetLength((CFStringRef)v);
                CFIndex maxBytes = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
                out = (char *)malloc(maxBytes);
                if (out && !CFStringGetCString((CFStringRef)v, out, maxBytes, kCFStringEncodingUTF8)) {
                    free(out);
                    out = NULL;
                }
            }
            CFRelease(v);
        }
    }
    if (domain) CFRelease(domain);
    if (keyRef) CFRelease(keyRef);
    return out;
}

// 寫一個 prefs BOOL，立刻落盤。
static void GHCFWritePrefsBool(const char *key, BOOL value) {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    CFStringRef keyRef = GHCFRuntimeCFString(key);
    if (domain && keyRef) {
        CFPreferencesSetAppValue(keyRef, value ? kCFBooleanTrue : kCFBooleanFalse, domain);
        CFPreferencesAppSynchronize(domain);
    }
    if (domain) CFRelease(domain);
    if (keyRef) CFRelease(keyRef);
}

// 寫一個 prefs 字串（NULL = 清掉那個鍵），立刻落盤。
static void GHCFWritePrefsCString(const char *key, const char *value) {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    CFStringRef keyRef = GHCFRuntimeCFString(key);
    if (domain && keyRef) {
        if (value && value[0] != '\0') {
            CFStringRef v = CFStringCreateWithCString(NULL, value, kCFStringEncodingUTF8);
            if (v) {
                CFPreferencesSetAppValue(keyRef, v, domain);
                CFRelease(v);
            }
        } else {
            CFPreferencesSetAppValue(keyRef, NULL, domain);
        }
        CFPreferencesAppSynchronize(domain);
    }
    if (domain) CFRelease(domain);
    if (keyRef) CFRelease(keyRef);
}

// ChinaFly 1.0.0：激活状态文字（读 dylib 写的 activationState 快取；
// authorized 已激活、locked 未激活、checkFailed 名单读不到暂不锁，
// 没值＝还没检查）。
static NSString *GHCFPrefsActivationStatusText(void) {
    char *state = GHCFPrefsCString("activationState");
    NSString *out;
    if (state && strcmp(state, "authorized") == 0) {
        out = GHCFRuntimeString("您的设备已授权");
    } else if (state && strcmp(state, "locked") == 0) {
        out = GHCFRuntimeString("未授权");
    } else if (state && strcmp(state, "checkFailed") == 0) {
        out = GHCFRuntimeString("名单读不到，暂不锁（检查网络／名单）");
    } else {
        out = GHCFRuntimeString("未检查（启动后异步检查）");
    }
    if (state) free(state);
    return out;
}


// 先聲明（下面定義；輪播 helper 要記日誌，先用）。
static void GHCFPrefsLogLine(const char *line);
// v53：觸發鈕自訂圖的固定檔名（跟卡片頭像／背景同一個設定目錄；
// dylib 那邊 GHCFCustomFlyTriggerImagePath 寫死同一條路徑）。
static NSString *GHCFFlyTriggerIconPath(void) {
    return [GHCFPrefsDir() stringByAppendingPathComponent:GHCFRuntimeString("ChinaFly-flyTrigger.jpg")];
}

static NSString *GHCFLogFilePath(void) {
    return GHCFRuntimeString("/var/mobile/Library/Logs/ChinaFly.log");
}


// v42：日誌尾段（預設最後 200 行）、最新在最上面（跟浮窗卡片同一份寫法）。
// v50：讀檔防呆——檔案不存在／讀不到回提示文字；超過 256KB 只取尾段
// （切口可能斷掉一個多字節字，讀不出來就退回整檔讀）；讀到幾行記在
// GHCFLogTailLinesRead，呼叫方寫日誌用。
static int GHCFLogTailLinesRead = 0;
static NSString *GHCFLogTailNewestFirst(void) {
    NSData *data = [NSData dataWithContentsOfFile:GHCFLogFilePath()];
    if (!data || [data length] == 0) {
        GHCFLogTailLinesRead = 0;
        return GHCFRuntimeString("还没有日志（档案不存在或读不到）。");
    }
    if ([data length] > 262144) {
        data = [data subdataWithRange:NSMakeRange([data length] - 262144, 262144)];
    }
    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!content) content = [NSString stringWithContentsOfFile:GHCFLogFilePath() encoding:NSUTF8StringEncoding error:nil];
    if (!content) {
        GHCFLogTailLinesRead = 0;
        return GHCFRuntimeString("还没有日志（档案不存在或读不到）。");
    }
    NSArray *lines = [content componentsSeparatedByString:GHCFRuntimeString("\n")];
    NSMutableArray *last = [NSMutableArray array];
    NSInteger start = (NSInteger)[lines count] - 200;
    if (start < 0) start = 0;
    for (NSInteger i = (NSInteger)[lines count] - 1; i >= start; i--) {
        [last addObject:[lines objectAtIndex:i]];
    }
    GHCFLogTailLinesRead = (int)[last count];
    return [last componentsJoinedByString:GHCFRuntimeString("\n")];
}

// v43：prefs 側寫檔日誌（搜索閃退診斷用，跟 dylib 寫同一份
// 檔案；設定 App 也是 mobile 身份，寫得動；寫不動就靜靜算了，
// 不彈框、不擋路）。
static void GHCFPrefsLogLine(const char *line) {
    if (!line) return;
    NSString *path = GHCFLogFilePath();
    NSString *text = [NSString stringWithCString:line encoding:NSUTF8StringEncoding];
    if (!text) return;
    NSString *entry = [text stringByAppendingString:GHCFRuntimeString("\n")];
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    } else {
        [data writeToFile:path atomically:NO];
    }
}

// v50：安全取表——iOS 16.5 上 PSListController 子類的 self.tableView
// 並不可靠（搜索頁上它拋 unrecognized selector，見 13.log 8610 行；
// 但日誌頁／頭像頁同一寫法又進得去，時好時壞）。以後全檔案一律走
// 這個 helper，絕不直接調 self.tableView。依序試：(1) respondsToSelector
// 再調 tableView；(2) self.view 本身或子視圖裡找 UITableView；
// (3) valueForKey _tableView。哪一路成功記一行日誌；都失敗回 nil，
// 呼叫方自己決定降級（不掛頭、不進編輯模式），不閃退。
static UITableView *GHCFSafeTableViewForController(PSListController *controller, const char *tag) {
    if (!controller) return nil;
    const char *t = tag ? tag : "?";
    @try {
        if ([controller respondsToSelector:@selector(tableView)]) {
            UITableView *(*msgSend)(id, SEL) = (UITableView *(*)(id, SEL))objc_msgSend;
            UITableView *tv = msgSend(controller, @selector(tableView));
            if ([tv isKindOfClass:[UITableView class]]) {
                char buf[192];
                snprintf(buf, sizeof(buf), "v57 prefs-table: %s via tableView", t);
                GHCFPrefsLogLine(buf);
                return tv;
            }
        }
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-table: %s tableView EXCEPTION %s", t, why);
        GHCFPrefsLogLine(buf);
    }
    @try {
        UIView *view = controller.view;
        if ([view isKindOfClass:[UITableView class]]) {
            char buf[192];
            snprintf(buf, sizeof(buf), "v57 prefs-table: %s via self.view", t);
            GHCFPrefsLogLine(buf);
            return (UITableView *)view;
        }
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:[UITableView class]]) {
                char buf[192];
                snprintf(buf, sizeof(buf), "v57 prefs-table: %s via subview", t);
                GHCFPrefsLogLine(buf);
                return (UITableView *)sub;
            }
        }
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-table: %s view scan EXCEPTION %s", t, why);
        GHCFPrefsLogLine(buf);
    }
    @try {
        id iv = [controller valueForKey:GHCFRuntimeString("_tableView")];
        if ([iv isKindOfClass:[UITableView class]]) {
            char buf[192];
            snprintf(buf, sizeof(buf), "v57 prefs-table: %s via _tableView", t);
            GHCFPrefsLogLine(buf);
            return (UITableView *)iv;
        }
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-table: %s _tableView EXCEPTION %s", t, why);
        GHCFPrefsLogLine(buf);
    }
    char buf[192];
    snprintf(buf, sizeof(buf), "v57 prefs-table: %s none", t);
    GHCFPrefsLogLine(buf);
    return nil;
}

// v42：圖片居中裁方形（頭像用，512px）。
static UIImage *GHCFPrefsSquareCropImage(UIImage *image, CGFloat size) {
    if (!image || !image.CGImage) return nil;
    CGFloat w = image.size.width, h = image.size.height;
    CGFloat side = (w < h) ? w : h;
    CGRect crop = CGRectMake((w - side) / 2.0, (h - side) / 2.0, side, side);
    CGImageRef cg = CGImageCreateWithImageInRect(image.CGImage, crop);
    if (!cg) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), YES, 1.0);
    [[UIImage imageWithCGImage:cg] drawInRect:CGRectMake(0, 0, size, size)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGImageRelease(cg);
    return out;
}



// v42：bundleID 轉 App 名字（固定 5 個先查，找不到再查後台緩存檔；
// 還是找不到就回 bundleID 本身，不空白）。
// （固定表在下面定義，這裡先前向聲明，免得隱式聲明報錯。）
static const char *GHCFFixedNames[5];
static int GHCFFixedIndexForBundleID(const char *bid);


// 原來的 5 個固定 App（跟主插件 Tweak.xm 裡的表同一份）。
static const char *GHCFFixedBundleIDs[5] = {
    "com.apple.calculator",
    "com.apple.mobiletimer",
    "com.apple.mobilenotes",
    "com.apple.Preferences",
    "com.apple.mobileslideshow"
};
static const char *GHCFFixedNames[5] = {
    "计算器",
    "时钟",
    "备忘录",
    "设置",
    "照片"
};
static const char *GHCFFixedEnabledKeys[5] = {
    "appCalculatorEnabled",
    "appClockEnabled",
    "appNotesEnabled",
    "appSettingsEnabled",
    "appPhotosEnabled"
};

static int GHCFFixedIndexForBundleID(const char *bid) {
    if (!bid) return -1;
    for (int i = 0; i < 5; i++) {
        if (strcmp(GHCFFixedBundleIDs[i], bid) == 0) return i;
    }
    return -1;
}

// v43.24：第 6 件——自選 App 串列（customAppBundleIDs，逗號分隔 bundleID），
// 開關是 sel-<bundleID>。
static void GHCFSetCustomAppListBid(const char *bid, BOOL on) {
    if (!bid || bid[0] == '\0') return;
    NSMutableArray *ids = [NSMutableArray array];
    char *raw = GHCFPrefsCString("customAppBundleIDs");
    if (raw) {
        NSString *rawStr = [NSString stringWithCString:raw encoding:NSUTF8StringEncoding];
        free(raw);
        if (rawStr && [rawStr length] > 0) {
            NSArray *parts = [rawStr componentsSeparatedByString:GHCFRuntimeString(",")];
            for (NSString *p in parts) if ([p length] > 0 && ![ids containsObject:p]) [ids addObject:p];
        }
    }
    NSString *bidStr = [NSString stringWithCString:bid encoding:NSUTF8StringEncoding];
    [ids removeObject:bidStr];
    if (on) [ids addObject:bidStr];
    NSString *joined = [ids componentsJoinedByString:GHCFRuntimeString(",")];
    GHCFWritePrefsCString("customAppBundleIDs", [joined UTF8String]);
}

// China Fly 1.0.0：首次使用默認開的 8 個 App（照 TrollOpen 影片裡
// 機主的選擇：抖音、汽水音樂 Plus、設置、DynamicCow、Facebook、
// Messenger、QQ、Telegram）。設置是固定 App（下面固定表裡已有，
// 預設開）；其餘 7 個是已裝 App，用 sel-<bid> 開關。
// 判定規則：sel-<bid> 寫過就照寫過的值；沒寫過才回默認（8 個裡
// 的回 YES，其餘回 NO）——用戶親手關掉的不會被默認蓋回來。
static BOOL GHCFIsDefaultOnAppBid(const char *bid) {
    if (!bid) return NO;
    static const char *defaults8[] = {
        "com.ss.iphone.ugc.Aweme",
        "com.soda.music",
        "com.apple.Preferences",
        "com.matteozappa.DynamicCowTS",
        "com.facebook.Facebook",
        "com.facebook.Messenger",
        "com.tencent.mqq",
        "ph.telegra.Telegram"
    };
    size_t n = sizeof(defaults8) / sizeof(defaults8[0]);
    for (size_t i = 0; i < n; i++) {
        if (strcmp(bid, defaults8[i]) == 0) return YES;
    }
    return NO;
}

// 某個 bundleID 是不是在啟動器裡（固定 App 讀開關，預設開；
// 自選 App：sel-<bid> 寫過就照它，沒寫過看是不是默認開的 8 個）。
static BOOL GHCFSetAppInLauncherPrefs(const char *bid, BOOL on);
static BOOL GHCFAppInLauncher(const char *bid) {
    if (!bid || bid[0] == '\0') return NO;
    int fixed = GHCFFixedIndexForBundleID(bid);
    if (fixed >= 0) return GHCFPrefsBool(GHCFFixedEnabledKeys[fixed], YES);
    char selKey[160];
    snprintf(selKey, sizeof(selKey), "sel-%s", bid);
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    CFStringRef keyRef = GHCFRuntimeCFString(selKey);
    BOOL hasValue = NO;
    BOOL stored = NO;
    if (domain && keyRef) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(keyRef, domain);
        if (v) {
            hasValue = YES;
            if (CFGetTypeID(v) == CFBooleanGetTypeID()) stored = CFBooleanGetValue((CFBooleanRef)v);
            CFRelease(v);
        }
    }
    if (domain) CFRelease(domain);
    if (keyRef) CFRelease(keyRef);
    if (hasValue) return stored;
    return GHCFIsDefaultOnAppBid(bid);
}

// 首次打開挑選器時把默認開的 8 個真正寫進 prefs（串列＋開關＋
// 已播種標記），dylib 那邊讀 customAppBundleIDs 才看得到它們；
// 只播一次，之後用戶的開關不再被默認動到。
static void GHCFSeedDefaultAppSelection(void) {
    if (GHCFPrefsBool("appPickerDefaultsSeeded", NO)) return;
    static const char *seedBids[] = {
        "com.ss.iphone.ugc.Aweme",
        "com.soda.music",
        "com.matteozappa.DynamicCowTS",
        "com.facebook.Facebook",
        "com.facebook.Messenger",
        "com.tencent.mqq",
        "ph.telegra.Telegram"
    };
    size_t n = sizeof(seedBids) / sizeof(seedBids[0]);
    for (size_t i = 0; i < n; i++) {
        GHCFSetAppInLauncherPrefs(seedBids[i], YES);
    }
    GHCFWritePrefsBool("appSettingsEnabled", YES);
    GHCFWritePrefsBool("appPickerDefaultsSeeded", YES);
    GHCFPrefsLogLine("cf prefs-apppicker: seeded default 8 apps");
}

// 把某個 App 放進／拿出啟動器（跟主插件的 GHCFSetAppInLauncher 同款
// 邏輯，設定頁這邊重寫一份——設定 bundle 和主插件是兩個進程，
// 調不到主插件的函數）。沒有數量上限，永遠回 YES。
static BOOL GHCFSetAppInLauncherPrefs(const char *bid, BOOL on) {
    if (!bid || bid[0] == '\0') return NO;
    int fixed = GHCFFixedIndexForBundleID(bid);
    if (fixed >= 0) {
        GHCFWritePrefsBool(GHCFFixedEnabledKeys[fixed], on);
        return YES;
    }
    GHCFSetCustomAppListBid(bid, on);
    char selKey[160];
    snprintf(selKey, sizeof(selKey), "sel-%s", bid);
    GHCFWritePrefsBool(selKey, on);
    return YES;
}

// 寫一個 prefs 陣列（menuAppOrder 用），立刻落盤。
static void GHCFWritePrefsArray(const char *key, NSArray *value) {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    CFStringRef keyRef = GHCFRuntimeCFString(key);
    if (domain && keyRef) {
        CFPreferencesSetAppValue(keyRef, (__bridge CFPropertyListRef)value, domain);
        CFPreferencesAppSynchronize(domain);
    }
    if (domain) CFRelease(domain);
    if (keyRef) CFRelease(keyRef);
}

// 讀後台緩存的已安裝 App 清單（主插件列舉、寫檔；設定頁只讀。
// 每項是 dict：bundleID／name）。讀不到回空陣列，不回 nil。
static NSArray *GHCFReadCachedApps(void) {
    NSArray *cached = [NSArray arrayWithContentsOfFile:GHCFAppCacheFilePath()];
    if (!cached) return [NSArray array];
    return cached;
}

// 菜單項解析：entry 是 bundleID 就找對應 App 名；是顯示名就按名
// 找 bundleID；都找不到就原樣當顯示名（bid 回 nil，運行時按名找）。
static void GHCFResolveMenuEntry(NSString *entry, NSString **outBid, NSString **outName) {
    NSString *bid = nil;
    NSString *name = nil;
    if (entry && [entry length] > 0) {
        int fixed = GHCFFixedIndexForBundleID([entry UTF8String]);
        if (fixed >= 0) {
            bid = entry;
            name = GHCFRuntimeString(GHCFFixedNames[fixed]);
        } else {
            NSArray *cached = GHCFReadCachedApps();
            for (id item in cached) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                NSString *cbid = [item objectForKey:GHCFRuntimeString("bundleID")];
                NSString *cname = [item objectForKey:GHCFRuntimeString("name")];
                if (cbid && [cbid isEqualToString:entry]) {
                    bid = cbid;
                    name = cname;
                    break;
                }
                if (cname && [cname isEqualToString:entry]) {
                    bid = cbid;
                    name = cname;
                    break;
                }
            }
        }
    }
    if (!name || [name length] == 0) name = entry ? entry : GHCFRuntimeString("");
    if (outBid) *outBid = bid;
    if (outName) *outName = name;
}

// 菜單默認順序（照 TrollOpen 影片露出的前 17 個，原樣保留；
// 微信在影片裡出現多次，這裡照列出的順序留三個。知道 bundleID
// 的存 bundleID，不知道的存顯示名，運行時按名找）。
static NSArray *GHCFDefaultMenuOrder(void) {
    return [NSArray arrayWithObjects:
        GHCFRuntimeString("com.apple.Preferences"),
        GHCFRuntimeString("com.tencent.xin"),
        GHCFRuntimeString("com.apple.calculator"),
        GHCFRuntimeString("AppsDump3"),
        GHCFRuntimeString("com.ss.iphone.ugc.Aweme"),
        GHCFRuntimeString("巨魔注入器"),
        GHCFRuntimeString("愛思全能版"),
        GHCFRuntimeString("com.tencent.mqq"),
        GHCFRuntimeString("com.tencent.xin"),
        GHCFRuntimeString("酷我音樂"),
        GHCFRuntimeString("虛擬定位"),
        GHCFRuntimeString("com.matteozappa.DynamicCowTS"),
        GHCFRuntimeString("com.facebook.Messenger"),
        GHCFRuntimeString("ph.telegra.Telegram"),
        GHCFRuntimeString("TrollStore"),
        GHCFRuntimeString("com.facebook.Facebook"),
        GHCFRuntimeString("com.tencent.xin"),
        nil];
}

// 讀 menuAppOrder（沒存過就寫一份默認順序再回它；
// 存過但不是字串陣列就當沒存過，照默認來）。
static NSMutableArray *GHCFReadMenuOrder(void) {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    CFStringRef keyRef = GHCFRuntimeCFString("menuAppOrder");
    NSArray *stored = nil;
    if (domain && keyRef) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(keyRef, domain);
        if (v) {
            if (CFGetTypeID(v) == CFArrayGetTypeID()) stored = (__bridge_transfer NSArray *)v;
            else CFRelease(v);
        }
    }
    if (domain) CFRelease(domain);
    if (keyRef) CFRelease(keyRef);
    NSMutableArray *order = [NSMutableArray array];
    if (stored) {
        for (id item in stored) {
            if ([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0) [order addObject:item];
        }
    }
    if ([order count] == 0) {
        order = [NSMutableArray arrayWithArray:GHCFDefaultMenuOrder()];
        GHCFWritePrefsArray("menuAppOrder", order);
        GHCFPrefsLogLine("cf prefs-menuedit: seeded default menu order");
    }
    return order;
}

static void GHCFWriteMenuOrder(NSArray *order) {
    if (!order) order = [NSArray array];
    GHCFWritePrefsArray("menuAppOrder", order);
}

// 代碼畫的紙飛機（觸發鈕默認圖；不要引用已刪的哆啦A夢 png）。
// 機頭朝右上，兩片折面一深一淺。
static UIImage *GHCFPaperPlaneImage(CGFloat size) {
    if (size <= 0) size = 120.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat s = size;
    UIBezierPath *top = [UIBezierPath bezierPath];
    [top moveToPoint:CGPointMake(0.08 * s, 0.50 * s)];
    [top addLineToPoint:CGPointMake(0.90 * s, 0.10 * s)];
    [top addLineToPoint:CGPointMake(0.44 * s, 0.64 * s)];
    [top closePath];
    [[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0] setFill];
    [top fill];
    UIBezierPath *bottom = [UIBezierPath bezierPath];
    [bottom moveToPoint:CGPointMake(0.44 * s, 0.64 * s)];
    [bottom addLineToPoint:CGPointMake(0.90 * s, 0.10 * s)];
    [bottom addLineToPoint:CGPointMake(0.60 * s, 0.90 * s)];
    [bottom closePath];
    [[UIColor colorWithRed:0.20 green:0.62 blue:1.0 alpha:1.0] setFill];
    [bottom fill];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

// v47：見下面 GHCFHandlePlistDetailTap 的定義——定義要用到白名單
// GHCFPrefsIsKnownPlistName 與 PlistPage 的接口聲明，都在文件後面，
// 這裡先給原型（主頁控制器與 PlistPage 共用同一個 didSelectRow）。
static BOOL GHCFHandlePlistDetailTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath);

// v72：見下面 GHCFHandleLinkListTap 的定義——LinkList 點按攔截，
// 推我們自己的 GHCFLinkListController（定義在文件後面，這裡先給原型）。
static BOOL GHCFHandleLinkListTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath);

// China Fly 1.0.0：見下面 GHCFHandleMenuEditTap 的定義——detail 是
// GHCFMenuEditListController 的連結行攔下來自己推（它是
// UITableViewController 子類，框架預設的推頁路徑推不動）。
static BOOL GHCFHandleMenuEditTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath);

// v43：手動派發 PSButtonCell 點按——不再賭框架會不會從 action 字串派發。
// 診斷：plist 的 action 字串、程式現拼的 action 字串、方法、target 全部合規，
// 但皇上在 v42 真機測到五個操作行點了完全沒反應；框架內部到底讀
// specifier->action 還是 properties 裡的 action 字串，靜態查不到，
// 所以直接在 didSelectRow 裡讀 action 字串、轉 SEL、在 target（沒有就 self）上跑。
// v54：N 定死——v52 加的 `SEL specAction = spec->action;` 整行刪掉：
// arm64e 上編譯器給這行直接 ivar 讀取生成帶 PAC 認證的載入，plist 載入
// 的按鈕那個值認證不過就 trap（.ips：GHCFDispatchButtonTap+552 `brk`，
// 呼叫方是狀態頁；19.log:11626 遊戲布局點按後無動作行，死在同一行）。
// action 只走 properties（v43/v44 就是這樣派發，遊戲布局走通過）。
// 注意：@try/@catch 只防 ObjC 例外，PAC trap 是硬體 trap、防不住——
// 真正的修法就是刪掉這行讀取，@try/@catch 只是第二道防線。
// 回傳 YES 表示這一行已經處理了（呼叫方直接 return，不要再走 super，免得重複跑）。
static BOOL GHCFDispatchButtonTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    if (!controller || !indexPath) return NO;
    @try {
    PSSpecifier *spec = [controller specifierAtIndexPath:indexPath];
    if (!spec) {
        GHCFPrefsLogLine("v57 prefs-config tap: no specifier for tap");
        return NO;
    }
    // v52：入口先記一行（section／row／cellType），點了沒反應時日誌看得見
    // 派發走到哪一步——之前這裡靜默回 NO，狀態頁的點按在日誌裡全無痕跡。
    {
        char tapBuf[160];
        snprintf(tapBuf, sizeof(tapBuf), "v57 prefs-config tap: section %ld row %ld cellType %d", (long)indexPath.section, (long)indexPath.row, (int)spec.cellType);
        GHCFPrefsLogLine(tapBuf);
    }
    if (spec.cellType != PSButtonCell) return NO;
    // v54：action 只走 properties，絕不再碰 spec->action ivar（見上面）。
    NSString *actionName = [spec propertyForKey:GHCFRuntimeString("action")];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!actionName || [actionName length] == 0) {
        GHCFPrefsLogLine("v57 prefs-config tap: button without action");
        return YES;
    }
    const char *actionC = [actionName UTF8String];
    SEL action = NSSelectorFromString(actionName);
    id target = spec.target;
    if (!target) target = controller;
    char buf[320];
    snprintf(buf, sizeof(buf), "v57 prefs-config tap: action %s target %s", actionC ? actionC : "?", [NSStringFromClass([target class]) UTF8String]);
    GHCFPrefsLogLine(buf);
    // v44：action 字串是裸名（沒有冒號），但方法都帶一個參數（PSSpecifier *），
    // 真正的 selector 有冒號（例如 ghcfBackupConfig:）。裸名先試，不回應就補冒號再試。
    // 這也是為什麼框架自己的派發在 v42 也不動——框架也是拿同一個裸名字串轉 SEL，
    // respondsToSelector 永遠回 NO，點按就這樣被靜靜吞掉了。
    if (![target respondsToSelector:action]) {
        GHCFPrefsLogLine("v57 prefs-config tap: bare name does not respond, trying colon");
        NSString *colonName = [actionName stringByAppendingString:GHCFRuntimeString(":")];
        SEL colonAction = NSSelectorFromString(colonName);
        if ([target respondsToSelector:colonAction]) {
            action = colonAction;
            GHCFPrefsLogLine("v57 prefs-config tap: colon selector responds");
        }
    }
    if (![target respondsToSelector:action]) {
        GHCFPrefsLogLine("v57 prefs-config tap: target does not respond to bare or colon, falling through to super");
        return NO;
    }
    // v44：變數 SEL 不能用 performSelector（-Werror 下 -Warc-performSelector-leaks），
    // 用 v41 就在用的 objc_msgSend 寫法。
    ((void (*)(id, SEL, id))objc_msgSend)(target, action, spec);
    snprintf(buf, sizeof(buf), "v57 prefs-config tap: dispatched %s", [NSStringFromSelector(action) UTF8String]);
    GHCFPrefsLogLine(buf);
    return YES;
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[512];
        snprintf(buf, sizeof(buf), "v57 prefs-config tap EXCEPTION %s", why);
        GHCFPrefsLogLine(buf);
        @try {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("点按失败") message:GHCFRuntimeString("这个按钮点下去出错了（已记进日志），先回上一页再试。") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:GHCFRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
            [controller presentViewController:alert animated:YES completion:nil];
        } @catch (NSException *e2) {
            (void)e2;
        }
        return YES;
    }
}

@interface ChinaFlyRootListController : PSListController <UIDocumentPickerDelegate>
@end

@implementation ChinaFlyRootListController

// v43：記進了哪一頁（PlistPage 繼承這裡，類名是 GHCFPlistPageController，
// 具體哪份 plist 由 specifiers 裡的 plistpage entry 行給出）。
// China Fly 1.0.0：歌詞播放器已拿掉，主頁不再嵌 WKWebView。
- (void)viewDidLoad {
    [super viewDidLoad];
    char buf[160];
    snprintf(buf, sizeof(buf), "v57 prefs-page: %s", [NSStringFromClass([self class]) UTF8String]);
    GHCFPrefsLogLine(buf);
}


// v43：按鈕行自己派發（見上面 GHCFDispatchButtonTap）；其他行走框架。
// v47：plist 名 detail 的連結行先攔下來自己推 PlistPage（見下面
// GHCFHandlePlistDetailTap），不再走框架預設——框架推的原生頁是空的。
// China Fly 1.0.0：菜單編輯行也先攔下來自己推（見 GHCFHandleMenuEditTap）。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (GHCFHandleMenuEditTap(self, tableView, indexPath)) return;
    if (GHCFHandleLinkListTap(self, tableView, indexPath)) return;
    if (GHCFHandlePlistDetailTap(self, tableView, indexPath)) return;
    if (GHCFDispatchButtonTap(self, tableView, indexPath)) return;
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        @try {
            NSMutableArray *loaded = [self loadSpecifiersFromPlistName:GHCFRuntimeString("Root") target:self];
            // v52：新手模式整個取消，不再過濾。
            _specifiers = loaded;
        } @catch (NSException *e) {
            const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
            char buf[512];
            snprintf(buf, sizeof(buf), "v57 prefs-root specifiers EXCEPTION %s", reason);
            GHCFPrefsLogLine(buf);
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:GHCFRuntimeString("主页组装出错（已记进日志），先回设定再试。") forKey:GHCFRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
        if (!_specifiers) _specifiers = [NSMutableArray array];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    NSString *keyName = GHCFRuntimeString("key");
    NSString *key = specifier.properties[keyName];
    CFPropertyListRef v = NULL;
    if (key) {
        CFStringRef cfKey = (__bridge CFStringRef)key;
        v = CFPreferencesCopyAppValue(cfKey, domain);
    }
    if (domain) CFRelease(domain);
    if (v) {
        id value = (__bridge_transfer id)v;
        return value;
    }
    // v41：沒存過就回 plist 裡寫的 default（以前回 NO，滑桿的預設值
    // 在設定頁會顯示成 0）。
    NSString *defaultName = GHCFRuntimeString("default");
    id def = specifier.properties[defaultName];
    if (def) return def;
    return [NSNumber numberWithBool:NO];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    NSString *keyName = GHCFRuntimeString("key");
    NSString *key = specifier.properties[keyName];
    if (key) {
        CFStringRef cfKey = (__bridge CFStringRef)key;
        CFPreferencesSetAppValue(cfKey, (__bridge CFPropertyListRef)value, domain);
        CFPreferencesAppSynchronize(domain);
        // v43：記開關／滑桿／分段改了什麼值（只記用戶改動，不記讀取；
        // readPreferenceValue 每行渲染都跑，記了會刷爆日誌）。
        // ChinaFly 1.0.0：激活码绝不写日志——key 是 activationCode 时跳过这行。
        if (![key isEqualToString:GHCFRuntimeString("activationCode")]) {
            char buf[256];
            const char *keyC = [key UTF8String];
            const char *valC = [[value description] UTF8String];
            snprintf(buf, sizeof(buf), "v57 prefs-set: %s = %s", keyC ? keyC : "?", valC ? valC : "?");
            GHCFPrefsLogLine(buf);
        }
    }
    if (domain) CFRelease(domain);
}

// 彈一個提示框（設定頁裡的回饋）。
- (void)ghcfShowAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    NSString *okTitle = GHCFRuntimeString("好");
    UIAlertAction *ok = [UIAlertAction actionWithTitle:okTitle style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:ok];
    // v43：提示框改走最上層 presenter、主隊列；彈不出來要寫日誌，不要靜默
    // （presentViewController 失敗是靜默的，看著就像點了沒反應）。
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = self;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        if (!presenter.view.window) {
            // v43：self 不在視窗裡時，改找前景 scene 的 key window
            //（不用已棄用的 UIApplication.keyWindow / windows）。
            UIWindow *keyWindow = nil;
            for (UIScene *s in [[UIApplication sharedApplication] connectedScenes]) {
                if (![s isKindOfClass:[UIWindowScene class]]) continue;
                UIWindowScene *ws = (UIWindowScene *)s;
                if (ws.activationState != UISceneActivationStateForegroundActive) continue;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
                if (keyWindow) break;
            }
            if (keyWindow && keyWindow.rootViewController) {
                presenter = keyWindow.rootViewController;
                while (presenter.presentedViewController) presenter = presenter.presentedViewController;
            }
        }
        if (presenter) {
            [presenter presentViewController:alert animated:YES completion:nil];
            GHCFPrefsLogLine("v57 prefs-config alert shown");
        } else {
            GHCFPrefsLogLine("v57 prefs-config alert FAILED: no presenter");
        }
    });
}

// v43.8：从 live 的 CFPreferences 现取值建档（备份／导出共用）——
// 设定档 /var/mobile/Library/Preferences/com.guhailong.fly.plist
// 在设定进程里看不到（写入都走 CFPreferencesSetAppValue，档是 cfprefsd
// 管的），旧写法复制档案永远报「没有配置文件可备份」。改成同步后用
// CFPreferencesCopyKeyList 拿全部 key、逐 key 取值组 dict 再写档；
// dict 是空的（0 个 key）才回 NO 且 count=0（没东西可备／可导）。
static BOOL GHCFWriteLivePrefsToFile(NSString *dst, NSUInteger *outCount, unsigned long long *outBytes) {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    if (!domain || !dst) return NO;
    CFPreferencesAppSynchronize(domain);
    CFArrayRef keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (keys) {
        CFIndex n = CFArrayGetCount(keys);
        for (CFIndex i = 0; i < n; i++) {
            CFStringRef key = (CFStringRef)CFArrayGetValueAtIndex(keys, i);
            if (!key) continue;
            CFPropertyListRef value = CFPreferencesCopyAppValue(key, domain);
            if (value) {
                [dict setObject:(__bridge id)value forKey:(__bridge NSString *)key];
                CFRelease(value);
            }
        }
        CFRelease(keys);
    }
    CFRelease(domain);
    if ([dict count] == 0) return NO;
    [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
    BOOL ok = [dict writeToFile:dst atomically:YES];
    if (ok) {
        if (outCount) *outCount = [dict count];
        if (outBytes) {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:dst error:nil];
            *outBytes = attrs ? [attrs fileSize] : 0;
        }
    }
    return ok;
}

// v43.10：備份／導出成功後直接把檔案遞給皇上——分享表帶檔案 URL，
// 當場存到文件／傳出去／隔空投送，不用自己去文件找。分享表關掉後
// 再彈提示寫清完整路徑（兩個 modal 不能疊著彈，分享表先開）。
- (void)ghcfShareConfigFile:(NSString *)path title:(NSString *)title what:(NSString *)what restoreRow:(NSString *)restoreRow {
    NSURL *url = [NSURL fileURLWithPath:path];
    if (!url) {
        [self ghcfShowAlertWithTitle:title message:GHCFRuntimeString("文件路径不对，分享打不开。")];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:[NSArray arrayWithObject:url] applicationActivities:nil];
    __weak typeof(self) weakSelf = self;
    share.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
        (void)activityType; (void)completed; (void)returnedItems; (void)activityError;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        char msgBuf[768];
        snprintf(msgBuf, sizeof(msgBuf), "%s在 %s。刚才的分享表可以直接把文件存到文件、发出去或隔空投送，不用自己去文件找。想换配置时，点「%s」挑这个文件就能用。", [what UTF8String], [path UTF8String], [restoreRow UTF8String]);
        [strongSelf ghcfShowAlertWithTitle:title message:GHCFRuntimeString(msgBuf)];
    };
    @try {
        [self presentViewController:share animated:YES completion:nil];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v43.10 prefs-config share EXCEPTION %s", reason);
        GHCFPrefsLogLine(buf);
        char msgBuf[768];
        snprintf(msgBuf, sizeof(msgBuf), "分享表打不开，文件在 %s，自己去文件找。", [path UTF8String]);
        [self ghcfShowAlertWithTitle:title message:GHCFRuntimeString(msgBuf)];
    }
}

// 備份配置：live 設定現取值寫一份到備份檔（v43.8）。
- (void)ghcfBackupConfig:(PSSpecifier *)specifier {
    (void)specifier;
    GHCFPrefsLogLine("v57 prefs-config backup entry");
    NSString *dst = GHCFBackupFilePath();
    NSUInteger count = 0;
    unsigned long long bytes = 0;
    BOOL ok = GHCFWriteLivePrefsToFile(dst, &count, &bytes);
    if (count == 0) {
        GHCFPrefsLogLine("v57 prefs-config backup: no keys in live prefs");
        [self ghcfShowAlertWithTitle:GHCFRuntimeString("没有配置文件可备份") message:GHCFRuntimeString("先改一个设置，配置文件才会生成。")];
        return;
    }
    if (ok) {
        char buf[512];
        snprintf(buf, sizeof(buf), "v57 prefs-config backup: wrote %lu keys, %llu bytes to %s", (unsigned long)count, bytes, [dst UTF8String]);
        GHCFPrefsLogLine(buf);
        // v43.10：成功後直接把檔案遞給皇上（分享表），不用自己去文件找。
        [self ghcfShareConfigFile:dst title:GHCFRuntimeString("已备份配置") what:GHCFRuntimeString("备份") restoreRow:GHCFRuntimeString("从备份恢复")];
    } else {
        GHCFPrefsLogLine("v57 prefs-config backup: write failed");
        [self ghcfShowAlertWithTitle:GHCFRuntimeString("备份失败") message:GHCFRuntimeString("复制配置文件时出错。")];
    }
}
// China Fly 1.0.0：導出／導入已拿掉（新 Root.plist 不再有這兩行）；
// 只留備份／恢復，備份檔是 ChinaFly-backup.plist。
// v43.10：恢復——把字典逐鍵寫進 live prefs（走 CFPreferences，
// cfprefsd 快取才更新；直接換檔看著像沒反應，v43 教訓）。
- (void)ghcfApplyConfigDict:(NSDictionary *)dict sourceDescription:(NSString *)src title:(NSString *)title {
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    if (domain) {
        for (NSString *key in dict) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)[dict objectForKey:key], domain);
        }
        CFPreferencesAppSynchronize(domain);
        CFRelease(domain);
    }
    [self reloadSpecifiers];
    char buf[512];
    snprintf(buf, sizeof(buf), "v43.10 prefs-config apply: applied %lu keys from %s", (unsigned long)[dict count], [src UTF8String]);
    GHCFPrefsLogLine(buf);
    [self ghcfShowAlertWithTitle:title message:GHCFRuntimeString("配置已恢复，请重新启动 SpringBoard 生效。")];
}

// v43.10：文件挑選器——恢復讓皇上自己挑配置文件（想換成別的
// 配置也能用，不只限於原來那一個固定備份檔）。用 initForOpeningContentTypes:
// asCopy:YES（等於舊 Import 模式：系統把挑中的檔拷一份進容器再給我們讀，
// 不用管 security-scoped resource；舊 initWithDocumentTypes:inMode: 在
// iOS 14 起已棄用，-Werror 會直接報錯）。彈不出來就走固定路徑
//（見下面 ghcfRestoreConfigFromFixedPath）。
- (void)ghcfPresentRestoreDocPicker {
    @try {
        UTType *plistType = [UTType typeWithIdentifier:GHCFRuntimeString("com.apple.property-list")];
        NSArray *types = [NSArray arrayWithObjects:plistType, nil];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v43.10 prefs-config docpicker EXCEPTION %s, fixed-path fallback", reason);
        GHCFPrefsLogLine(buf);
        [self ghcfRestoreConfigFromFixedPath];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = ([urls count] > 0) ? [urls objectAtIndex:0] : nil;
    if (!url) {
        GHCFPrefsLogLine("v43.10 prefs-config docpicker: no url");
        return;
    }
    NSString *path = [url path];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!dict) {
        char buf[512];
        snprintf(buf, sizeof(buf), "v43.10 prefs-config docpicker: unreadable %s", [path UTF8String]);
        GHCFPrefsLogLine(buf);
        [self ghcfShowAlertWithTitle:GHCFRuntimeString("恢复失败") message:GHCFRuntimeString("挑的配置文件读不出来（要 .plist 配置文件）。")];
        return;
    }
    [self ghcfApplyConfigDict:dict sourceDescription:path title:GHCFRuntimeString("已从备份恢复配置")];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    GHCFPrefsLogLine("v43.10 prefs-config docpicker: cancelled");
}

// 從備份文件恢復配置：先彈文件挑選器，讓皇上自己挑配置文件。
// v43：改走 CFPreferences 逐鍵寫入（見上）。
- (void)ghcfRestoreConfig:(PSSpecifier *)specifier {
    (void)specifier;
    GHCFPrefsLogLine("v57 prefs-config restore entry");
    [self ghcfPresentRestoreDocPicker];
}

// v43.10：挑選器彈不出來時的 fallback——讀固定備份檔 ChinaFly-backup.plist。
- (void)ghcfRestoreConfigFromFixedPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *src = GHCFBackupFilePath();
    if (![fm fileExistsAtPath:src]) {
        GHCFPrefsLogLine("v57 prefs-config restore: no backup file");
        [self ghcfShowAlertWithTitle:GHCFRuntimeString("没有找到备份文件") message:GHCFRuntimeString("先点「备份配置」，再恢复。")];
        return;
    }
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:src];
    if (!dict) {
        char buf[512];
        snprintf(buf, sizeof(buf), "v57 prefs-config restore: backup file unreadable %s", [src UTF8String]);
        GHCFPrefsLogLine(buf);
        [self ghcfShowAlertWithTitle:GHCFRuntimeString("恢复失败") message:GHCFRuntimeString("备份文件读不出来。")];
        return;
    }
    [self ghcfApplyConfigDict:dict sourceDescription:src title:GHCFRuntimeString("已从备份恢复配置")];
}

@end
// 開的那份清單的設定頁版，同一份 key、同一份清單，兩邊同步。
// 清單讀後台緩存檔（主插件啟動 5 秒後在後台列舉、寫檔；設定頁
// 只讀緩存，不列舉、不堵主線程）。固定 5 個永遠在最前面；
// 自選 App 的開關 key 是 sel-<bundleID>，串列走 customAppBundleIDs（無上限）。
// v55：選 App 頁每行掛 App 圖標（UIImage 取 App 圖標的私有方法，走運行時拿；
// 拿不到就回 nil、行只顯示名字，不擋列表、不閃退）。圖標按 bundleID 快取，
// 開頁只取一次（清單上百個也不卡）。
@interface UIImage (GHCFAppIconLookup)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end
static NSMutableDictionary *GHCFAppIconCache = nil;
static UIImage *GHCFAppIconForBundleID(NSString *bid) {
    if (!bid || [bid length] == 0) return nil;
    if (!GHCFAppIconCache) GHCFAppIconCache = [NSMutableDictionary dictionary];
    UIImage *cached = GHCFAppIconCache[bid];
    if (cached) return cached;
    UIImage *icon = nil;
    @try {
        icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:0 scale:[UIScreen mainScreen].scale];
        if (!icon) icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
    } @catch (NSException *e) {
        icon = nil;
    }
    if (icon) {
        if ([GHCFAppIconCache count] > 300) [GHCFAppIconCache removeAllObjects];
        GHCFAppIconCache[bid] = icon;
    }
    return icon;
}


@interface GHCFAppPickerListController : PSListController <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *ghcfSearchBar;
@property (nonatomic, strong) NSString *ghcfSearchText;
@property (nonatomic, assign) BOOL ghcfSearchBarInstalled;
@end

@implementation GHCFAppPickerListController


// v43：記進了哪一頁。
- (void)viewDidLoad {
    @try {
        [super viewDidLoad];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-apppicker viewDidLoad EXCEPTION %s", reason);
        GHCFPrefsLogLine(buf);
    }
    GHCFPrefsLogLine("v57 prefs-page: AppPicker");
}

// China Fly 1.0.0：搜索欄掛在表頭（viewDidAppear 才碰 table，
// 只掛一次；搜尋字變了就清快取重組，表頭的搜索欄留著不動）。
- (void)viewDidAppear:(BOOL)animated {
    @try {
        [super viewDidAppear:animated];
    } @catch (NSException *e) {
        GHCFPrefsLogLine("v57 prefs-apppicker: super viewDidAppear EXCEPTION");
    }
    if (self.ghcfSearchBarInstalled) return;
    UITableView *tv = GHCFSafeTableViewForController(self, "apppicker-search");
    if (!tv) {
        GHCFPrefsLogLine("v57 prefs-apppicker: no table, search bar not mounted");
        return;
    }
    @try {
        UISearchBar *bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, tv.bounds.size.width, 44)];
        bar.delegate = self;
        bar.placeholder = GHCFRuntimeString("搜尋 App");
        bar.showsCancelButton = YES;
        bar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        bar.autocorrectionType = UITextAutocorrectionTypeNo;
        self.ghcfSearchBar = bar;
        tv.tableHeaderView = bar;
        self.ghcfSearchBarInstalled = YES;
        GHCFPrefsLogLine("v57 prefs-apppicker: search bar mounted");
    } @catch (NSException *e) {
        GHCFPrefsLogLine("v57 prefs-apppicker: search bar mount EXCEPTION");
    }
}

// 搜索字變了：清快取重組（specifiers 裡按字過濾）；
// 重組後把焦點還給搜索欄，鍵盤不掉。
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchBar;
    BOOL wasFirstResponder = [self.ghcfSearchBar isFirstResponder];
    self.ghcfSearchText = searchText;
    _specifiers = nil;
    [self reloadSpecifiers];
    if (wasFirstResponder) [self.ghcfSearchBar becomeFirstResponder];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = GHCFRuntimeString("");
    self.ghcfSearchText = nil;
    _specifiers = nil;
    [self reloadSpecifiers];
    [searchBar resignFirstResponder];
}

// v50：按鈕行自己派發（GHCFDispatchButtonTap；框架自己的派發對裸方法名
// 不補冒號，點了沒反應——見 v42.1/v42.2；「重新掃描」按鈕靠這個才動）。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (GHCFDispatchButtonTap(self, tableView, indexPath)) return;
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        @try {
            // China Fly 1.0.0：首次開這頁先把默認開的 8 個播進 prefs。
            GHCFSeedDefaultAppSelection();
            NSMutableArray *specs = [NSMutableArray array];
            // 說明組。
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            NSString *footerKey = GHCFRuntimeString("footerText");
            [group setProperty:GHCFRuntimeString("开的 App 出现在启动器里（数量不限）。清单在后台列举、缓存起来；刚装的 App 可能要等一会儿才出现，缺 App 时点下面「重新扫描」。") forKey:footerKey];
            [specs addObject:group];
            // v50：重新掃描（清單是後台列舉的緩存，舊了會缺 App；點一下請
            // dylib 2 秒內重建緩存，下次開這頁就看到新的）。
            PSSpecifier *rescan = [PSSpecifier preferenceSpecifierNamed:GHCFRuntimeString("重新扫描") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            [rescan setProperty:GHCFRuntimeString("ghcfRescanApps") forKey:GHCFRuntimeString("action")];
            [specs addObject:rescan];
            // 固定 5 個。
            for (int i = 0; i < 5; i++) {
                NSString *name = GHCFRuntimeString(GHCFFixedNames[i]);
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
                [spec setProperty:GHCFRuntimeString(GHCFFixedEnabledKeys[i]) forKey:GHCFRuntimeString("key")];
                [spec setProperty:GHCFRuntimeString("com.guhailong.fly") forKey:GHCFRuntimeString("defaults")];
                [spec setProperty:[NSNumber numberWithBool:YES] forKey:GHCFRuntimeString("default")];
                UIImage *fixedIcon = GHCFAppIconForBundleID(GHCFRuntimeString(GHCFFixedBundleIDs[i]));
                if (fixedIcon) [spec setProperty:fixedIcon forKey:GHCFRuntimeString("iconImage")];
                [specs addObject:spec];
            }
            // 緩存的已安裝 App（跳過固定 5 個，按名字排過了）。
            NSArray *cached = [NSArray arrayWithContentsOfFile:GHCFAppCacheFilePath()];
            BOOL anyCached = NO;
            if (cached) {
                for (id item in cached) {
                    if (![item isKindOfClass:[NSDictionary class]]) continue;
                    NSString *bidStr = item[GHCFRuntimeString("bundleID")];
                    NSString *nameStr = item[GHCFRuntimeString("name")];
                    if (!bidStr || [bidStr length] == 0) continue;
                    const char *bid = [bidStr UTF8String];
                    if (GHCFFixedIndexForBundleID(bid) >= 0) continue;
                    anyCached = YES;
                    NSString *label = (nameStr && [nameStr length] > 0) ? nameStr : bidStr;
                    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
                    NSString *selKey = [GHCFRuntimeString("sel-") stringByAppendingString:bidStr];
                    [spec setProperty:selKey forKey:GHCFRuntimeString("key")];
                    [spec setProperty:GHCFRuntimeString("com.guhailong.fly") forKey:GHCFRuntimeString("defaults")];
                    [spec setProperty:[NSNumber numberWithBool:NO] forKey:GHCFRuntimeString("default")];
                    UIImage *cachedIcon = GHCFAppIconForBundleID(bidStr);
                    if (cachedIcon) [spec setProperty:cachedIcon forKey:GHCFRuntimeString("iconImage")];
                    [specs addObject:spec];
                }
            }
            if (!anyCached) {
                PSSpecifier *emptyGroup = [PSSpecifier emptyGroupSpecifier];
                [emptyGroup setProperty:GHCFRuntimeString("还没有已安装 App 清单（后台列举中，稍后再开这个页）。") forKey:GHCFRuntimeString("footerText")];
                [specs addObject:emptyGroup];
            }
            // China Fly 1.0.0：搜索過濾——有搜尋字時只留說明組、
            // 「重新掃描」和名字裡有搜尋字的 App 開關行。
            if (self.ghcfSearchText && [self.ghcfSearchText length] > 0) {
                NSMutableArray *filtered = [NSMutableArray array];
                for (PSSpecifier *sp in specs) {
                    if (sp.cellType != PSSwitchCell) {
                        [filtered addObject:sp];
                        continue;
                    }
                    NSString *label = sp.name;
                    if (label && [label rangeOfString:self.ghcfSearchText options:NSCaseInsensitiveSearch].location != NSNotFound) {
                        [filtered addObject:sp];
                    }
                }
                _specifiers = filtered;
            } else {
                _specifiers = specs;
            }
    
        } @catch (NSException *e) {
            const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
            char buf[512];
            snprintf(buf, sizeof(buf), "v57 prefs-apppicker specifiers EXCEPTION %s", reason);
            GHCFPrefsLogLine(buf);
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:GHCFRuntimeString("选择器页组装出错（已记进日志），先回上一页再试。") forKey:GHCFRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
        if (!_specifiers) _specifiers = [NSMutableArray array];
    }
    return _specifiers;
}

- (void)ghcfRescanApps:(PSSpecifier *)specifier {
    (void)specifier;
    GHCFWritePrefsBool("rescanAppsRequested", YES);
    GHCFPrefsLogLine("v57 prefs-apppicker rescan requested");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("正在重新扫描") message:GHCFRuntimeString("已请后台重新列举已安装 App，稍后再开这一页就看到新的清单。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:GHCFRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[GHCFRuntimeString("key")];
    if (!key) return [NSNumber numberWithBool:NO];
    NSString *selPrefix = GHCFRuntimeString("sel-");
    if ([key hasPrefix:selPrefix]) {
        NSString *bidStr = [key substringFromIndex:[selPrefix length]];
        return [NSNumber numberWithBool:GHCFAppInLauncher([bidStr UTF8String])];
    }
    // 固定 App：讀 prefs，沒設回 plist 的 default（開）。
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    CFPropertyListRef v = NULL;
    if (domain) {
        CFStringRef cfKey = (__bridge CFStringRef)key;
        v = CFPreferencesCopyAppValue(cfKey, domain);
        CFRelease(domain);
    }
    if (v) {
        id value = (__bridge_transfer id)v;
        return value;
    }
    NSString *defaultName = GHCFRuntimeString("default");
    id def = specifier.properties[defaultName];
    if (def) return def;
    return [NSNumber numberWithBool:NO];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[GHCFRuntimeString("key")];
    if (!key) return;
    BOOL on = [value boolValue];
    NSString *selPrefix = GHCFRuntimeString("sel-");
    if ([key hasPrefix:selPrefix]) {
        NSString *bidStr = [key substringFromIndex:[selPrefix length]];
        GHCFSetAppInLauncherPrefs([bidStr UTF8String], on);
        // v43.24：第 6 件——自選 App 無上限，不再彈「已滿」提示。
        char buf[320];
        snprintf(buf, sizeof(buf), "v57 prefs-set: sel %s = %d", [bidStr UTF8String], on ? 1 : 0);
        GHCFPrefsLogLine(buf);
        [self reloadSpecifiers];
        return;
    }
    // 固定 App：直接寫開關。
    CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
    if (domain) {
        CFStringRef cfKey = (__bridge CFStringRef)key;
        CFPreferencesSetAppValue(cfKey, (__bridge CFPropertyListRef)value, domain);
        CFPreferencesAppSynchronize(domain);
        CFRelease(domain);
    }
    // v43：記固定 App 開關改了什麼值。
    char buf[256];
    const char *keyC = [key UTF8String];
    const char *valC = [[value description] UTF8String];
    snprintf(buf, sizeof(buf), "v57 prefs-set: %s = %s", keyC ? keyC : "?", valC ? valC : "?");
    GHCFPrefsLogLine(buf);
}

@end


// ── China Fly 1.0.0 動態頁 ──
// 下面 6 個控制器都是 prefs bundle 裡的自訂類（prefs bundle 不受
// dylib「禁自訂 ObjC 類」那條限；主插件 Tweak.xm 裡還是只能用
// Apple 類＋GHCFLauncher 一個自訂類）。

// China Fly 1.0.0：菜單編輯頁——「當前列表」可拖動排序。
// UITableViewController 子類（不用 PSListController：這頁是純列表＋
// 拖動重排，編輯模式的 reorder control 就夠了）。讀／寫 prefs 鍵
// menuAppOrder（有序字串陣列：知道 bundleID 的存 bundleID，
// 不知道的存顯示名，運行時按名找——見 GHCFResolveMenuEntry）。
// 右上角「編輯」按鈕進編輯模式，拖動右邊的手柄重排，鬆手即存。
@interface GHCFMenuEditListController : UITableViewController
@property (nonatomic, strong) NSMutableArray *ghcfMenuItems;
@end

@implementation GHCFMenuEditListController

- (void)viewDidLoad {
    [super viewDidLoad];
    GHCFPrefsLogLine("cf prefs-page: MenuEdit");
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.ghcfMenuItems = GHCFReadMenuOrder();
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 44)];
    footer.text = GHCFRuntimeString("按右上角「編輯」，拖動右邊的手柄排序，鬆手就存好了。");
    footer.font = [UIFont systemFontOfSize:13];
    footer.textColor = [UIColor grayColor];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.numberOfLines = 0;
    self.tableView.tableFooterView = footer;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)[self.ghcfMenuItems count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *reuseId = GHCFRuntimeString("GHCFMenuEditCell");
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseId];
    }
    NSString *entry = nil;
    if (indexPath.row >= 0 && indexPath.row < (NSInteger)[self.ghcfMenuItems count]) entry = [self.ghcfMenuItems objectAtIndex:(NSUInteger)indexPath.row];
    NSString *bid = nil;
    NSString *name = nil;
    GHCFResolveMenuEntry(entry, &bid, &name);
    cell.textLabel.text = name;
    cell.imageView.image = nil;
    if (bid) {
        UIImage *icon = GHCFAppIconForBundleID(bid);
        if (icon) cell.imageView.image = icon;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
    (void)tableView;
    NSInteger from = fromIndexPath.row;
    NSInteger to = toIndexPath.row;
    if (from == to) return;
    if (from < 0 || from >= (NSInteger)[self.ghcfMenuItems count]) return;
    if (to < 0 || to >= (NSInteger)[self.ghcfMenuItems count]) return;
    NSString *moved = [self.ghcfMenuItems objectAtIndex:(NSUInteger)from];
    [self.ghcfMenuItems removeObjectAtIndex:(NSUInteger)from];
    [self.ghcfMenuItems insertObject:moved atIndex:(NSUInteger)to];
    GHCFWriteMenuOrder(self.ghcfMenuItems);
    char buf[256];
    snprintf(buf, sizeof(buf), "cf prefs-menuedit: moved row %ld to %ld", (long)from, (long)to);
    GHCFPrefsLogLine(buf);
}

@end

// v42：「查看日誌」——設定 App 裡直接看分屏日誌：最新在最上面
//（讀尾段，預設最後 200 行）、能刷新、能清空（檔案截斷；寫不動就
// 誠實報失敗，不假裝能清）、能分享（系統分享表單）。
@interface GHCFLogViewerListController : PSListController
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, assign) BOOL headerInstalled;
@end

@implementation GHCFLogViewerListController

// v43：按鈕行自己派發（GHCFDispatchButtonTap）；其他行走框架。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (GHCFDispatchButtonTap(self, tableView, indexPath)) return;
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

// v50：重做——viewDidLoad 只建 UITextView（讀檔防呆在
// GHCFLogTailNewestFirst 裡），不再碰 table；掛載移到 viewDidAppear
//（只掛一次，安全取表＋try/catch），掛不上就只記日誌、頁面照常可用
//（三個按鈕＋分享都還在）。
- (void)viewDidLoad {
    @try {
        [super viewDidLoad];
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-log: super viewDidLoad EXCEPTION %s", why);
        GHCFPrefsLogLine(buf);
    }
    GHCFPrefsLogLine("v57 prefs-page: LogViewer");
    @try {
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 420)];
        tv.font = [UIFont systemFontOfSize:11];
        tv.editable = NO;
        tv.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        tv.text = GHCFLogTailNewestFirst();
        self.logView = tv;
        char buf[128];
        snprintf(buf, sizeof(buf), "v57 prefs-log: read %d lines", GHCFLogTailLinesRead);
        GHCFPrefsLogLine(buf);
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-log: build text view EXCEPTION %s", why);
        GHCFPrefsLogLine(buf);
        self.logView = nil;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    @try {
        [super viewDidAppear:animated];
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-log: super viewDidAppear EXCEPTION %s", why);
        GHCFPrefsLogLine(buf);
    }
    if (self.logView && !self.headerInstalled) {
        UITableView *tv = GHCFSafeTableViewForController(self, "log");
        if (tv) {
            @try {
                tv.tableHeaderView = self.logView;
                self.headerInstalled = YES;
                GHCFPrefsLogLine("v57 prefs-log: header mounted");
            } @catch (NSException *e) {
                const char *why = [e reason] ? [[e reason] UTF8String] : "?";
                char buf[256];
                snprintf(buf, sizeof(buf), "v57 prefs-log: mount EXCEPTION %s", why);
                GHCFPrefsLogLine(buf);
            }
        } else {
            GHCFPrefsLogLine("v57 prefs-log: no table, header not mounted");
        }
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        @try {
            NSMutableArray *specs = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:GHCFRuntimeString("最新的在最上面（预设最后 200 行）；清空是把档案截断，新的日志会继续写进来。") forKey:GHCFRuntimeString("footerText")];
            [specs addObject:group];
            NSArray *buttons = [NSArray arrayWithObjects:GHCFRuntimeString("刷新"), GHCFRuntimeString("清空"), GHCFRuntimeString("分享"), nil];
            NSArray *actions = [NSArray arrayWithObjects:GHCFRuntimeString("ghcfLogRefresh"), GHCFRuntimeString("ghcfLogClear"), GHCFRuntimeString("ghcfLogShare"), nil];
            for (NSUInteger i = 0; i < [buttons count]; i++) {
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:[buttons objectAtIndex:i] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
                [spec setProperty:[actions objectAtIndex:i] forKey:GHCFRuntimeString("action")];
                [specs addObject:spec];
            }
            _specifiers = specs;
        } @catch (NSException *e) {
            const char *why = [e reason] ? [[e reason] UTF8String] : "?";
            char buf[256];
            snprintf(buf, sizeof(buf), "v57 prefs-log: specifiers EXCEPTION %s", why);
            GHCFPrefsLogLine(buf);
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:GHCFRuntimeString("日志页组装出错（已记进日志），先回上一页再试。") forKey:GHCFRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
    }
    return _specifiers;
}

- (void)ghcfLogRefresh:(PSSpecifier *)specifier {
    (void)specifier;
    @try {
        if (self.logView) self.logView.text = GHCFLogTailNewestFirst();
    } @catch (NSException *e) {
        GHCFPrefsLogLine("v57 prefs-log: refresh EXCEPTION");
    }
}

- (void)ghcfLogClear:(PSSpecifier *)specifier {
    (void)specifier;
    NSError *err = nil;
    BOOL ok = [[NSData data] writeToFile:GHCFLogFilePath() options:NSDataWritingAtomic error:&err];
    if (ok) {
        if (self.logView) self.logView.text = GHCFLogTailNewestFirst();
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("日志已清空") message:GHCFRuntimeString("日志档案已截断，新的日志会继续写进来。") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:GHCFRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("清空失败") message:GHCFRuntimeString("日志档案写不动（权限问题），请用 Filza 手动清。") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:GHCFRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)ghcfLogShare:(PSSpecifier *)specifier {
    (void)specifier;
    NSURL *url = [NSURL fileURLWithPath:GHCFLogFilePath()];
    if (!url) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:[NSArray arrayWithObject:url] applicationActivities:nil];
    [self presentViewController:share animated:YES completion:nil];
}

@end



// v53：悬浮图标——相冊選圖（PHPicker）、居中裁方形 512、
// 存設定目錄固定檔名、寫 flyTriggerIconCustom 鍵；恢復默認刪檔＋清鍵，
// 觸發鈕 2 秒內回默認圖（dylib tick 重讀）。照卡片頭像控制器樣式。
@interface GHCFFlyTriggerIconListController : PSListController <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIImageView *previewView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, assign) BOOL headerInstalled;
@end

@implementation GHCFFlyTriggerIconListController

// v43：按鈕行自己派發（GHCFDispatchButtonTap）；其他行走框架。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (GHCFDispatchButtonTap(self, tableView, indexPath)) return;
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

// v50：掛載移到 viewDidAppear（安全取表＋try/catch）；viewDidLoad 只建
// 預覽區，不再碰 table。
- (void)viewDidLoad {
    @try {
        [super viewDidLoad];
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-flyTriggericon: super viewDidLoad EXCEPTION %s", why);
        GHCFPrefsLogLine(buf);
    }
    GHCFPrefsLogLine("v57 prefs-page: FlyTriggerIcon");
    @try {
        CGFloat w = [UIScreen mainScreen].bounds.size.width;
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 160)];
        container.backgroundColor = [UIColor whiteColor];
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake((w - 120) / 2.0, 20, 120, 120)];
        iv.layer.cornerRadius = 60.0;
        iv.layer.masksToBounds = YES;
        iv.layer.borderWidth = 2.0;
        iv.layer.borderColor = [UIColor colorWithRed:0.83 green:0.68 blue:0.21 alpha:1.0].CGColor;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        [container addSubview:iv];
        self.previewView = iv;
        self.headerView = container;
        [self ghcfRefreshFlyTriggerPreview];
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-flyTriggericon: viewDidLoad EXCEPTION %s", why);
        GHCFPrefsLogLine(buf);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    @try {
        [super viewDidAppear:animated];
    } @catch (NSException *e) {
        GHCFPrefsLogLine("v57 prefs-flyTriggericon: super viewDidAppear EXCEPTION");
    }
    if (self.headerView && !self.headerInstalled) {
        UITableView *tv = GHCFSafeTableViewForController(self, "flyTriggericon");
        if (tv) {
            @try {
                tv.tableHeaderView = self.headerView;
                self.headerInstalled = YES;
                GHCFPrefsLogLine("v57 prefs-flyTriggericon: header mounted");
            } @catch (NSException *e) {
                const char *why = [e reason] ? [[e reason] UTF8String] : "?";
                char buf[256];
                snprintf(buf, sizeof(buf), "v57 prefs-flyTriggericon: mount EXCEPTION %s", why);
                GHCFPrefsLogLine(buf);
            }
        } else {
            GHCFPrefsLogLine("v57 prefs-flyTriggericon: no table, header not mounted");
        }
    }
}

- (void)ghcfRefreshFlyTriggerPreview {
    @try {
        UIImage *img = [UIImage imageWithContentsOfFile:GHCFFlyTriggerIconPath()];
        if (!img) {
            // China Fly 1.0.0：沒有自訂圖就顯示代碼畫的紙飛機
            //（不要引用已刪的哆啦A夢 png）。
            img = GHCFPaperPlaneImage(120.0);
        }
        self.previewView.image = img;
    } @catch (NSException *e) {
        GHCFPrefsLogLine("v57 prefs-flyTriggericon: refresh EXCEPTION");
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        [group setProperty:GHCFRuntimeString("上面那张圆图是现在的触发钮图，默认是纸飞机；从相册选一张、居中裁成方形存起来，触发钮 2 秒内就换成它。") forKey:GHCFRuntimeString("footerText")];
        [specs addObject:group];
        PSSpecifier *pick = [PSSpecifier preferenceSpecifierNamed:GHCFRuntimeString("从相册选图（换钮图片）") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [pick setProperty:GHCFRuntimeString("ghcfPickFlyTriggerIcon") forKey:GHCFRuntimeString("action")];
        [specs addObject:pick];
        PSSpecifier *restore = [PSSpecifier preferenceSpecifierNamed:GHCFRuntimeString("恢复默认触发钮图") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [restore setProperty:GHCFRuntimeString("ghcfRestoreFlyTriggerIcon") forKey:GHCFRuntimeString("action")];
        [specs addObject:restore];
        _specifiers = specs;
    }
    return _specifiers;
}

- (void)ghcfPickFlyTriggerIcon:(PSSpecifier *)specifier {
    (void)specifier;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter imagesFilter];
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)ghcfRestoreFlyTriggerIcon:(PSSpecifier *)specifier {
    (void)specifier;
    [[NSFileManager defaultManager] removeItemAtPath:GHCFFlyTriggerIconPath() error:nil];
    GHCFWritePrefsBool("flyTriggerIconCustom", NO);
    [self ghcfRefreshFlyTriggerPreview];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("已恢复默认触发钮图") message:GHCFRuntimeString("触发钮回到默认图。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:GHCFRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!results || [results count] == 0) return;
    NSItemProvider *provider = [results objectAtIndex:0].itemProvider;
    if (!provider) return;
    [provider loadObjectOfClass:[UIImage class] completionHandler:^(id object, NSError *error) {
        (void)error;
        if (![object isKindOfClass:[UIImage class]]) return;
        UIImage *picked = (UIImage *)object;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImage *square = GHCFPrefsSquareCropImage(picked, 512.0);
            if (!square) return;
            NSData *data = UIImageJPEGRepresentation(square, 0.85);
            BOOL ok = data && [data writeToFile:GHCFFlyTriggerIconPath() atomically:YES];
            if (ok) {
                GHCFWritePrefsBool("flyTriggerIconCustom", YES);
                [self ghcfRefreshFlyTriggerPreview];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("钮图片已换好") message:GHCFRuntimeString("触发钮 2 秒内就换成这张。") preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:GHCFRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("保存钮图片失败") message:GHCFRuntimeString("图片写不进设定目录。") preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:GHCFRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

@end


// （GHCFPlistPageController 在文件後面定義，這裡先給完整接口聲明——
// 光是 @class 前向聲明不夠，[GHCFPlistPageController class] 會報錯。）
@interface GHCFPlistPageController : ChinaFlyRootListController
@end

// v72：LinkList 子清單控制器（見下面 GHCFHandleLinkListTap）——
// 框架原生的 PSListItemsController 在鍵盤頁上只顯示一個選項（子清單幾乎空白，
// plist 本身是對的、父頁也載了 7 項，框架子清單的生成／快取／渲染在這裡
// 黑盒修不了；同 v47 的做法：點按攔下來、推我們自己的控制器）。
// 它從點按那行的 specifier 現場讀 values／titles 建單選行，不走框架快取；
// 選項寫值走繼承的 setPreferenceValue（CFPreferences＋同步），並記
// v72 prefs-linklist 日誌，下次日誌能證明寫入。
@interface GHCFLinkListController : ChinaFlyRootListController
@end

// China Fly 1.0.0：子頁要跳的 plist 白名單（9 份真實檔案；不在裡面的
// 名字一律不載，免得 loadSpecifiersFromPlistName 拿到壞名字）。
// 舊頁（ARC、ARCButtons、Floating、Window、Shadow、Scheduler、Banner、
// GestureCustom、Keyboard、Info、Status、Other）已刪，不在白名單裡，
// 點了也不會載。Activation 是 1.0.0 新加的激活頁（照舊分屏 1.0.103
// 那套，碼表跟舊分屏用同一份線上的 codes.json）。
static BOOL GHCFPrefsIsKnownPlistName(const char *name) {
    if (!name || name[0] == '\0') return NO;
    static const char *known[] = {"ActionButtonLongPress", "ActionButtonTap", "Activation", "Dial", "FloatingIcon", "MenuEdit", "Root", "SplitSettings", "Trigger"};
    size_t n = sizeof(known) / sizeof(known[0]);
    for (size_t i = 0; i < n; i++) {
        if (strcmp(name, known[i]) == 0) return YES;
    }
    return NO;
}


// China Fly 1.0.0：攔截 detail=GHCFMenuEditListController 的連結行，
// 自己推菜單編輯頁。GHCFMenuEditListController 是 UITableViewController
// 子類（不是 PSListController），框架預設的推頁路徑是照 PSListController
// 做的，直接交給框架會推不動；這裡用 navigationController 直推。
// 回傳 YES 表示這一行已經處理了（呼叫方直接 return，不要再走 super）。
static BOOL GHCFHandleMenuEditTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    if (!controller || !indexPath) return NO;
    PSSpecifier *spec = [controller specifierAtIndexPath:indexPath];
    if (!spec) return NO;
    if (spec.cellType != PSLinkCell) return NO;
    NSString *detail = spec.properties[GHCFRuntimeString("detail")];
    if (!detail || ![detail isEqualToString:GHCFRuntimeString("GHCFMenuEditListController")]) return NO;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    GHCFMenuEditListController *page = [[GHCFMenuEditListController alloc] initWithStyle:UITableViewStyleGrouped];
    NSString *label = spec.name;
    page.title = (label && [label length] > 0) ? label : GHCFRuntimeString("當前列表");
    UINavigationController *nav = controller.navigationController;
    if (nav) {
        [nav pushViewController:page animated:YES];
        GHCFPrefsLogLine("cf prefs-menuedit push");
    } else {
        GHCFPrefsLogLine("cf prefs-menuedit push FAILED: no navigationController");
    }
    return YES;
}

// v72：攔截 PSLinkListCell 的點按，自己推 GHCFLinkListController。
// 根因（皇上 2026-11-17 14:11 報：鍵盤子清單只顯示內弹出，頁面幾乎空白）：
// plist 本身是對的（Keyboard[4] validTitles 浮窗内弹出／外弹出、
// validValues inner／outer，出貨包裡也在），父頁也載了 7 項（24.log 證明，
// 舊快取假說已推翻）——剩下就是框架原生的 PSListItemsController 自己
// 生成／快取／渲染子清單時出的問題，在這裡黑盒修不了；同 v47 修
// detail 連結行的做法（框架原生控制器載不到我們 bundle 的東西就空白），
// 點按先攔下來、推我們自己的控制器：子清單從點按那行的 specifier
// 現場讀 values／titles 建行，不走框架快取，兩個選項一定都在；
// 選項寫值走繼承的 setPreferenceValue，並記 v72 prefs-linklist 日誌。
// 沒有 values（或空）就回 NO 交回框架，不推空白頁。
// 回傳 YES 表示這一行已經處理了（呼叫方直接 return，不要再走 super）。
static BOOL GHCFHandleLinkListTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    if (!controller || !indexPath) return NO;
    PSSpecifier *spec = [controller specifierAtIndexPath:indexPath];
    if (!spec) return NO;
    if (spec.cellType != PSLinkListCell) return NO;
    NSArray *values = spec.properties[GHCFRuntimeString("values")];
    NSArray *titles = spec.properties[GHCFRuntimeString("titles")];
    // v43.11：plist 載入的 LinkList 行用 validValues／validTitles，沒有 values 屬性
    //（鍵盤彈出方式那些行就是這麼漏網的——30.log 6 次 no values）。
    //讀不到才改讀 validValues／validTitles，讀到就推我們自己的頁。
    if (!values || [values count] == 0) {
        values = spec.properties[GHCFRuntimeString("validValues")];
        titles = spec.properties[GHCFRuntimeString("validTitles")];
    }
    if (!values || [values count] == 0) {
        GHCFPrefsLogLine("v72 prefs-linklist no values, framework fallback");
        return NO;
    }
    (void)titles;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    GHCFLinkListController *page = [[GHCFLinkListController alloc] init];
    page.specifier = spec;
    page.parentController = controller;
    page.rootController = controller.rootController;
    [controller pushController:page];
    NSString *key = spec.properties[GHCFRuntimeString("key")];
    const char *keyC = key ? [key UTF8String] : "?";
    char buf[256];
    snprintf(buf, sizeof(buf), "v72 prefs-linklist push %s options %lu", keyC, (unsigned long)[values count]);
    GHCFPrefsLogLine(buf);
    return YES;
}

// v47：攔截 plist 名 detail 的連結行，自己手動推 PlistPage。
// 根因（皇上 2026-11-14 19:29 報：系統設定裡點「ARC设置」進去什麼都
// 沒有，主頁本身正常）：Root.plist 裡四個子頁連結行
// （arc 設置 detail=ARC、浮窗設置
// detail=Floating、其他雜項功能 detail=Other、高級設置 detail=Advanced）
// 的 detail 是 plist 名、沒有 action，點按走到框架預設的處理——它 new
// 一個原生的 PSListController 來載那份 plist，但那個原生控制器的 bundle
// 不是我們這個 PreferenceLoader bundle（我們 bundle 裡的 plist 它找不
// 到），specifiers 載出來是空的：頁面推得出來，裡面一行都沒有。類名
// detail 的行不受影響（框架直接 alloc 那個類，類在我們二進制裡，
// specifiers 由類自己載），所以類名 detail 的行都正常，
// 主頁（我們自己的控制器自己載 Root.plist）也正常。PreferenceLoader
// 登記檔裡根控制器就是用類名登記的（isController），也是同一道理。
// 修法：連結行點按時先在這裡攔下來——detail 是白名單裡的 plist 名，就
// 手動推一個 GHCFPlistPageController：把 plist 名寫進 specifier 的非保留字鍵
// ghcfTargetPlist，再 push。PlistPage 的 specifiers 是在我們自己的
// 子類身上載 plist（bundle 對得上），內容就出來了。detail 是類名、
// 或不在白名單裡的，一律回 NO 交回框架／super，不動它。
// PlistPage 繼承主頁控制器（同一個 didSelectRow），所以子頁裡的嵌套
// plist 連結（浮窗設置裡的陰影／橫幅／鍵盤／調度、其他雜項裡的
// 桌面圖標／懸浮圖標、ARC／高級設置裡的調度／手勢自定義）走同
// 一個攔截，一次全修；類名 detail 的嵌套行（排序頁、加入 App、
// 日誌／頭像／背景）繼續走框架，本來就正常。
// 回傳 YES 表示這一行已經處理了（呼叫方直接 return，不要再走 super）。
static BOOL GHCFHandlePlistDetailTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    if (!controller || !indexPath) return NO;
    PSSpecifier *spec = [controller specifierAtIndexPath:indexPath];
    if (!spec) return NO;
    if (spec.cellType != PSLinkCell) return NO;
    NSString *detail = spec.properties[GHCFRuntimeString("detail")];
    if (!detail || [detail length] == 0) return NO;
    const char *detailC = [detail UTF8String];
    // 類名 detail——框架直接 alloc 那個類，本來就正常，不攔。
    if (NSClassFromString(detail) != Nil) return NO;
    if (!GHCFPrefsIsKnownPlistName(detailC)) {
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-nav REJECTED unknown plist detail %s", detailC ? detailC : "?");
        GHCFPrefsLogLine(buf);
        return NO;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [spec setProperty:detail forKey:GHCFRuntimeString("ghcfTargetPlist")];
    GHCFPlistPageController *page = [[GHCFPlistPageController alloc] init];
    page.specifier = spec;
    page.parentController = controller;
    page.rootController = controller.rootController;
    [controller pushController:page];
    char buf[256];
    snprintf(buf, sizeof(buf), "v57 prefs-nav push plist %s", detailC ? detailC : "?");
    GHCFPrefsLogLine(buf);
    return YES;
}

// v42：任意 plist 頁——搜索結果點進來的頁：按 specifier 上的
// plistName 載入那份 plist。繼承主頁控制器，所以備份／導出／
// 導入／恢復／布局預設那些按鈕動作在這裡也一樣能用。
// （接口聲明在文件前面搜索控制器之前，這裡只寫實作。）
// v43：改讀 ghcfTargetPlist（非保留字 key），先對白名單才載，
// 載入失敗只顯示空白頁、不閃退；進出寫檔日誌。
@implementation GHCFPlistPageController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *targetPlist = self.specifier.properties[GHCFRuntimeString("ghcfTargetPlist")];
        if (!targetPlist || [targetPlist length] == 0) {
            // v43.19：重進設定恢復出來的頁，specifier 是新的，ghcfTargetPlist
            // 那個運行期寫進去的鍵沒了；退回讀 detail（行裡本來就寫著 plist 名）。
            targetPlist = self.specifier.properties[GHCFRuntimeString("detail")];
        }
        const char *cname = targetPlist ? [targetPlist UTF8String] : NULL;
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-search plistpage entry plist %s", cname ? cname : "(nil)");
        GHCFPrefsLogLine(buf);
        if (targetPlist && [targetPlist length] > 0 && GHCFPrefsIsKnownPlistName(cname)) {
            @try {
                _specifiers = [self loadSpecifiersFromPlistName:targetPlist target:self];
            } @catch (NSException *e) {
                char ebuf[512];
                snprintf(ebuf, sizeof(ebuf), "v57 prefs-search plistpage EXCEPTION %s %s", [[e name] UTF8String], [[e reason] UTF8String]);
                GHCFPrefsLogLine(ebuf);
                NSMutableArray *safe = [NSMutableArray array];
                PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
                [group setProperty:GHCFRuntimeString("这一页打不开（已记进日志），先回上一页再试。") forKey:GHCFRuntimeString("footerText")];
                [safe addObject:group];
                _specifiers = safe;
            }
            if (!_specifiers) _specifiers = [NSMutableArray array];
        } else {
            GHCFPrefsLogLine("v57 prefs-search plistpage REJECTED unknown plist");
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:GHCFRuntimeString("这一页打不开（已记进日志），先回上一页再试。") forKey:GHCFRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
        // China Fly 1.0.0：Keyboard.plist 已刪，鍵盤過濾整段拿掉。
        // v43.32：觸發方式下面三套按方式動態換行——ARC 只留 ARC 兩行
        //（arcStartAngle／arcFanAngle），邊緣只留邊緣那套（觸發側／
        // 滑幾次／左／右×豎／橫屏各三根滑桿），懸浮條只留懸浮條兩行
        //（floatingBarY／floatingBarSize）；調試開關和觸發方式行本身
        // 三套通用，一直留著。行和組頭都帶 ghcfTriggerSet 標記
        //（arc／edge／bar），沒標記的都留。模式變了回這一頁時
        // viewWillAppear 已清快取重組（v71），讀到的就是新值。
        if (targetPlist && [targetPlist isEqualToString:GHCFRuntimeString("Trigger")]) {
            char *tmode = GHCFPrefsCString("triggerMode");
            const char *want = "edge";
            if (tmode) {
                if (strcmp(tmode, "arc") == 0) want = "arc";
                else if (strcmp(tmode, "bar") == 0) want = "bar";
                free(tmode);
            }
            NSMutableArray *kept = [NSMutableArray array];
            for (PSSpecifier *sp in _specifiers) {
                NSString *setTag = sp.properties[GHCFRuntimeString("ghcfTriggerSet")];
                if (setTag && strcmp([setTag UTF8String], want) != 0) continue;
                [kept addObject:sp];
            }
            _specifiers = kept;
        }
        char buf2[128];
        snprintf(buf2, sizeof(buf2), "v57 prefs-search plistpage exit count %lu", (unsigned long)[_specifiers count]);
        GHCFPrefsLogLine(buf2);
        // v71：頁面載入時記一行 plist 名＋item 數量——下次日誌直接證明
        // 載的是新版還是舊版（1.0.70 兩行看不到，靠這行定位）。
        {
            char pbuf[256];
            snprintf(pbuf, sizeof(pbuf), "v71 prefs-page %s items %lu", cname ? cname : "(nil)", (unsigned long)[_specifiers count]);
            GHCFPrefsLogLine(pbuf);
        }
    }
    return _specifiers;
}

// v71：子頁每次出現都清快取重組（學手勢總覽頁 v54——只讀快取頁回來看見的
// 必須是新值，舊 specifiers 會 stale；1.0.70 的新行在手機上看不到，
// 每頁快取就是頭號嫌疑）。
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    @try {
        _specifiers = nil;
        [self reloadSpecifiers];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v71 prefs-plistpage viewWillAppear EXCEPTION %s", reason);
        GHCFPrefsLogLine(buf);
    }
}

@end

@implementation GHCFLinkListController

// v72：LinkList 子清單——從點按那行（self.specifier）的 values／titles 現場建單選行。
// 每個選項一行 PSListItemCell（單選圓點行），values 只有那一個值；
// 當前值由繼承的 readPreferenceValue 讀（沒存過回 plist 的 default），框架照它打勾。
- (NSArray *)specifiers {
    if (!_specifiers) {
        PSSpecifier *parent = self.specifier;
        NSArray *values = parent ? parent.properties[GHCFRuntimeString("values")] : nil;
        NSArray *titles = parent ? parent.properties[GHCFRuntimeString("titles")] : nil;
        // v43.11：跟攔截一樣，values／titles 讀不到改讀 validValues／validTitles
        //（plist 行就是這個名字；建出來的選項行照舊只寫 values，寫值路只讀 values）。
        if (!values || [values count] == 0) {
            values = parent ? parent.properties[GHCFRuntimeString("validValues")] : nil;
            titles = parent ? parent.properties[GHCFRuntimeString("validTitles")] : nil;
        }
        NSString *key = parent ? parent.properties[GHCFRuntimeString("key")] : nil;
        NSString *defaults = parent ? parent.properties[GHCFRuntimeString("defaults")] : nil;
        id def = parent ? parent.properties[GHCFRuntimeString("default")] : nil;
        NSMutableArray *specs = [NSMutableArray array];
        if (values && [values count] > 0 && key) {
            for (NSUInteger i = 0; i < [values count]; i++) {
                id value = [values objectAtIndex:i];
                NSString *title = nil;
                if (titles && i < [titles count]) title = [titles objectAtIndex:i];
                if (!title) title = [value description];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSListItemCell edit:nil];
                [spec setProperty:[NSArray arrayWithObject:value] forKey:GHCFRuntimeString("values")];
                [spec setProperty:key forKey:GHCFRuntimeString("key")];
                if (defaults) [spec setProperty:defaults forKey:GHCFRuntimeString("defaults")];
                if (def) [spec setProperty:def forKey:GHCFRuntimeString("default")];
                [specs addObject:spec];
            }
            const char *keyC = [key UTF8String];
            char buf[256];
            snprintf(buf, sizeof(buf), "v72 prefs-linklist %s options %lu", keyC ? keyC : "?", (unsigned long)[values count]);
            GHCFPrefsLogLine(buf);
        } else {
            // values 讀不到——不推空白頁，顯示一行說明（下次日誌能看到）。
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:GHCFRuntimeString("选项读不到，先回上一页再试。") forKey:GHCFRuntimeString("footerText")];
            [specs addObject:group];
            GHCFPrefsLogLine("v72 prefs-linklist no values at build");
        }
        _specifiers = specs;
    }
    return _specifiers;
}

// v72：子頁每次出現都清快取重組（跟 PlistPage 同做法——只讀快取頁回來看見的
// 必須是新值，選中的勾才跟得上）。
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    @try {
        _specifiers = nil;
        [self reloadSpecifiers];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v72 prefs-linklist viewWillAppear EXCEPTION %s", reason);
        GHCFPrefsLogLine(buf);
    }
}

// v72：LinkList 選項寫值記一行（框架原生的 PSListItemsController 寫值走它
// 自己的控制器，繞過我們有記日誌的 setPreferenceValue——這就是 24.log 裡
// exitAnimation／launcherStyle／keyboardPopupMode 一行 prefs-set 都沒有的原因）。
// 這裡先記 v72 prefs-linklist，再調繼承的 setPreferenceValue 真正寫入
//（CFPreferencesSetAppValue＋AppSynchronize，跟開關／滑桿同一條路）。
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[GHCFRuntimeString("key")];
    const char *keyC = key ? [key UTF8String] : "?";
    const char *valC = value ? [[value description] UTF8String] : "?";
    char buf[256];
    snprintf(buf, sizeof(buf), "v72 prefs-linklist %s = %s", keyC, valC);
    GHCFPrefsLogLine(buf);
    [super setPreferenceValue:value specifier:specifier];
}

// v43.11：LinkList 選項行點按自己寫值——框架原生的 PSListController 不負責給
// PSListItemCell 行寫值（那是 PSListItemsController 的活，我們在 v43.10 繞過了它），
// 所以這頁以前只能看不能改（30.log：點選項 0 行寫值日誌）。取該行 values[0] 調
// [self setPreferenceValue:values[0] specifier:spec]（上面 v72 記日誌＋繼承寫值＋
// 同步），再 pop 回上一頁（原生 LinkList 點選後自動返回；挑選頁 viewDidAppear
// 會 reloadSpecifiers＋按新間隔重開計時器，不用再補）。不是 PSListItemCell 的行
// 或 values 讀不到就走 super。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if (spec && spec.cellType == PSListItemCell) {
        NSArray *values = spec.properties[GHCFRuntimeString("values")];
        if (values && [values count] > 0) {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            [self setPreferenceValue:[values objectAtIndex:0] specifier:spec];
            [self.navigationController popViewControllerAnimated:YES];
            return;
        }
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

@end

// China Fly 1.0.0：狀態頁（GHCFStatusListController）與鍵盤助手標記
//（GHCFKbHelperMarkersText）已整段拿掉。激活頁（下面兩類）是 1.0.0
// 新加的（皇上 21:34 定，照舊分屏 1.0.103 那套；碼表跟舊分屏用同一份
// 線上的 codes.json，實現、鍵、通知名全用 China Fly 自己的）。
// 除了共用這份碼表，China Fly 別的什麼都不碰舊分屏（皇上 21:36 定）。

@interface GHCFActivationRowCell : PSTableCell
@end

@implementation GHCFActivationRowCell {
    UIImageView *_actIconView;
    UILabel *_actTitleLabel;
    UILabel *_actSubtitleLabel;
    UILabel *_actValueLabel;
    UIImageView *_actChevronView;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.accessoryType = UITableViewCellAccessoryNone;
        _actIconView = [[UIImageView alloc] init];
        _actIconView.contentMode = UIViewContentModeScaleAspectFit;
        _actIconView.tintColor = [UIColor systemBlueColor];
        [self.contentView addSubview:_actIconView];
        _actTitleLabel = [[UILabel alloc] init];
        _actTitleLabel.font = [UIFont systemFontOfSize:16];
        _actTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_actTitleLabel];
        _actSubtitleLabel = [[UILabel alloc] init];
        _actSubtitleLabel.font = [UIFont systemFontOfSize:13];
        _actSubtitleLabel.textColor = [UIColor grayColor];
        _actSubtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_actSubtitleLabel];
        _actValueLabel = [[UILabel alloc] init];
        _actValueLabel.font = [UIFont systemFontOfSize:16];
        _actValueLabel.textColor = [UIColor grayColor];
        _actValueLabel.textAlignment = NSTextAlignmentRight;
        _actValueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_actValueLabel];
        _actChevronView = [[UIImageView alloc] init];
        _actChevronView.contentMode = UIViewContentModeScaleAspectFit;
        _actChevronView.tintColor = [UIColor grayColor];
        [self.contentView addSubview:_actChevronView];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.textLabel.text = nil;
    self.textLabel.hidden = YES;
    self.detailTextLabel.text = nil;
    self.detailTextLabel.hidden = YES;
    NSString *title = specifier.properties[GHCFRuntimeString("label")];
    _actTitleLabel.text = title;
    NSString *subtitle = specifier.properties[GHCFRuntimeString("subtitle")];
    _actSubtitleLabel.text = subtitle;
    _actSubtitleLabel.hidden = (!subtitle || [subtitle length] == 0);
    NSString *iconName = specifier.properties[GHCFRuntimeString("iconName")];
    UIImage *icon = nil;
    if (iconName && [iconName length] > 0) icon = [UIImage systemImageNamed:iconName];
    _actIconView.image = icon;
    _actIconView.hidden = (icon == nil);
    NSString *value = specifier.properties[GHCFRuntimeString("valueText")];
    _actValueLabel.text = value;
    _actValueLabel.hidden = (!value || [value length] == 0);
    BOOL hasAction = (specifier.properties[GHCFRuntimeString("action")] != nil);
    if (hasAction) {
        _actChevronView.image = [UIImage systemImageNamed:GHCFRuntimeString("chevron.right")];
        _actChevronView.hidden = NO;
    } else {
        _actChevronView.image = nil;
        _actChevronView.hidden = YES;
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat textX = _actIconView.hidden ? 15 : 53;
    CGFloat textRight = w - 15;
    if (!_actChevronView.hidden) textRight = w - 40;
    if (!_actIconView.hidden) _actIconView.frame = CGRectMake(15, (h - 28) / 2, 28, 28);
    if (!_actChevronView.hidden) _actChevronView.frame = CGRectMake(w - 25, (h - 14) / 2, 10, 14);
    CGFloat valueW = _actValueLabel.hidden ? 0 : 160;
    if (valueW > 0) _actValueLabel.frame = CGRectMake(textRight - valueW, 0, valueW, h);
    CGFloat titleW = textRight - valueW - (valueW > 0 ? 8 : 0) - textX;
    if (titleW < 0) titleW = 0;
    if (_actSubtitleLabel.hidden) {
        _actTitleLabel.frame = CGRectMake(textX, 0, titleW, h);
    } else {
        _actTitleLabel.frame = CGRectMake(textX, 7, titleW, 22);
        _actSubtitleLabel.frame = CGRectMake(textX, 29, titleW, 18);
    }
}

@end

// ChinaFly 1.0.0：激活页（两张卡：上卡激活／赞助／管理三行，下卡状态行＋
// 加入群组＋底部「关于 China Fly」）。状态文字走同一套
// GHCFPrefsActivationStatusText。值行在 -specifiers 里现填，viewWillAppear 重载。
@interface GHCFActivationListController : ChinaFlyRootListController
@end

@implementation GHCFActivationListController

- (void)viewDidLoad {
    @try {
        [super viewDidLoad];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "ChinaFly prefs-activation viewDidLoad EXCEPTION %s", reason);
        GHCFPrefsLogLine(buf);
    }
    GHCFPrefsLogLine("ChinaFly prefs-page: Activation");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    char buf[160];
    snprintf(buf, sizeof(buf), "ChinaFly prefs-activation tap: section %ld row %ld", (long)indexPath.section, (long)indexPath.row);
    GHCFPrefsLogLine(buf);
    if (GHCFHandlePlistDetailTap(self, tableView, indexPath)) return;
    if (GHCFDispatchButtonTap(self, tableView, indexPath)) return;
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return 56;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        @try {
            NSMutableArray *loaded = [self loadSpecifiersFromPlistName:GHCFRuntimeString("Activation") target:self];
            for (PSSpecifier *spec in loaded) {
                NSString *vk = spec.properties[GHCFRuntimeString("valueKey")];
                if (![vk isKindOfClass:[NSString class]]) continue;
                if ([vk isEqualToString:GHCFRuntimeString("activationState")]) {
                    [spec setProperty:GHCFPrefsActivationStatusText() forKey:GHCFRuntimeString("valueText")];
                } else if ([vk isEqualToString:GHCFRuntimeString("systemVersion")]) {
                    NSString *ver = [[UIDevice currentDevice] systemVersion];
                    NSString *txt = [GHCFRuntimeString("iOS ") stringByAppendingString:(ver ? ver : GHCFRuntimeString("?"))];
                    [spec setProperty:txt forKey:GHCFRuntimeString("valueText")];
                } else if ([vk isEqualToString:GHCFRuntimeString("pluginVersion")]) {
                    [spec setProperty:GHCFRuntimeString("1.0.0") forKey:GHCFRuntimeString("valueText")];
                }
            }
            _specifiers = loaded;
        } @catch (NSException *e) {
            const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
            char buf[512];
            snprintf(buf, sizeof(buf), "ChinaFly prefs-activation specifiers EXCEPTION %s", reason);
            GHCFPrefsLogLine(buf);
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:GHCFRuntimeString("激活页打不开（已记进日志），先回上一页再试。") forKey:GHCFRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
        if (!_specifiers) _specifiers = [NSMutableArray array];
    }
    return _specifiers;
}

// 提示框改走最上层 presenter、主队列（同 ghcfShowAlertWithTitle
// 的做法；本页的输入框／操作表不能走那个只带「好」的 helper）。
- (void)ghcfActivationPresent:(UIAlertController *)alert {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = self;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        if (!presenter.view.window) {
            UIWindow *keyWindow = nil;
            for (UIScene *s in [[UIApplication sharedApplication] connectedScenes]) {
                if (![s isKindOfClass:[UIWindowScene class]]) continue;
                UIWindowScene *ws = (UIWindowScene *)s;
                if (ws.activationState != UISceneActivationStateForegroundActive) continue;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
                if (keyWindow) break;
            }
            if (keyWindow && keyWindow.rootViewController) {
                presenter = keyWindow.rootViewController;
                while (presenter.presentedViewController) presenter = presenter.presentedViewController;
            }
        }
        if (alert.popoverPresentationController) {
            alert.popoverPresentationController.sourceView = self.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        }
        if (presenter) {
            [presenter presentViewController:alert animated:YES completion:nil];
        } else {
            GHCFPrefsLogLine("ChinaFly prefs-activation present FAILED: no presenter");
        }
    });
}

// 发 Darwin 通知给 dylib 重抓名单对码，4 秒后重载本页（状态行自己翻成
// 「您的设备已授权」／「未授权」，不用退出重进）。
- (void)ghcfActivationPostRecheck {
    notify_post("com.guhailong.fly.activationRecheck");
    GHCFPrefsLogLine("ChinaFly prefs-activation recheck posted");
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf reloadSpecifiers];
    });
}

// 上卡第 1 行：弹输入框输激活码，确认就写 prefs＋发检查（码不记日志）。
- (void)ghcfActivationEnterCode:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("激活正版授权") message:GHCFRuntimeString("输入激活码来绑定当前的设备。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = GHCFRuntimeString("激活码，如 SD-XXXX-XXXX-XXXX");
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:GHCFRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    __weak UIAlertController *weakAlert = alert;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:GHCFRuntimeString("确认") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        UIAlertController *strongAlert = weakAlert;
        NSString *raw = strongAlert ? strongAlert.textFields.firstObject.text : nil;
        NSString *code = [[raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
        if (!code || [code length] == 0) {
            [self ghcfShowAlertWithTitle:GHCFRuntimeString("请输入激活码") message:GHCFRuntimeString("激活码是空的，先输入再确认。")];
            return;
        }
        CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
        if (domain) {
            CFStringRef cfKey = GHCFRuntimeCFString("activationCode");
            if (cfKey) {
                CFPreferencesSetAppValue(cfKey, (__bridge CFPropertyListRef)code, domain);
                CFRelease(cfKey);
            }
            CFPreferencesAppSynchronize(domain);
            CFRelease(domain);
        }
        [self ghcfActivationPostRecheck];
        [self ghcfShowAlertWithTitle:GHCFRuntimeString("已发送检查") message:GHCFRuntimeString("已发送检查，稍等几秒再看「当前授权状态」，通过了会显示「您的设备已授权」。")];
    }];
    [alert addAction:cancel];
    [alert addAction:ok];
    [self ghcfActivationPresent:alert];
}

// 上卡第 2 行：没有在线购买页，去 Telegram 频道找 Lee 要码。
- (void)ghcfActivationSponsor:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("赞助购买授权") message:GHCFRuntimeString("没有在线购买页，去 Telegram 频道找 Lee 要激活码。") preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:GHCFRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *open = [UIAlertAction actionWithTitle:GHCFRuntimeString("打开频道") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [self ghcfActivationOpenTelegramChannel];
    }];
    [alert addAction:cancel];
    [alert addAction:open];
    [self ghcfActivationPresent:alert];
}

// 设置页进程里 openURL 不可靠，先顺手试 tg:// 深链，
// 不管成不成都复制 https 邀请链接＋弹「已复制」，保证链接一定到手。
- (void)ghcfActivationOpenTelegramChannel {
    NSURL *tgURL = [NSURL URLWithString:GHCFRuntimeString("tg://join?invite=UaeIYedetWtiZGQ1")];
    if (tgURL) {
        [[UIApplication sharedApplication] openURL:tgURL options:[NSDictionary dictionary] completionHandler:^(BOOL success) {
            (void)success;
            dispatch_async(dispatch_get_main_queue(), ^{
                GHCFPrefsLogLine("ChinaFly prefs-activation telegram tg attempted");
            });
        }];
    }
    [UIPasteboard generalPasteboard].string = GHCFRuntimeString("https://t.me/+UaeIYedetWtiZGQ1");
    GHCFPrefsLogLine("ChinaFly prefs-activation telegram copied");
    [self ghcfShowAlertWithTitle:GHCFRuntimeString("已复制") message:GHCFRuntimeString("Telegram 频道链接已复制到剪贴板，去 Telegram 贴上进群找 Lee 要码。")];
}

// 上卡第 3 行：清除已保存的激活码、重新检查。
- (void)ghcfActivationManage:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("管理配置授权") message:GHCFRuntimeString("重置配置，授权找回等操作。") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *clear = [UIAlertAction actionWithTitle:GHCFRuntimeString("清除已保存的激活码") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action;
        CFStringRef domain = GHCFRuntimeCFString("com.guhailong.fly");
        if (domain) {
            CFStringRef cfKey = GHCFRuntimeCFString("activationCode");
            if (cfKey) {
                CFPreferencesSetAppValue(cfKey, NULL, domain);
                CFRelease(cfKey);
            }
            CFPreferencesAppSynchronize(domain);
            CFRelease(domain);
        }
        [self ghcfActivationPostRecheck];
        [self ghcfShowAlertWithTitle:GHCFRuntimeString("已清除") message:GHCFRuntimeString("已保存的激活码已清除，状态回到未授权。")];
    }];
    UIAlertAction *recheck = [UIAlertAction actionWithTitle:GHCFRuntimeString("重新检查激活码") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [self ghcfActivationPostRecheck];
        [self ghcfShowAlertWithTitle:GHCFRuntimeString("已发送检查") message:GHCFRuntimeString("已发送检查，稍等几秒再看「当前授权状态」。")];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:GHCFRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    [sheet addAction:clear];
    [sheet addAction:recheck];
    [sheet addAction:cancel];
    [self ghcfActivationPresent:sheet];
}

// 下卡：加入官方群组——QQ 群号复制、Telegram 频道。
- (void)ghcfActivationJoinGroup:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:GHCFRuntimeString("加入官方群组") message:GHCFRuntimeString("选择加入官方交流群") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *qq = [UIAlertAction actionWithTitle:GHCFRuntimeString("QQ 群 1130823454") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [UIPasteboard generalPasteboard].string = GHCFRuntimeString("1130823454");
        GHCFPrefsLogLine("ChinaFly prefs-activation QQ group copied");
        [self ghcfShowAlertWithTitle:GHCFRuntimeString("已复制") message:GHCFRuntimeString("QQ交流群 1130823454 已复制到剪贴板，去 QQ 搜索群号加入。")];
    }];
    UIAlertAction *tg = [UIAlertAction actionWithTitle:GHCFRuntimeString("Telegram 频道") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [self ghcfActivationOpenTelegramChannel];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:GHCFRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    [sheet addAction:qq];
    [sheet addAction:tg];
    [sheet addAction:cancel];
    [self ghcfActivationPresent:sheet];
}

@end
