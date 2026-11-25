// China Fly 1.0.0 — 設置頁（PreferenceLoader）。
// 從 v43.42（舊分屏 1.0.115，頭 653fcaa）改過來的設置頁：
// 歌詞播放器、激活、檢查更新、狀態頁已拿掉；備份／恢復留下；
// 選擇應用加搜索欄＋首次默認開影片裡的 8 個；菜單編輯是新的
// CFLYMenuEditListController（UITableViewController，可拖動排序）；
// 觸發鈕圖默認改成代碼畫的紙飛機。子頁是獨立 plist（Dial／
// SplitSettings／MenuEdit／Trigger／ActionButtonTap／
// ActionButtonLongPress／FloatingIcon），由 PreferenceLoader 的預設
// 控制器載入；「選擇應用」是動態頁（CFLYAppPickerListController，
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
// Apple 類＋CFLYLauncher 一個自訂類）。
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <Preferences/PSSwitchTableCell.h>
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

// 运行时现做一个 NSString（不用写死字串）。
static NSString *CFLYRuntimeString(const char *cstr) {
    return [NSString stringWithCString:cstr encoding:NSUTF8StringEncoding];
}

// 运行时现做一个 CFStringRef（不用 CFSTR），用完要 CFRelease。
static CFStringRef CFLYRuntimeCFString(const char *cstr) {
    return CFStringCreateWithCString(NULL, cstr, kCFStringEncodingUTF8);
}

// 設定檔目錄（設定 App 的 mobile 用戶可寫）。
static NSString *CFLYPrefsDir(void) {
    return CFLYRuntimeString("/var/mobile/Library/Preferences");
}

static NSString *CFLYBackupFilePath(void) {
    return [CFLYPrefsDir() stringByAppendingPathComponent:CFLYRuntimeString("ChinaFly-backup.plist")];
}

static NSString *CFLYAppCacheFilePath(void) {
    return [CFLYPrefsDir() stringByAppendingPathComponent:CFLYRuntimeString("ChinaFly-apps.plist")];
}

// 讀一個 prefs BOOL（沒設就回預設值）。
static BOOL CFLYPrefsBool(const char *key, BOOL defaultValue) {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    CFStringRef keyRef = CFLYRuntimeCFString(key);
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

// ChinaFly 1.0.1: 讀舊分屏域的 enabled 鍵（休眠提示用；跟 dylib 的
// CFLYReadOldSplitscreenEnabled 同一套做法）。1.0.3 起提示條件改成
// 開關開著 AND 舊 dylib 文件還在（見 CFLYPrefsShouldDormantForOldSplitscreen）。
static BOOL CFLYPrefsReadOldSplitscreenEnabled(void) {
    CFStringRef domain = CFLYRuntimeCFString("com.guhailong.splitscreen");
    CFStringRef keyRef = CFLYRuntimeCFString("enabled");
    BOOL out = NO;
    if (domain && keyRef) {
        CFPreferencesAppSynchronize(domain);
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

// ChinaFly 1.0.3：舊分屏的 dylib 文件還在不在（跟 dylib 那邊同一套：
// 先查 rootless 路徑 /var/jb/...，再查 /Library/...）。
static BOOL CFLYPrefsOldSplitscreenDylibExists(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *jbPath = CFLYRuntimeString("/var/jb/Library/MobileSubstrate/DynamicLibraries/GuHaiLongSplitScreen.dylib");
    NSString *libPath = CFLYRuntimeString("/Library/MobileSubstrate/DynamicLibraries/GuHaiLongSplitScreen.dylib");
    if (jbPath && [fm fileExistsAtPath:jbPath]) return YES;
    if (libPath && [fm fileExistsAtPath:libPath]) return YES;
    return NO;
}
// ChinaFly 1.0.3：休眠條件改成「舊開關開著 AND 舊 dylib 文件還在」
//（跟 dylib 的 CFLYShouldDormantForOldSplitscreen 同一個條件，提示跟
// dylib 對不上會騙人）。舊包刪了、只剩殘留 prefs 時不再顯示休眠提示。
static BOOL CFLYPrefsShouldDormantForOldSplitscreen(void) {
    return CFLYPrefsReadOldSplitscreenEnabled() && CFLYPrefsOldSplitscreenDylibExists();
}

// 讀一個 prefs 字串（沒設就回 NULL，調用處要 free）。
static char *CFLYPrefsCString(const char *key) {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    CFStringRef keyRef = CFLYRuntimeCFString(key);
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
static void CFLYWritePrefsBool(const char *key, BOOL value) {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    CFStringRef keyRef = CFLYRuntimeCFString(key);
    if (domain && keyRef) {
        CFPreferencesSetAppValue(keyRef, value ? kCFBooleanTrue : kCFBooleanFalse, domain);
        CFPreferencesAppSynchronize(domain);
    }
    if (domain) CFRelease(domain);
    if (keyRef) CFRelease(keyRef);
}

// 寫一個 prefs 字串（NULL = 清掉那個鍵），立刻落盤。
static void CFLYWritePrefsCString(const char *key, const char *value) {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    CFStringRef keyRef = CFLYRuntimeCFString(key);
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
// 没值＝还没检查）。1.0.4（P1）：說法換得更直白。
// ChinaFly 1.0.5：授權取消——dylib 不再對碼、永遠寫 authorized；
// 還沒值（剛裝、dylib 還沒跑）也顯示已授權，不再顯示「尚未驗證」。
// locked 那行留著當兜底（舊版寫下的 locked 值、或以後恢復授權時用）。
static NSString *CFLYPrefsActivationStatusText(void) {
    char *state = CFLYPrefsCString("activationState");
    NSString *out;
    if (state && strcmp(state, "authorized") == 0) {
        out = CFLYRuntimeString("已授權，China Fly 可以使用");
    } else if (state && strcmp(state, "locked") == 0) {
        out = CFLYRuntimeString("未授權，請輸入激活碼");
    } else if (state && strcmp(state, "checkFailed") == 0) {
        out = CFLYRuntimeString("名單讀不到，暫不鎖定（檢查網絡）");
    } else {
        out = CFLYRuntimeString("已授權（1.0.5 起無需激活碼）");
    }
    if (state) free(state);
    return out;
}


// 先聲明（下面定義；輪播 helper 要記日誌，先用）。
static void CFLYPrefsLogLine(const char *line);
// v53：觸發鈕自訂圖的固定檔名（跟卡片頭像／背景同一個設定目錄；
// dylib 那邊 CFLYCustomFlyTriggerImagePath 寫死同一條路徑）。
static NSString *CFLYFlyTriggerIconPath(void) {
    return [CFLYPrefsDir() stringByAppendingPathComponent:CFLYRuntimeString("ChinaFly-flyTrigger.jpg")];
}

static NSString *CFLYLogFilePath(void) {
    return CFLYRuntimeString("/var/mobile/Library/Logs/ChinaFly.log");
}


// v42：日誌尾段（預設最後 200 行）、最新在最上面（跟浮窗卡片同一份寫法）。
// v50：讀檔防呆——檔案不存在／讀不到回提示文字；超過 256KB 只取尾段
// （切口可能斷掉一個多字節字，讀不出來就退回整檔讀）；讀到幾行記在
// CFLYLogTailLinesRead，呼叫方寫日誌用。
static int CFLYLogTailLinesRead = 0;
static NSString *CFLYLogTailNewestFirst(void) {
    NSData *data = [NSData dataWithContentsOfFile:CFLYLogFilePath()];
    if (!data || [data length] == 0) {
        CFLYLogTailLinesRead = 0;
        return CFLYRuntimeString("还没有日志（档案不存在或读不到）。");
    }
    if ([data length] > 262144) {
        data = [data subdataWithRange:NSMakeRange([data length] - 262144, 262144)];
    }
    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!content) content = [NSString stringWithContentsOfFile:CFLYLogFilePath() encoding:NSUTF8StringEncoding error:nil];
    if (!content) {
        CFLYLogTailLinesRead = 0;
        return CFLYRuntimeString("还没有日志（档案不存在或读不到）。");
    }
    NSArray *lines = [content componentsSeparatedByString:CFLYRuntimeString("\n")];
    NSMutableArray *last = [NSMutableArray array];
    NSInteger start = (NSInteger)[lines count] - 200;
    if (start < 0) start = 0;
    for (NSInteger i = (NSInteger)[lines count] - 1; i >= start; i--) {
        [last addObject:[lines objectAtIndex:i]];
    }
    CFLYLogTailLinesRead = (int)[last count];
    return [last componentsJoinedByString:CFLYRuntimeString("\n")];
}

// v43：prefs 側寫檔日誌（搜索閃退診斷用，跟 dylib 寫同一份
// 檔案；設定 App 也是 mobile 身份，寫得動；寫不動就靜靜算了，
// 不彈框、不擋路）。
static void CFLYPrefsLogLine(const char *line) {
    if (!line) return;
    NSString *path = CFLYLogFilePath();
    NSString *text = [NSString stringWithCString:line encoding:NSUTF8StringEncoding];
    if (!text) return;
    NSString *entry = [text stringByAppendingString:CFLYRuntimeString("\n")];
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
static UITableView *CFLYSafeTableViewForController(PSListController *controller, const char *tag) {
    if (!controller) return nil;
    const char *t = tag ? tag : "?";
    @try {
        if ([controller respondsToSelector:@selector(tableView)]) {
            UITableView *(*msgSend)(id, SEL) = (UITableView *(*)(id, SEL))objc_msgSend;
            UITableView *tv = msgSend(controller, @selector(tableView));
            if ([tv isKindOfClass:[UITableView class]]) {
                char buf[192];
                snprintf(buf, sizeof(buf), "v57 prefs-table: %s via tableView", t);
                CFLYPrefsLogLine(buf);
                return tv;
            }
        }
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-table: %s tableView EXCEPTION %s", t, why);
        CFLYPrefsLogLine(buf);
    }
    @try {
        UIView *view = controller.view;
        if ([view isKindOfClass:[UITableView class]]) {
            char buf[192];
            snprintf(buf, sizeof(buf), "v57 prefs-table: %s via self.view", t);
            CFLYPrefsLogLine(buf);
            return (UITableView *)view;
        }
        for (UIView *sub in view.subviews) {
            if ([sub isKindOfClass:[UITableView class]]) {
                char buf[192];
                snprintf(buf, sizeof(buf), "v57 prefs-table: %s via subview", t);
                CFLYPrefsLogLine(buf);
                return (UITableView *)sub;
            }
        }
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-table: %s view scan EXCEPTION %s", t, why);
        CFLYPrefsLogLine(buf);
    }
    @try {
        id iv = [controller valueForKey:CFLYRuntimeString("_tableView")];
        if ([iv isKindOfClass:[UITableView class]]) {
            char buf[192];
            snprintf(buf, sizeof(buf), "v57 prefs-table: %s via _tableView", t);
            CFLYPrefsLogLine(buf);
            return (UITableView *)iv;
        }
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-table: %s _tableView EXCEPTION %s", t, why);
        CFLYPrefsLogLine(buf);
    }
    char buf[192];
    snprintf(buf, sizeof(buf), "v57 prefs-table: %s none", t);
    CFLYPrefsLogLine(buf);
    return nil;
}

// v42：圖片居中裁方形（頭像用，512px）。
static UIImage *CFLYPrefsSquareCropImage(UIImage *image, CGFloat size) {
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
static const char *CFLYFixedNames[5];
static int CFLYFixedIndexForBundleID(const char *bid);


// 原來的 5 個固定 App（跟主插件 Tweak.xm 裡的表同一份）。
static const char *CFLYFixedBundleIDs[5] = {
    "com.apple.calculator",
    "com.apple.mobiletimer",
    "com.apple.mobilenotes",
    "com.apple.Preferences",
    "com.apple.mobileslideshow"
};
static const char *CFLYFixedNames[5] = {
    "计算器",
    "时钟",
    "备忘录",
    "设置",
    "照片"
};
static const char *CFLYFixedEnabledKeys[5] = {
    "appCalculatorEnabled",
    "appClockEnabled",
    "appNotesEnabled",
    "appSettingsEnabled",
    "appPhotosEnabled"
};

static int CFLYFixedIndexForBundleID(const char *bid) {
    if (!bid) return -1;
    for (int i = 0; i < 5; i++) {
        if (strcmp(CFLYFixedBundleIDs[i], bid) == 0) return i;
    }
    return -1;
}

// v43.24：第 6 件——自選 App 串列（customAppBundleIDs，逗號分隔 bundleID），
// 開關是 sel-<bundleID>。
static void CFLYSetCustomAppListBid(const char *bid, BOOL on) {
    if (!bid || bid[0] == '\0') return;
    NSMutableArray *ids = [NSMutableArray array];
    char *raw = CFLYPrefsCString("customAppBundleIDs");
    if (raw) {
        NSString *rawStr = [NSString stringWithCString:raw encoding:NSUTF8StringEncoding];
        free(raw);
        if (rawStr && [rawStr length] > 0) {
            NSArray *parts = [rawStr componentsSeparatedByString:CFLYRuntimeString(",")];
            for (NSString *p in parts) if ([p length] > 0 && ![ids containsObject:p]) [ids addObject:p];
        }
    }
    NSString *bidStr = [NSString stringWithCString:bid encoding:NSUTF8StringEncoding];
    [ids removeObject:bidStr];
    if (on) [ids addObject:bidStr];
    NSString *joined = [ids componentsJoinedByString:CFLYRuntimeString(",")];
    CFLYWritePrefsCString("customAppBundleIDs", [joined UTF8String]);
}

// China Fly 1.0.0：首次使用默認開的 8 個 App（照 參考影片裡
// 機主的選擇：抖音、汽水音樂 Plus、設置、DynamicCow、Facebook、
// Messenger、QQ、Telegram）。設置是固定 App（下面固定表裡已有，
// 預設開）；其餘 7 個是已裝 App，用 sel-<bid> 開關。
// 判定規則：sel-<bid> 寫過就照寫過的值；沒寫過才回默認（8 個裡
// 的回 YES，其餘回 NO）——用戶親手關掉的不會被默認蓋回來。
static BOOL CFLYIsDefaultOnAppBid(const char *bid) {
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
static BOOL CFLYSetAppInLauncherPrefs(const char *bid, BOOL on);
static BOOL CFLYAppInLauncher(const char *bid) {
    if (!bid || bid[0] == '\0') return NO;
    int fixed = CFLYFixedIndexForBundleID(bid);
    if (fixed >= 0) return CFLYPrefsBool(CFLYFixedEnabledKeys[fixed], YES);
    char selKey[160];
    snprintf(selKey, sizeof(selKey), "sel-%s", bid);
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    CFStringRef keyRef = CFLYRuntimeCFString(selKey);
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
    return CFLYIsDefaultOnAppBid(bid);
}

// 首次打開挑選器時把默認開的 8 個真正寫進 prefs（串列＋開關＋
// 已播種標記），dylib 那邊讀 customAppBundleIDs 才看得到它們；
// 只播一次，之後用戶的開關不再被默認動到。
static void CFLYSeedDefaultAppSelection(void) {
    if (CFLYPrefsBool("appPickerDefaultsSeeded", NO)) return;
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
        CFLYSetAppInLauncherPrefs(seedBids[i], YES);
    }
    CFLYWritePrefsBool("appSettingsEnabled", YES);
    CFLYWritePrefsBool("appPickerDefaultsSeeded", YES);
    CFLYPrefsLogLine("cf prefs-apppicker: seeded default 8 apps");
}

// 把某個 App 放進／拿出啟動器（跟主插件的 CFLYSetAppInLauncher 同款
// 邏輯，設定頁這邊重寫一份——設定 bundle 和主插件是兩個進程，
// 調不到主插件的函數）。沒有數量上限，永遠回 YES。
static BOOL CFLYSetAppInLauncherPrefs(const char *bid, BOOL on) {
    if (!bid || bid[0] == '\0') return NO;
    int fixed = CFLYFixedIndexForBundleID(bid);
    if (fixed >= 0) {
        CFLYWritePrefsBool(CFLYFixedEnabledKeys[fixed], on);
        return YES;
    }
    CFLYSetCustomAppListBid(bid, on);
    char selKey[160];
    snprintf(selKey, sizeof(selKey), "sel-%s", bid);
    CFLYWritePrefsBool(selKey, on);
    return YES;
}

// 寫一個 prefs 陣列（menuAppOrder 用），立刻落盤。
static void CFLYWritePrefsArray(const char *key, NSArray *value) {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    CFStringRef keyRef = CFLYRuntimeCFString(key);
    if (domain && keyRef) {
        CFPreferencesSetAppValue(keyRef, (__bridge CFPropertyListRef)value, domain);
        CFPreferencesAppSynchronize(domain);
    }
    if (domain) CFRelease(domain);
    if (keyRef) CFRelease(keyRef);
}

// 讀後台緩存的已安裝 App 清單（主插件列舉、寫檔；設定頁只讀。
// 每項是 dict：bundleID／name）。讀不到回空陣列，不回 nil。
static NSArray *CFLYReadCachedApps(void) {
    NSArray *cached = [NSArray arrayWithContentsOfFile:CFLYAppCacheFilePath()];
    if (!cached) return [NSArray array];
    return cached;
}

// 菜單項解析：entry 是 bundleID 就找對應 App 名；是顯示名就按名
// 找 bundleID；都找不到就原樣當顯示名（bid 回 nil，運行時按名找）。
// ChinaFly 1.0.3：前向聲明（定義在後面，選擇應用那頁用的同一套名字解析）。
static NSString *CFLYPrefsDisplayNameForBundleID(NSString *bid);

static void CFLYResolveMenuEntry(NSString *entry, NSString **outBid, NSString **outName) {
    NSString *bid = nil;
    NSString *name = nil;
    if (entry && [entry length] > 0) {
        int fixed = CFLYFixedIndexForBundleID([entry UTF8String]);
        if (fixed >= 0) {
            bid = entry;
            name = CFLYRuntimeString(CFLYFixedNames[fixed]);
        } else {
            NSArray *cached = CFLYReadCachedApps();
            for (id item in cached) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                // ChinaFly 1.0.5：緩存 dict 的值必須是字串才比——非字串值
                // 直接調 isEqualToString: 會 unrecognized selector 閃退。
                id rawBid = [item objectForKey:CFLYRuntimeString("bundleID")];
                id rawName = [item objectForKey:CFLYRuntimeString("name")];
                NSString *cbid = [rawBid isKindOfClass:[NSString class]] ? rawBid : nil;
                NSString *cname = [rawName isKindOfClass:[NSString class]] ? rawName : nil;
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
    // ChinaFly 1.0.3：拿不到名字時先用選擇應用那頁同一套現解
    //（localizedName → Info.plist 顯示名 → CFBundleName → 資料夾名），
    // 絕不直接顯示裸 bundleID（皇上 09:46 的規矩）；proxy 完全拿不到
    // 才回退到 entry 本身（此時那個 App 根本沒裝上）。
    if (!name || [name length] == 0) {
        NSString *key = bid ? bid : entry;
        NSString *resolved = key ? CFLYPrefsDisplayNameForBundleID(key) : nil;
        if (resolved && [resolved length] > 0) name = resolved;
        else name = entry ? entry : CFLYRuntimeString("");
    }
    if (outBid) *outBid = bid;
    if (outName) *outName = name;
}

// 菜單默認順序（照 參考影片露出的前 17 個，原樣保留；
// 微信在影片裡出現多次，這裡照列出的順序留三個。知道 bundleID
// 的存 bundleID，不知道的存顯示名，運行時按名找）。
static NSArray *CFLYDefaultMenuOrder(void) {
    return [NSArray arrayWithObjects:
        CFLYRuntimeString("com.apple.Preferences"),
        CFLYRuntimeString("com.tencent.xin"),
        CFLYRuntimeString("com.apple.calculator"),
        CFLYRuntimeString("AppsDump3"),
        CFLYRuntimeString("com.ss.iphone.ugc.Aweme"),
        CFLYRuntimeString("愛思全能版"),
        CFLYRuntimeString("com.tencent.mqq"),
        CFLYRuntimeString("com.tencent.xin"),
        CFLYRuntimeString("酷我音樂"),
        CFLYRuntimeString("虛擬定位"),
        CFLYRuntimeString("com.matteozappa.DynamicCowTS"),
        CFLYRuntimeString("com.facebook.Messenger"),
        CFLYRuntimeString("ph.telegra.Telegram"),
        CFLYRuntimeString("com.facebook.Facebook"),
        CFLYRuntimeString("com.tencent.xin"),
        nil];
}

// 讀 menuAppOrder（沒存過就寫一份默認順序再回它；
// 存過但不是字串陣列就當沒存過，照默認來）。
static NSMutableArray *CFLYReadMenuOrder(void) {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    CFStringRef keyRef = CFLYRuntimeCFString("menuAppOrder");
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
        order = [NSMutableArray arrayWithArray:CFLYDefaultMenuOrder()];
        CFLYWritePrefsArray("menuAppOrder", order);
        CFLYPrefsLogLine("cf prefs-menuedit: seeded default menu order");
    }
    return order;
}

static void CFLYWriteMenuOrder(NSArray *order) {
    if (!order) order = [NSArray array];
    CFLYWritePrefsArray("menuAppOrder", order);
}

// 代碼畫的紙飛機（觸發鈕默認圖；不要引用已刪的哆啦A夢 png）。
// 機頭朝右上，兩片折面一深一淺。
static UIImage *CFLYPaperPlaneImage(CGFloat size) {
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

// v47：見下面 CFLYHandlePlistDetailTap 的定義——定義要用到白名單
// CFLYPrefsIsKnownPlistName 與 PlistPage 的接口聲明，都在文件後面，
// 這裡先給原型（主頁控制器與 PlistPage 共用同一個 didSelectRow）。
static BOOL CFLYHandlePlistDetailTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath);

// v72：見下面 CFLYHandleLinkListTap 的定義——LinkList 點按攔截，
// 推我們自己的 CFLYLinkListController（定義在文件後面，這裡先給原型）。
static BOOL CFLYHandleLinkListTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath);

// China Fly 1.0.0：見下面 CFLYHandleMenuEditTap 的定義——detail 是
// CFLYMenuEditListController 的連結行攔下來自己推（它是
// UITableViewController 子類，框架預設的推頁路徑推不動）。
static BOOL CFLYHandleMenuEditTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath);

// China Fly 1.0.4：見下面 CFLYHandleMenuAddTap 的定義——detail 是
// CFLYMenuAddListController 的連結行攔下來自己推（它是
// PSListController 子類，動態組行；框架預設的推頁路徑推不動）。
static BOOL CFLYHandleMenuAddTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath);

// v43：手動派發 PSButtonCell 點按——不再賭框架會不會從 action 字串派發。
// 診斷：plist 的 action 字串、程式現拼的 action 字串、方法、target 全部合規，
// 但皇上在 v42 真機測到五個操作行點了完全沒反應；框架內部到底讀
// specifier->action 還是 properties 裡的 action 字串，靜態查不到，
// 所以直接在 didSelectRow 裡讀 action 字串、轉 SEL、在 target（沒有就 self）上跑。
// v54：N 定死——v52 加的 `SEL specAction = spec->action;` 整行刪掉：
// arm64e 上編譯器給這行直接 ivar 讀取生成帶 PAC 認證的載入，plist 載入
// 的按鈕那個值認證不過就 trap（.ips：CFLYDispatchButtonTap+552 `brk`，
// 呼叫方是狀態頁；19.log:11626 遊戲布局點按後無動作行，死在同一行）。
// action 只走 properties（v43/v44 就是這樣派發，遊戲布局走通過）。
// 注意：@try/@catch 只防 ObjC 例外，PAC trap 是硬體 trap、防不住——
// 真正的修法就是刪掉這行讀取，@try/@catch 只是第二道防線。
// 回傳 YES 表示這一行已經處理了（呼叫方直接 return，不要再走 super，免得重複跑）。
static BOOL CFLYDispatchButtonTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    if (!controller || !indexPath) return NO;
    @try {
    PSSpecifier *spec = [controller specifierAtIndexPath:indexPath];
    if (!spec) {
        CFLYPrefsLogLine("v57 prefs-config tap: no specifier for tap");
        return NO;
    }
    // v52：入口先記一行（section／row／cellType），點了沒反應時日誌看得見
    // 派發走到哪一步——之前這裡靜默回 NO，狀態頁的點按在日誌裡全無痕跡。
    {
        char tapBuf[160];
        snprintf(tapBuf, sizeof(tapBuf), "v57 prefs-config tap: section %ld row %ld cellType %d", (long)indexPath.section, (long)indexPath.row, (int)spec.cellType);
        CFLYPrefsLogLine(tapBuf);
    }
    if (spec.cellType != PSButtonCell) return NO;
    // v54：action 只走 properties，絕不再碰 spec->action ivar（見上面）。
    NSString *actionName = [spec propertyForKey:CFLYRuntimeString("action")];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!actionName || [actionName length] == 0) {
        CFLYPrefsLogLine("v57 prefs-config tap: button without action");
        return YES;
    }
    const char *actionC = [actionName UTF8String];
    SEL action = NSSelectorFromString(actionName);
    id target = spec.target;
    if (!target) target = controller;
    char buf[320];
    snprintf(buf, sizeof(buf), "v57 prefs-config tap: action %s target %s", actionC ? actionC : "?", [NSStringFromClass([target class]) UTF8String]);
    CFLYPrefsLogLine(buf);
    // v44：action 字串是裸名（沒有冒號），但方法都帶一個參數（PSSpecifier *），
    // 真正的 selector 有冒號（例如 cflyBackupConfig:）。裸名先試，不回應就補冒號再試。
    // 這也是為什麼框架自己的派發在 v42 也不動——框架也是拿同一個裸名字串轉 SEL，
    // respondsToSelector 永遠回 NO，點按就這樣被靜靜吞掉了。
    if (![target respondsToSelector:action]) {
        CFLYPrefsLogLine("v57 prefs-config tap: bare name does not respond, trying colon");
        NSString *colonName = [actionName stringByAppendingString:CFLYRuntimeString(":")];
        SEL colonAction = NSSelectorFromString(colonName);
        if ([target respondsToSelector:colonAction]) {
            action = colonAction;
            CFLYPrefsLogLine("v57 prefs-config tap: colon selector responds");
        }
    }
    if (![target respondsToSelector:action]) {
        CFLYPrefsLogLine("v57 prefs-config tap: target does not respond to bare or colon, falling through to super");
        return NO;
    }
    // v44：變數 SEL 不能用 performSelector（-Werror 下 -Warc-performSelector-leaks），
    // 用 v41 就在用的 objc_msgSend 寫法。
    ((void (*)(id, SEL, id))objc_msgSend)(target, action, spec);
    snprintf(buf, sizeof(buf), "v57 prefs-config tap: dispatched %s", [NSStringFromSelector(action) UTF8String]);
    CFLYPrefsLogLine(buf);
    return YES;
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[512];
        snprintf(buf, sizeof(buf), "v57 prefs-config tap EXCEPTION %s", why);
        CFLYPrefsLogLine(buf);
        @try {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("点按失败") message:CFLYRuntimeString("这个按钮点下去出错了（已记进日志），先回上一页再试。") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:CFLYRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
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

// v43：記進了哪一頁（PlistPage 繼承這裡，類名是 CFLYPlistPageController，
// 具體哪份 plist 由 specifiers 裡的 plistpage entry 行給出）。
// China Fly 1.0.0：歌詞播放器已拿掉，主頁不再嵌 WKWebView。
- (void)viewDidLoad {
    [super viewDidLoad];
    char buf[160];
    snprintf(buf, sizeof(buf), "v57 prefs-page: %s", [NSStringFromClass([self class]) UTF8String]);
    CFLYPrefsLogLine(buf);
}


// v43：按鈕行自己派發（見上面 CFLYDispatchButtonTap）；其他行走框架。
// v47：plist 名 detail 的連結行先攔下來自己推 PlistPage（見下面
// CFLYHandlePlistDetailTap），不再走框架預設——框架推的原生頁是空的。
// China Fly 1.0.0：菜單編輯行也先攔下來自己推（見 CFLYHandleMenuEditTap）。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (CFLYHandleMenuAddTap(self, tableView, indexPath)) return;
    if (CFLYHandleMenuEditTap(self, tableView, indexPath)) return;
    if (CFLYHandleLinkListTap(self, tableView, indexPath)) return;
    if (CFLYHandlePlistDetailTap(self, tableView, indexPath)) return;
    if (CFLYDispatchButtonTap(self, tableView, indexPath)) return;
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        @try {
            NSMutableArray *loaded = [self loadSpecifiersFromPlistName:CFLYRuntimeString("Root") target:self];
            // v52：新手模式整個取消，不再過濾。
            _specifiers = loaded;
        } @catch (NSException *e) {
            const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
            char buf[512];
            snprintf(buf, sizeof(buf), "v57 prefs-root specifiers EXCEPTION %s", reason);
            CFLYPrefsLogLine(buf);
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:CFLYRuntimeString("主页组装出错（已记进日志），先回设定再试。") forKey:CFLYRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
        if (!_specifiers) _specifiers = [NSMutableArray array];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    NSString *keyName = CFLYRuntimeString("key");
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
    NSString *defaultName = CFLYRuntimeString("default");
    id def = specifier.properties[defaultName];
    if (def) return def;
    return [NSNumber numberWithBool:NO];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    NSString *keyName = CFLYRuntimeString("key");
    NSString *key = specifier.properties[keyName];
    if (key) {
        CFStringRef cfKey = (__bridge CFStringRef)key;
        CFPreferencesSetAppValue(cfKey, (__bridge CFPropertyListRef)value, domain);
        CFPreferencesAppSynchronize(domain);
        // v43：記開關／滑桿／分段改了什麼值（只記用戶改動，不記讀取；
        // readPreferenceValue 每行渲染都跑，記了會刷爆日誌）。
        // ChinaFly 1.0.0：激活码绝不写日志——key 是 activationCode 时跳过这行。
        if (![key isEqualToString:CFLYRuntimeString("activationCode")]) {
            char buf[256];
            const char *keyC = [key UTF8String];
            const char *valC = [[value description] UTF8String];
            snprintf(buf, sizeof(buf), "v57 prefs-set: %s = %s", keyC ? keyC : "?", valC ? valC : "?");
            CFLYPrefsLogLine(buf);
        }
    }
    if (domain) CFRelease(domain);
}

// 彈一個提示框（設定頁裡的回饋）。
- (void)cflyShowAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    NSString *okTitle = CFLYRuntimeString("好");
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
            CFLYPrefsLogLine("v57 prefs-config alert shown");
        } else {
            CFLYPrefsLogLine("v57 prefs-config alert FAILED: no presenter");
        }
    });
}

// v43.8：从 live 的 CFPreferences 现取值建档（备份／导出共用）——
// 设定档 /var/mobile/Library/Preferences/com.chinafly.fly.plist
// 在设定进程里看不到（写入都走 CFPreferencesSetAppValue，档是 cfprefsd
// 管的），旧写法复制档案永远报「没有配置文件可备份」。改成同步后用
// CFPreferencesCopyKeyList 拿全部 key、逐 key 取值组 dict 再写档；
// dict 是空的（0 个 key）才回 NO 且 count=0（没东西可备／可导）。
static BOOL CFLYWriteLivePrefsToFile(NSString *dst, NSUInteger *outCount, unsigned long long *outBytes) {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
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
- (void)cflyShareConfigFile:(NSString *)path title:(NSString *)title what:(NSString *)what restoreRow:(NSString *)restoreRow {
    NSURL *url = [NSURL fileURLWithPath:path];
    if (!url) {
        [self cflyShowAlertWithTitle:title message:CFLYRuntimeString("文件路径不对，分享打不开。")];
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
        [strongSelf cflyShowAlertWithTitle:title message:CFLYRuntimeString(msgBuf)];
    };
    @try {
        [self presentViewController:share animated:YES completion:nil];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v43.10 prefs-config share EXCEPTION %s", reason);
        CFLYPrefsLogLine(buf);
        char msgBuf[768];
        snprintf(msgBuf, sizeof(msgBuf), "分享表打不开，文件在 %s，自己去文件找。", [path UTF8String]);
        [self cflyShowAlertWithTitle:title message:CFLYRuntimeString(msgBuf)];
    }
}

// 備份配置：live 設定現取值寫一份到備份檔（v43.8）。
- (void)cflyBackupConfig:(PSSpecifier *)specifier {
    (void)specifier;
    CFLYPrefsLogLine("v57 prefs-config backup entry");
    NSString *dst = CFLYBackupFilePath();
    NSUInteger count = 0;
    unsigned long long bytes = 0;
    BOOL ok = CFLYWriteLivePrefsToFile(dst, &count, &bytes);
    if (count == 0) {
        CFLYPrefsLogLine("v57 prefs-config backup: no keys in live prefs");
        [self cflyShowAlertWithTitle:CFLYRuntimeString("没有配置文件可备份") message:CFLYRuntimeString("先改一个设置，配置文件才会生成。")];
        return;
    }
    if (ok) {
        char buf[512];
        snprintf(buf, sizeof(buf), "v57 prefs-config backup: wrote %lu keys, %llu bytes to %s", (unsigned long)count, bytes, [dst UTF8String]);
        CFLYPrefsLogLine(buf);
        // v43.10：成功後直接把檔案遞給皇上（分享表），不用自己去文件找。
        [self cflyShareConfigFile:dst title:CFLYRuntimeString("已备份配置") what:CFLYRuntimeString("备份") restoreRow:CFLYRuntimeString("从备份恢复")];
    } else {
        CFLYPrefsLogLine("v57 prefs-config backup: write failed");
        [self cflyShowAlertWithTitle:CFLYRuntimeString("备份失败") message:CFLYRuntimeString("复制配置文件时出错。")];
    }
}
// China Fly 1.0.0：導出／導入已拿掉（新 Root.plist 不再有這兩行）；
// 只留備份／恢復，備份檔是 ChinaFly-backup.plist。
// v43.10：恢復——把字典逐鍵寫進 live prefs（走 CFPreferences，
// cfprefsd 快取才更新；直接換檔看著像沒反應，v43 教訓）。
- (void)cflyApplyConfigDict:(NSDictionary *)dict sourceDescription:(NSString *)src title:(NSString *)title {
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
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
    CFLYPrefsLogLine(buf);
    [self cflyShowAlertWithTitle:title message:CFLYRuntimeString("配置已恢复，请重新启动 SpringBoard 生效。")];
}

// v43.10：文件挑選器——恢復讓皇上自己挑配置文件（想換成別的
// 配置也能用，不只限於原來那一個固定備份檔）。用 initForOpeningContentTypes:
// asCopy:YES（等於舊 Import 模式：系統把挑中的檔拷一份進容器再給我們讀，
// 不用管 security-scoped resource；舊 initWithDocumentTypes:inMode: 在
// iOS 14 起已棄用，-Werror 會直接報錯）。彈不出來就走固定路徑
//（見下面 cflyRestoreConfigFromFixedPath）。
- (void)cflyPresentRestoreDocPicker {
    @try {
        UTType *plistType = [UTType typeWithIdentifier:CFLYRuntimeString("com.apple.property-list")];
        NSArray *types = [NSArray arrayWithObjects:plistType, nil];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v43.10 prefs-config docpicker EXCEPTION %s, fixed-path fallback", reason);
        CFLYPrefsLogLine(buf);
        [self cflyRestoreConfigFromFixedPath];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = ([urls count] > 0) ? [urls objectAtIndex:0] : nil;
    if (!url) {
        CFLYPrefsLogLine("v43.10 prefs-config docpicker: no url");
        return;
    }
    NSString *path = [url path];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!dict) {
        char buf[512];
        snprintf(buf, sizeof(buf), "v43.10 prefs-config docpicker: unreadable %s", [path UTF8String]);
        CFLYPrefsLogLine(buf);
        [self cflyShowAlertWithTitle:CFLYRuntimeString("恢复失败") message:CFLYRuntimeString("挑的配置文件读不出来（要 .plist 配置文件）。")];
        return;
    }
    [self cflyApplyConfigDict:dict sourceDescription:path title:CFLYRuntimeString("已从备份恢复配置")];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    CFLYPrefsLogLine("v43.10 prefs-config docpicker: cancelled");
}

// 從備份文件恢復配置：先彈文件挑選器，讓皇上自己挑配置文件。
// v43：改走 CFPreferences 逐鍵寫入（見上）。
- (void)cflyRestoreConfig:(PSSpecifier *)specifier {
    (void)specifier;
    CFLYPrefsLogLine("v57 prefs-config restore entry");
    [self cflyPresentRestoreDocPicker];
}

// v43.10：挑選器彈不出來時的 fallback——讀固定備份檔 ChinaFly-backup.plist。
- (void)cflyRestoreConfigFromFixedPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *src = CFLYBackupFilePath();
    if (![fm fileExistsAtPath:src]) {
        CFLYPrefsLogLine("v57 prefs-config restore: no backup file");
        [self cflyShowAlertWithTitle:CFLYRuntimeString("没有找到备份文件") message:CFLYRuntimeString("先点「备份配置」，再恢复。")];
        return;
    }
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:src];
    if (!dict) {
        char buf[512];
        snprintf(buf, sizeof(buf), "v57 prefs-config restore: backup file unreadable %s", [src UTF8String]);
        CFLYPrefsLogLine(buf);
        [self cflyShowAlertWithTitle:CFLYRuntimeString("恢复失败") message:CFLYRuntimeString("备份文件读不出来。")];
        return;
    }
    [self cflyApplyConfigDict:dict sourceDescription:src title:CFLYRuntimeString("已从备份恢复配置")];
}

@end
// 開的那份清單的設定頁版，同一份 key、同一份清單，兩邊同步。
// 清單讀後台緩存檔（主插件啟動 5 秒後在後台列舉、寫檔；設定頁
// 只讀緩存，不列舉、不堵主線程）。固定 5 個永遠在最前面；
// 自選 App 的開關 key 是 sel-<bundleID>，串列走 customAppBundleIDs（無上限）。
// v55：選 App 頁每行掛 App 圖標（UIImage 取 App 圖標的私有方法，走運行時拿；
// 拿不到就回 nil、行只顯示名字，不擋列表、不閃退）。圖標按 bundleID 快取，
// 開頁只取一次（清單上百個也不卡）。
@interface UIImage (CFLYAppIconLookup)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end
static NSMutableDictionary *CFLYAppIconCache = nil;
static UIImage *CFLYAppIconForBundleID(NSString *bid) {
    if (!bid || [bid length] == 0) return nil;
    if (!CFLYAppIconCache) CFLYAppIconCache = [NSMutableDictionary dictionary];
    UIImage *cached = CFLYAppIconCache[bid];
    if (cached) return cached;
    UIImage *icon = nil;
    @try {
        icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:0 scale:[UIScreen mainScreen].scale];
        if (!icon) icon = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
    } @catch (NSException *e) {
        icon = nil;
    }
    if (icon) {
        if ([CFLYAppIconCache count] > 300) [CFLYAppIconCache removeAllObjects];
        CFLYAppIconCache[bid] = icon;
    }
    return icon;
}

// ChinaFly 1.0.1: .app 資料夾名當顯示名（去 ".app" 後綴）。
static NSString *CFLYPrefsAppFolderDisplayName(NSString *bundlePath) {
    if (!bundlePath || [bundlePath length] == 0) return nil;
    NSString *last = [bundlePath lastPathComponent];
    if (!last || [last length] == 0) return nil;
    NSString *suffix = CFLYRuntimeString(".app");
    if ([last hasSuffix:suffix]) last = [last substringToIndex:([last length] - [suffix length])];
    if ([last length] == 0) return nil;
    return last;
}

// ChinaFly 1.0.1: 從一個 App 的 bundle 路徑讀顯示名：Info.plist
// CFBundleDisplayName → CFBundleName → .app 資料夾名。
static NSString *CFLYPrefsDisplayNameFromAppBundlePath(NSString *bundlePath) {
    if (!bundlePath || [bundlePath length] == 0) return nil;
    NSString *infoPath = [bundlePath stringByAppendingPathComponent:CFLYRuntimeString("Info.plist")];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSString *name = nil;
    if (info) {
        name = [info objectForKey:CFLYRuntimeString("CFBundleDisplayName")];
        if (!name || ![name isKindOfClass:[NSString class]] || [name length] == 0) name = [info objectForKey:CFLYRuntimeString("CFBundleName")];
    }
    if (!name || ![name isKindOfClass:[NSString class]] || [name length] == 0) name = CFLYPrefsAppFolderDisplayName(bundlePath);
    return name;
}

// ChinaFly 1.0.1: 選擇應用顯示時的名字解析——緩存名字空了就現解：
// LSApplicationWorkspace 找該 bundleID 的 proxy：localizedName →
// Info.plist（bundleURL）CFBundleDisplayName → CFBundleName → .app
// 資料夾名。proxy 完全拿不到才回 nil（workspace 本身叫不到，實際上
// 不會發生；此時整頁的圖標機制也一樣拿不到東西）。
static NSString *CFLYPrefsDisplayNameForBundleID(NSString *bid) {
    if (!bid || [bid length] == 0) return nil;
    NSString *name = nil;
    @try {
        Class wsClass = objc_getClass("LSApplicationWorkspace");
        if (!wsClass) return nil;
        SEL defaultSel = sel_registerName("defaultWorkspace");
        if (!defaultSel || ![wsClass respondsToSelector:defaultSel]) return nil;
        id workspace = ((id (*)(id, SEL))objc_msgSend)((id)wsClass, defaultSel);
        if (!workspace) return nil;
        SEL proxySel = sel_registerName("applicationProxyForIdentifier:");
        if (!proxySel || ![workspace respondsToSelector:proxySel]) return nil;
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(workspace, proxySel, bid);
        if (!proxy) return nil;
        SEL nameSel = sel_registerName("localizedName");
        if (nameSel && [proxy respondsToSelector:nameSel]) name = ((id (*)(id, SEL))objc_msgSend)(proxy, nameSel);
        if (!name || ![name isKindOfClass:[NSString class]] || [name length] == 0) {
            NSString *bundlePath = nil;
            SEL bundleURLSel = sel_registerName("bundleURL");
            if (bundleURLSel && [proxy respondsToSelector:bundleURLSel]) {
                NSURL *bundleURL = ((id (*)(id, SEL))objc_msgSend)(proxy, bundleURLSel);
                if (bundleURL && [bundleURL isKindOfClass:[NSURL class]]) bundlePath = [bundleURL path];
            }
            name = CFLYPrefsDisplayNameFromAppBundlePath(bundlePath);
        }
    } @catch (NSException *e) {
        name = nil;
    }
    if (!name || ![name isKindOfClass:[NSString class]] || [name length] == 0) return nil;
    return name;
}


@interface CFLYAppPickerListController : PSListController <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *cflySearchBar;
@property (nonatomic, strong) NSString *cflySearchText;
@property (nonatomic, assign) BOOL cflySearchBarInstalled;
@end

// China Fly 1.0.4：選擇應用行格子——真圖標＋名字（粗）＋bundle ID 小字。
// 沒圖標的行在組行時就跳過（不顯示白格子），所以這格子一定有圖。
// 開關格子的真類名是 PSSwitchTableCell（PSSwitchCell 只是列舉值），
// 繼承它，開關照樣由系統按 cellType 建出來。
@interface CFLYAppPickerCell : PSSwitchTableCell
@end

@implementation CFLYAppPickerCell {
    UILabel *_apSubtitleLabel;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        _apSubtitleLabel = [[UILabel alloc] init];
        _apSubtitleLabel.font = [UIFont systemFontOfSize:12];
        _apSubtitleLabel.textColor = [UIColor grayColor];
        _apSubtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_apSubtitleLabel];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    NSString *subtitle = specifier.properties[CFLYRuntimeString("subtitle")];
    _apSubtitleLabel.text = subtitle;
    _apSubtitleLabel.hidden = (!subtitle || [subtitle length] == 0);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // 44pt 行高內兩行：主標上收、副標放下面。
    CGRect tf = self.textLabel.frame;
    self.textLabel.frame = CGRectMake(tf.origin.x, 4.0, tf.size.width, 20.0);
    CGFloat w = self.contentView.bounds.size.width;
    _apSubtitleLabel.frame = CGRectMake(tf.origin.x, 24.0, w - tf.origin.x - 70.0, 16.0);
}

@end

@implementation CFLYAppPickerListController


// v43：記進了哪一頁。
- (void)viewDidLoad {
    @try {
        [super viewDidLoad];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-apppicker viewDidLoad EXCEPTION %s", reason);
        CFLYPrefsLogLine(buf);
    }
    CFLYPrefsLogLine("v57 prefs-page: AppPicker");
}

// China Fly 1.0.0：搜索欄掛在表頭（viewDidAppear 才碰 table，
// 只掛一次；搜尋字變了就清快取重組，表頭的搜索欄留著不動）。
- (void)viewDidAppear:(BOOL)animated {
    @try {
        [super viewDidAppear:animated];
    } @catch (NSException *e) {
        CFLYPrefsLogLine("v57 prefs-apppicker: super viewDidAppear EXCEPTION");
    }
    if (self.cflySearchBarInstalled) return;
    UITableView *tv = CFLYSafeTableViewForController(self, "apppicker-search");
    if (!tv) {
        CFLYPrefsLogLine("v57 prefs-apppicker: no table, search bar not mounted");
        return;
    }
    @try {
        UISearchBar *bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, tv.bounds.size.width, 44)];
        bar.delegate = self;
        bar.placeholder = CFLYRuntimeString("搜索");
        bar.showsCancelButton = YES;
        bar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        bar.autocorrectionType = UITextAutocorrectionTypeNo;
        self.cflySearchBar = bar;
        tv.tableHeaderView = bar;
        self.cflySearchBarInstalled = YES;
        CFLYPrefsLogLine("v57 prefs-apppicker: search bar mounted");
    } @catch (NSException *e) {
        CFLYPrefsLogLine("v57 prefs-apppicker: search bar mount EXCEPTION");
    }
}

// 搜索字變了：清快取重組（specifiers 裡按字過濾）；
// 重組後把焦點還給搜索欄，鍵盤不掉。
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchBar;
    BOOL wasFirstResponder = [self.cflySearchBar isFirstResponder];
    self.cflySearchText = searchText;
    _specifiers = nil;
    [self reloadSpecifiers];
    if (wasFirstResponder) [self.cflySearchBar becomeFirstResponder];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = CFLYRuntimeString("");
    self.cflySearchText = nil;
    _specifiers = nil;
    [self reloadSpecifiers];
    [searchBar resignFirstResponder];
}

// v50：按鈕行自己派發（CFLYDispatchButtonTap；框架自己的派發對裸方法名
// 不補冒號，點了沒反應——見 v42.1/v42.2；「重新掃描」按鈕靠這個才動）。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (CFLYDispatchButtonTap(self, tableView, indexPath)) return;
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        @try {
            // China Fly 1.0.0：首次開這頁先把默認開的 8 個播進 prefs。
            CFLYSeedDefaultAppSelection();
            NSMutableArray *specs = [NSMutableArray array];
            // 說明組（1.0.4 換了寫法）。
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            NSString *footerKey = CFLYRuntimeString("footerText");
            [group setProperty:CFLYRuntimeString("打開的 App 會出現在啟動器裡，想開幾個就開幾個。清單是後台列出來的，剛裝好的 App 可能要等一會兒才看得到。") forKey:footerKey];
            [specs addObject:group];
            // 系統應用組頭（1.0.4：只有這一組，固定 5 個跟緩存的一起按名字排）。
            PSSpecifier *section = [PSSpecifier emptyGroupSpecifier];
            [section setProperty:CFLYRuntimeString("系統應用") forKey:CFLYRuntimeString("label")];
            [specs addObject:section];
            // 收集全部 App（固定 5 個＋緩存的），按名字排成一張表。
            NSMutableArray *allApps = [NSMutableArray array];
            for (int i = 0; i < 5; i++) {
                NSString *name = CFLYRuntimeString(CFLYFixedNames[i]);
                NSString *bid = CFLYRuntimeString(CFLYFixedBundleIDs[i]);
                NSString *key = CFLYRuntimeString(CFLYFixedEnabledKeys[i]);
                [allApps addObject:@{CFLYRuntimeString("name"): name, CFLYRuntimeString("bundleID"): bid, CFLYRuntimeString("key"): key, CFLYRuntimeString("default"): [NSNumber numberWithBool:YES]}];
            }
            NSArray *cached = [NSArray arrayWithContentsOfFile:CFLYAppCacheFilePath()];
            if (cached) {
                for (id item in cached) {
                    if (![item isKindOfClass:[NSDictionary class]]) continue;
                    NSString *bidStr = item[CFLYRuntimeString("bundleID")];
                    NSString *nameStr = item[CFLYRuntimeString("name")];
                    if (!bidStr || [bidStr length] == 0) continue;
                    const char *bid = [bidStr UTF8String];
                    if (CFLYFixedIndexForBundleID(bid) >= 0) continue;
                    // ChinaFly 1.0.1: 絕不顯示光禿禿的 bundleID——緩存名字空了就
                    // 顯示時現解（同一條退路鏈：本地化名 → Info.plist 顯示名 →
                    // CFBundleName → 資料夾名）。
                    NSString *label = (nameStr && [nameStr length] > 0) ? nameStr : CFLYPrefsDisplayNameForBundleID(bidStr);
                    if (!label || [label length] == 0) label = bidStr;
                    NSString *selKey = [CFLYRuntimeString("sel-") stringByAppendingString:bidStr];
                    [allApps addObject:@{CFLYRuntimeString("name"): label, CFLYRuntimeString("bundleID"): bidStr, CFLYRuntimeString("key"): selKey, CFLYRuntimeString("default"): [NSNumber numberWithBool:NO]}];
                }
            }
            NSArray *sorted = [allApps sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                NSString *na = a[CFLYRuntimeString("name")];
                NSString *nb = b[CFLYRuntimeString("name")];
                return [na localizedCompare:nb];
            }];
            BOOL anyRow = NO;
            for (NSDictionary *app in sorted) {
                NSString *bidStr = app[CFLYRuntimeString("bundleID")];
                NSString *label = app[CFLYRuntimeString("name")];
                // 1.0.4：沒有真圖標的不顯示（不留白格子）。
                UIImage *icon = CFLYAppIconForBundleID(bidStr);
                if (!icon) continue;
                anyRow = YES;
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
                [spec setProperty:app[CFLYRuntimeString("key")] forKey:CFLYRuntimeString("key")];
                [spec setProperty:CFLYRuntimeString("com.chinafly.fly") forKey:CFLYRuntimeString("defaults")];
                [spec setProperty:app[CFLYRuntimeString("default")] forKey:CFLYRuntimeString("default")];
                [spec setProperty:bidStr forKey:CFLYRuntimeString("subtitle")];
                [spec setProperty:NSStringFromClass([CFLYAppPickerCell class]) forKey:CFLYRuntimeString("cellClass")];
                [spec setProperty:icon forKey:CFLYRuntimeString("iconImage")];
                [specs addObject:spec];
            }
            if (!anyRow) {
                PSSpecifier *emptyGroup = [PSSpecifier emptyGroupSpecifier];
                [emptyGroup setProperty:CFLYRuntimeString("還沒有 App 清單，後台正在列出，晚點再開這頁看看。") forKey:CFLYRuntimeString("footerText")];
                [specs addObject:emptyGroup];
            }
            // China Fly 1.0.0：搜索過濾——有搜尋字時只留說明組
            // 和名字裡有搜尋字的 App 開關行。
            if (self.cflySearchText && [self.cflySearchText length] > 0) {
                NSMutableArray *filtered = [NSMutableArray array];
                for (PSSpecifier *sp in specs) {
                    if (sp.cellType != PSSwitchCell) {
                        [filtered addObject:sp];
                        continue;
                    }
                    NSString *label = sp.name;
                    if (label && [label rangeOfString:self.cflySearchText options:NSCaseInsensitiveSearch].location != NSNotFound) {
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
            CFLYPrefsLogLine(buf);
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:CFLYRuntimeString("选择器页组装出错（已记进日志），先回上一页再试。") forKey:CFLYRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
        if (!_specifiers) _specifiers = [NSMutableArray array];
    }
    return _specifiers;
}


- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[CFLYRuntimeString("key")];
    if (!key) return [NSNumber numberWithBool:NO];
    NSString *selPrefix = CFLYRuntimeString("sel-");
    if ([key hasPrefix:selPrefix]) {
        NSString *bidStr = [key substringFromIndex:[selPrefix length]];
        return [NSNumber numberWithBool:CFLYAppInLauncher([bidStr UTF8String])];
    }
    // 固定 App：讀 prefs，沒設回 plist 的 default（開）。
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
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
    NSString *defaultName = CFLYRuntimeString("default");
    id def = specifier.properties[defaultName];
    if (def) return def;
    return [NSNumber numberWithBool:NO];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[CFLYRuntimeString("key")];
    if (!key) return;
    BOOL on = [value boolValue];
    NSString *selPrefix = CFLYRuntimeString("sel-");
    if ([key hasPrefix:selPrefix]) {
        NSString *bidStr = [key substringFromIndex:[selPrefix length]];
        CFLYSetAppInLauncherPrefs([bidStr UTF8String], on);
        // v43.24：第 6 件——自選 App 無上限，不再彈「已滿」提示。
        char buf[320];
        snprintf(buf, sizeof(buf), "v57 prefs-set: sel %s = %d", [bidStr UTF8String], on ? 1 : 0);
        CFLYPrefsLogLine(buf);
        [self reloadSpecifiers];
        return;
    }
    // 固定 App：直接寫開關。
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
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
    CFLYPrefsLogLine(buf);
}

@end


// ── China Fly 1.0.0 動態頁 ──
// 下面 6 個控制器都是 prefs bundle 裡的自訂類（prefs bundle 不受
// dylib「禁自訂 ObjC 類」那條限；主插件 Tweak.xm 裡還是只能用
// Apple 類＋CFLYLauncher 一個自訂類）。

// China Fly 1.0.0：菜單編輯頁——「當前列表」可拖動排序。
// UITableViewController 子類（不用 PSListController：這頁是純列表＋
// 拖動重排，編輯模式的 reorder control 就夠了）。讀／寫 prefs 鍵
// menuAppOrder（有序字串陣列：知道 bundleID 的存 bundleID，
// 不知道的存顯示名，運行時按名找——見 CFLYResolveMenuEntry）。
// 右上角「編輯」按鈕進編輯模式，拖動右邊的手柄重排，鬆手即存。
@interface CFLYMenuEditListController : UITableViewController
@property (nonatomic, strong) NSMutableArray *cflyMenuItems;
@end

@implementation CFLYMenuEditListController

- (void)viewDidLoad {
    [super viewDidLoad];
    CFLYPrefsLogLine("cf prefs-page: MenuEdit");
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.cflyMenuItems = CFLYReadMenuOrder();
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 44)];
    footer.text = CFLYRuntimeString("点击更换图标，编辑拖动排序或左滑删除。");
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
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return (NSInteger)[self.cflyMenuItems count];
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        NSString *addId = CFLYRuntimeString("CFLYMenuEditAddCell");
        UITableViewCell *addCell = [tableView dequeueReusableCellWithIdentifier:addId];
        if (!addCell) {
            addCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:addId];
        }
        addCell.textLabel.text = CFLYRuntimeString("添加 URL Scheme");
        addCell.textLabel.textColor = [UIColor systemBlueColor];
        addCell.imageView.image = [UIImage systemImageNamed:CFLYRuntimeString("plus.circle")];
        addCell.imageView.tintColor = [UIColor systemBlueColor];
        addCell.accessoryType = UITableViewCellAccessoryNone;
        return addCell;
    }
    NSString *reuseId = CFLYRuntimeString("CFLYMenuEditCell");
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseId];
    }
    NSString *entry = nil;
    if (indexPath.row >= 0 && indexPath.row < (NSInteger)[self.cflyMenuItems count]) entry = [self.cflyMenuItems objectAtIndex:(NSUInteger)indexPath.row];
    NSString *bid = nil;
    NSString *name = nil;
    CFLYResolveMenuEntry(entry, &bid, &name);
    cell.textLabel.text = name;
    // 副標：bundle ID（沒有 bundle ID 的自訂項就顯示原來的 entry）。
    cell.detailTextLabel.text = (bid && [bid length] > 0) ? bid : entry;
    cell.detailTextLabel.textColor = [UIColor grayColor];
    cell.imageView.image = nil;
    // 自訂圖標（menuIcon_<entry> 存 SF Symbol 名）優先，沒有就用 App 真圖標。
    UIImage *customIcon = nil;
    if (entry && [entry length] > 0) {
        NSString *iconKey = [CFLYRuntimeString("menuIcon_") stringByAppendingString:entry];
        CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
        if (domain) {
            CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)iconKey, domain);
            if (v) {
                // ChinaFly 1.0.5：menuIcon_<entry> 必須是字串才轉——值若不是
                // NSString（plist 被手改／舊寫入殘留），直接轉型後調 length
                // 會 unrecognized selector 閃退；非字串就放掉、不當圖標用。
                if ([(__bridge id)v isKindOfClass:[NSString class]]) {
                    NSString *symName = (__bridge_transfer NSString *)v;
                    if ([symName length] > 0) customIcon = [UIImage systemImageNamed:symName];
                } else {
                    CFRelease(v);
                }
            }
            CFRelease(domain);
        }
    }
    if (customIcon) {
        cell.imageView.image = customIcon;
        cell.imageView.tintColor = [UIColor systemBlueColor];
    } else if (bid) {
        UIImage *icon = CFLYAppIconForBundleID(bid);
        if (icon) cell.imageView.image = icon;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return YES;
}

// 1.0.4：紅色減號刪除（左滑或編輯模式點減號都刪）。
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 1) return UITableViewCellEditingStyleNone;
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.section != 0) return;
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)[self.cflyMenuItems count]) return;
    NSString *removed = [self.cflyMenuItems objectAtIndex:(NSUInteger)indexPath.row];
    [self.cflyMenuItems removeObjectAtIndex:(NSUInteger)indexPath.row];
    CFLYWriteMenuOrder(self.cflyMenuItems);
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    char buf[256];
    snprintf(buf, sizeof(buf), "cf prefs-menuedit: deleted row %ld (%s)", (long)indexPath.row, removed ? [removed UTF8String] : "?");
    CFLYPrefsLogLine(buf);
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == 0;
}

// ChinaFly 1.0.5：閃退主因——本頁有 2 個 section（0＝菜單項、1＝「添加
// URL Scheme」單行），但之前沒有 targetIndexPathForMove。拖一行從
// section 0 往 section 1 拖時，UITableView 以為它跨了 section，
// 卻調 moveRowAtIndexPath:toIndexPath:——那裡只在扁平陣列裡挪，
// 各 section 的行數不變，UITableView 數出來的行數對不上，就拋
// NSInternalInconsistencyException、設定直接閃退（編輯模式拖排序
// 往下拖到底就會中；日誌只記「進頁」，不記崩潰，所以 7b1267da.log
// 裡 12 次進頁都沒看到崩潰行）。修：拖放目標一律夾回 section 0，
// 跨 section 的目標直接拒收；moveRow 那邊再加一道 section 守門。
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedIndexPath {
    (void)tableView;
    (void)sourceIndexPath;
    if (proposedIndexPath.section != 0) {
        NSInteger last = (NSInteger)[self.cflyMenuItems count] - 1;
        if (last < 0) last = 0;
        return [NSIndexPath indexPathForRow:last inSection:0];
    }
    return proposedIndexPath;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
    (void)tableView;
    if (fromIndexPath.section != 0 || toIndexPath.section != 0) return;
    NSInteger from = fromIndexPath.row;
    NSInteger to = toIndexPath.row;
    if (from == to) return;
    if (from < 0 || from >= (NSInteger)[self.cflyMenuItems count]) return;
    if (to < 0 || to >= (NSInteger)[self.cflyMenuItems count]) return;
    NSString *moved = [self.cflyMenuItems objectAtIndex:(NSUInteger)from];
    [self.cflyMenuItems removeObjectAtIndex:(NSUInteger)from];
    [self.cflyMenuItems insertObject:moved atIndex:(NSUInteger)to];
    CFLYWriteMenuOrder(self.cflyMenuItems);
    char buf[256];
    snprintf(buf, sizeof(buf), "cf prefs-menuedit: moved row %ld to %ld", (long)from, (long)to);
    CFLYPrefsLogLine(buf);
}

// 點一行：添加 URL Scheme 那行就彈輸入框；App 行就彈更換圖標。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self cflyMenuEditAddURLScheme];
        return;
    }
    if (self.editing) return;
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)[self.cflyMenuItems count]) return;
    NSString *entry = [self.cflyMenuItems objectAtIndex:(NSUInteger)indexPath.row];
    [self cflyMenuEditChangeIconForEntry:entry];
}

// 添加 URL Scheme：輸一個 URL Scheme 或 Bundle ID，加進當前列表。
- (void)cflyMenuEditAddURLScheme {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("添加 URL Scheme") message:CFLYRuntimeString("输入一个 URL Scheme 或 Bundle ID，例如 weixin:// 或 com.tencent.xin。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = CFLYRuntimeString("weixin:// 或 com.tencent.xin");
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    UIAlertAction *add = [UIAlertAction actionWithTitle:CFLYRuntimeString("添加") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        NSString *value = alert.textFields.firstObject.text;
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!value || [value length] == 0) return;
        [self.cflyMenuItems addObject:value];
        CFLYWriteMenuOrder(self.cflyMenuItems);
        [self.tableView reloadData];
        char buf[256];
        snprintf(buf, sizeof(buf), "cf prefs-menuedit: added URL scheme %s", [value UTF8String]);
        CFLYPrefsLogLine(buf);
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:CFLYRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:add];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
}

// 更換圖標：輸一個 SF Symbol 名（例如 star.fill），存到 menuIcon_<entry>。
- (void)cflyMenuEditChangeIconForEntry:(NSString *)entry {
    if (!entry || [entry length] == 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("更換圖標") message:CFLYRuntimeString("输入一个 SF Symbol 名，例如 star.fill。留空就恢复 App 原图标。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = CFLYRuntimeString("SF Symbol 名，例如 star.fill");
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    UIAlertAction *save = [UIAlertAction actionWithTitle:CFLYRuntimeString("保存") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        NSString *value = alert.textFields.firstObject.text;
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *iconKey = [CFLYRuntimeString("menuIcon_") stringByAppendingString:entry];
        CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
        if (domain) {
            if (value && [value length] > 0) {
                CFPreferencesSetAppValue((__bridge CFStringRef)iconKey, (__bridge CFPropertyListRef)value, domain);
            } else {
                CFPreferencesSetAppValue((__bridge CFStringRef)iconKey, NULL, domain);
            }
            CFPreferencesAppSynchronize(domain);
            CFRelease(domain);
        }
        [self.tableView reloadData];
        CFLYPrefsLogLine("cf prefs-menuedit: icon changed");
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:CFLYRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:save];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// ── China Fly 1.0.4：菜單編輯點加入列表（47 項）──
// dylib 的 CFLYMenuItems 是另一支二進制，這裡要自己有一份同順序、
// 同名字的表（中性 key、繁體中文名、英文顯示名、SF Symbol）。
// 全屏翻譯（第 48 項）不列；4 個巨魔智能體已取消，不在表裡。
typedef struct { const char *identifier; const char *label; const char *labelEn; const char *symbol; } CFLYMenuAddItemDef;
static const CFLYMenuAddItemDef CFLYMenuAddItems[47] = {
{"spotlight", "聚焦搜尋", "Spotlight Search", "magnifyingglass"},
{"console", "查看日誌", "View Logs", "terminal"},
{"screenRecord", "螢幕錄影", "Screen Recording", "record.circle"},
{"screenRecordMic", "有聲錄影", "Recording with Mic", "mic.fill"},
{"silent", "靜音切換", "Silent Toggle", "bell.slash"},
{"respring", "重啟桌面", "Restart SpringBoard", "arrow.counterclockwise"},
{"reboot", "重新開機", "Reboot Device", "power"},
{"orientation", "鎖定方向", "Orientation Lock", "lock.rotation"},
{"appearance", "日夜切換", "Light / Dark", "moon.circle"},
{"announce", "Siri 語音播報", "Announce Notifications", "megaphone"},
{"bluetooth", "藍牙開關", "Bluetooth", "bluetooth"},
{"wifi", "Wi-Fi 開關", "Wi-Fi", "wifi"},
{"vpn", "VPN 開關", "VPN", "lock.shield"},
{"cellular", "行動數據開關", "Cellular Data", "antenna.radiowaves.left.and.right"},
{"trueTone", "原彩開關", "True Tone", "sun.max"},
{"airplane", "飛航開關", "Airplane Mode", "airplane"},
{"hotspot", "個人熱點開關", "Personal Hotspot", "personalhotspot"},
{"lowPower", "省電開關", "Low Power Mode", "battery.25"},
{"flashlight", "手電筒開關", "Flashlight", "flashlight.on.fill"},
{"nightShift", "夜覽開關", "Night Shift", "moon.fill"},
{"smartInvert", "智慧反色開關", "Smart Invert", "circle.lefthalf.filled"},
{"lock", "鎖定螢幕", "Lock Screen", "lock.fill"},
{"siri", "開啟 Siri", "Open Siri", "mic.fill"},
{"volumeDown", "調低音量", "Volume Down", "speaker.wave.1.fill"},
{"volumeUp", "調高音量", "Volume Up", "speaker.wave.3.fill"},
{"appLibrary", "打開 App 資源庫", "App Library", "square.grid.3x3.fill"},
{"appSwitcher", "打開多工切換", "App Switcher", "square.stack.3d.up.fill"},
{"voiceControl", "語音操控", "Voice Control", "waveform"},
{"controlCenter", "打開控制中心", "Control Center", "switch.2"},
{"liveSpeech", "即時語音", "Live Speech", "person.wave.2"},
{"mute", "靜音開關", "Mute", "speaker.slash.fill"},
{"nearbyDevices", "控制附近裝置", "Nearby Devices", "airplayaudio"},
{"notificationCenter", "打開通知中心", "Notification Center", "bell.fill"},
{"watchRemote", "Watch 遠端螢幕", "Watch Remote Screen", "applewatch"},
{"quickNote", "快速備忘錄", "Quick Note", "note.text"},
{"dock", "顯示 Dock", "Show Dock", "dock.rectangle"},
{"location", "定位開關", "Location Services", "location.fill"},
{"screenshot", "螢幕截圖", "Screenshot", "camera.viewfinder"},
{"screenshotEdit", "截圖並編輯", "Screenshot & Edit", "square.and.pencil"},
{"autoBrightness", "自動亮度開關", "Auto-Brightness", "sun.max.fill"},
{"dnd", "勿擾開關", "Do Not Disturb", "moon.zzz.fill"},
{"screenshotCopy", "截圖複製", "Copy Screenshot", "doc.on.clipboard"},
{"screenshotRegion", "選取區域截圖", "Screenshot Region", "crop"},
{"floatForeground", "把前景變浮窗", "Float Foreground App", "rectangle.on.rectangle"},
{"singleWindow", "只留一個浮窗", "Single Window Mode", "rectangle"},
{"minimizeAll", "收起全部浮窗", "Minimize All", "chevron.down"},
{"closeAll", "關掉全部浮窗", "Close All Windows", "xmark.circle"},
};

// 藍底圓角方塊＋白 SF Symbol（影片裡菜單編輯頁那種圖標），28pt。
// 符號拿不到（名字錯了）就回 nil，行裡不畫圖。
static UIImage *CFLYMenuAddIconForSymbol(const char *symbol) {
    if (!symbol || symbol[0] == '\0') return nil;
    UIImage *sym = [UIImage systemImageNamed:[NSString stringWithCString:symbol encoding:NSUTF8StringEncoding]];
    if (!sym || !sym.CGImage) return nil;
    CGFloat s = 28.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0.0);
    UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s, s) cornerRadius:6.0];
    [[UIColor systemBlueColor] setFill];
    [bg fill];
    CGFloat inset = 5.0;
    CGRect r = CGRectMake(inset, inset, s - inset * 2, s - inset * 2);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 0, s);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGRect fr = CGRectMake(r.origin.x, s - r.origin.y - r.size.height, r.size.width, r.size.height);
        CGContextClipToMask(ctx, fr, sym.CGImage);
        [[UIColor whiteColor] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, s, s));
        CGContextRestoreGState(ctx);
    }
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

// 菜單編輯點加入行的格子：藍方塊圖標＋中文名（粗）＋英文小字＋打勾（已加入）。
@interface CFLYMenuAddCell : PSTableCell
@end

@implementation CFLYMenuAddCell {
    UIImageView *_maIconView;
    UILabel *_maTitleLabel;
    UILabel *_maSubtitleLabel;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        _maIconView = [[UIImageView alloc] init];
        _maIconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_maIconView];
        _maTitleLabel = [[UILabel alloc] init];
        _maTitleLabel.font = [UIFont boldSystemFontOfSize:16];
        _maTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_maTitleLabel];
        _maSubtitleLabel = [[UILabel alloc] init];
        _maSubtitleLabel.font = [UIFont systemFontOfSize:13];
        _maSubtitleLabel.textColor = [UIColor grayColor];
        _maSubtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_maSubtitleLabel];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.textLabel.text = nil;
    self.textLabel.hidden = YES;
    self.detailTextLabel.text = nil;
    self.detailTextLabel.hidden = YES;
    NSString *title = specifier.properties[CFLYRuntimeString("label")];
    _maTitleLabel.text = title;
    NSString *subtitle = specifier.properties[CFLYRuntimeString("subtitle")];
    _maSubtitleLabel.text = subtitle;
    _maSubtitleLabel.hidden = (!subtitle || [subtitle length] == 0);
    UIImage *icon = specifier.properties[CFLYRuntimeString("iconImage")];
    _maIconView.image = icon;
    _maIconView.hidden = (icon == nil);
    NSNumber *checked = specifier.properties[CFLYRuntimeString("menuChecked")];
    self.accessoryType = (checked && [checked boolValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat x = 16.0;
    if (_maIconView.image) {
        _maIconView.frame = CGRectMake(x, (h - 28.0) / 2.0, 28.0, 28.0);
        x += 28.0 + 12.0;
    }
    CGFloat textW = w - x - 16.0;
    if (_maSubtitleLabel.hidden) {
        _maTitleLabel.frame = CGRectMake(x, 0, textW, h);
    } else {
        _maTitleLabel.frame = CGRectMake(x, 6.0, textW, 22.0);
        _maSubtitleLabel.frame = CGRectMake(x, 28.0, textW, 18.0);
    }
}

@end

// 菜單編輯點加入列表：47 項，點一下就加入／移出表盤菜單（打勾＝已加入）。
// 右上角「編輯」推當前列表頁（拖動排序／刪除）。
@interface CFLYMenuAddListController : PSListController
@end

@implementation CFLYMenuAddListController

- (void)viewDidLoad {
    [super viewDidLoad];
    CFLYPrefsLogLine("cf prefs-page: MenuAdd");
    UIBarButtonItem *editBtn = [[UIBarButtonItem alloc] initWithTitle:CFLYRuntimeString("編輯") style:UIBarButtonItemStylePlain target:self action:@selector(cflyMenuAddOpenCurrentList)];
    self.navigationItem.rightBarButtonItem = editBtn;
}

- (void)cflyMenuAddOpenCurrentList {
    CFLYMenuEditListController *page = [[CFLYMenuEditListController alloc] initWithStyle:UITableViewStyleGrouped];
    page.title = CFLYRuntimeString("當前列表");
    UINavigationController *nav = self.navigationController;
    if (nav) {
        [nav pushViewController:page animated:YES];
        CFLYPrefsLogLine("cf prefs-menuadd push current list");
    }
}

// 讀某一項在不在表盤菜單裡（menuToggle_<identifier>，預設開）。
- (BOOL)cflyMenuAddIsEnabled:(const char *)identifier {
    if (!identifier || identifier[0] == '\0') return NO;
    char key[96];
    snprintf(key, sizeof(key), "menuToggle_%s", identifier);
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    BOOL v = YES;
    if (domain) {
        CFPropertyListRef val = CFPreferencesCopyAppValue((__bridge CFStringRef)[NSString stringWithCString:key encoding:NSUTF8StringEncoding], domain);
        if (val) {
            if (CFGetTypeID(val) == CFBooleanGetTypeID()) v = CFBooleanGetValue((CFBooleanRef)val);
            CFRelease(val);
        }
        CFRelease(domain);
    }
    return v;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        @try {
            NSMutableArray *specs = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:CFLYRuntimeString("點一下即可加入列表。") forKey:CFLYRuntimeString("footerText")];
            [specs addObject:group];
            PSSpecifier *section = [PSSpecifier emptyGroupSpecifier];
            [section setProperty:CFLYRuntimeString("可添加工具") forKey:CFLYRuntimeString("label")];
            [specs addObject:section];
            for (int i = 0; i < 47; i++) {
                const CFLYMenuAddItemDef *def = &CFLYMenuAddItems[i];
                NSString *label = [NSString stringWithCString:def->label encoding:NSUTF8StringEncoding];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
                [spec setProperty:CFLYRuntimeString(def->labelEn) forKey:CFLYRuntimeString("subtitle")];
                [spec setProperty:[NSString stringWithCString:def->identifier encoding:NSUTF8StringEncoding] forKey:CFLYRuntimeString("menuIdentifier")];
                [spec setProperty:CFLYRuntimeString("cflyMenuAddToggle:") forKey:CFLYRuntimeString("action")];
                [spec setProperty:[NSNumber numberWithBool:[self cflyMenuAddIsEnabled:def->identifier]] forKey:CFLYRuntimeString("menuChecked")];
                [spec setProperty:NSStringFromClass([CFLYMenuAddCell class]) forKey:CFLYRuntimeString("cellClass")];
                UIImage *icon = CFLYMenuAddIconForSymbol(def->symbol);
                if (icon) [spec setProperty:icon forKey:CFLYRuntimeString("iconImage")];
                [specs addObject:spec];
            }
            _specifiers = specs;
        } @catch (NSException *e) {
            const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
            char buf[512];
            snprintf(buf, sizeof(buf), "v57 prefs-menuadd specifiers EXCEPTION %s", reason);
            CFLYPrefsLogLine(buf);
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:CFLYRuntimeString("菜單編輯頁組裝出錯（已記進日志），先回上一頁再試。") forKey:CFLYRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
        if (!_specifiers) _specifiers = [NSMutableArray array];
    }
    return _specifiers;
}

// 點一下：加入／移出表盤菜單（寫 menuToggle_<identifier>），打勾即時跟著變。
- (void)cflyMenuAddToggle:(PSSpecifier *)specifier {
    NSString *ident = specifier.properties[CFLYRuntimeString("menuIdentifier")];
    if (!ident || [ident length] == 0) return;
    const char *identC = [ident UTF8String];
    BOOL cur = [self cflyMenuAddIsEnabled:identC];
    BOOL next = !cur;
    char key[96];
    snprintf(key, sizeof(key), "menuToggle_%s", identC);
    CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
    if (domain) {
        CFPreferencesSetAppValue((__bridge CFStringRef)[NSString stringWithCString:key encoding:NSUTF8StringEncoding], next ? kCFBooleanTrue : kCFBooleanFalse, domain);
        CFPreferencesAppSynchronize(domain);
        CFRelease(domain);
    }
    CFStringRef noteName = CFLYRuntimeCFString("com.chinafly.fly.prefschanged");
    if (noteName) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), noteName, NULL, NULL, true);
        CFRelease(noteName);
    }
    char buf[128];
    snprintf(buf, sizeof(buf), "cf prefs-menuadd toggle %s %s", identC, next ? "on" : "off");
    CFLYPrefsLogLine(buf);
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (CFLYDispatchButtonTap(self, tableView, indexPath)) return;
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

@end


// v42：「查看日誌」——設定 App 裡直接看分屏日誌：最新在最上面
//（讀尾段，預設最後 200 行）、能刷新、能清空（檔案截斷；寫不動就
// 誠實報失敗，不假裝能清）、能分享（系統分享表單）。
@interface CFLYLogViewerListController : PSListController
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, assign) BOOL headerInstalled;
@end

@implementation CFLYLogViewerListController

// v43：按鈕行自己派發（CFLYDispatchButtonTap）；其他行走框架。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (CFLYDispatchButtonTap(self, tableView, indexPath)) return;
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

// v50：重做——viewDidLoad 只建 UITextView（讀檔防呆在
// CFLYLogTailNewestFirst 裡），不再碰 table；掛載移到 viewDidAppear
//（只掛一次，安全取表＋try/catch），掛不上就只記日誌、頁面照常可用
//（三個按鈕＋分享都還在）。
- (void)viewDidLoad {
    @try {
        [super viewDidLoad];
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-log: super viewDidLoad EXCEPTION %s", why);
        CFLYPrefsLogLine(buf);
    }
    CFLYPrefsLogLine("v57 prefs-page: LogViewer");
    @try {
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 420)];
        tv.font = [UIFont systemFontOfSize:11];
        tv.editable = NO;
        tv.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        tv.text = CFLYLogTailNewestFirst();
        self.logView = tv;
        char buf[128];
        snprintf(buf, sizeof(buf), "v57 prefs-log: read %d lines", CFLYLogTailLinesRead);
        CFLYPrefsLogLine(buf);
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-log: build text view EXCEPTION %s", why);
        CFLYPrefsLogLine(buf);
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
        CFLYPrefsLogLine(buf);
    }
    if (self.logView && !self.headerInstalled) {
        UITableView *tv = CFLYSafeTableViewForController(self, "log");
        if (tv) {
            @try {
                tv.tableHeaderView = self.logView;
                self.headerInstalled = YES;
                CFLYPrefsLogLine("v57 prefs-log: header mounted");
            } @catch (NSException *e) {
                const char *why = [e reason] ? [[e reason] UTF8String] : "?";
                char buf[256];
                snprintf(buf, sizeof(buf), "v57 prefs-log: mount EXCEPTION %s", why);
                CFLYPrefsLogLine(buf);
            }
        } else {
            CFLYPrefsLogLine("v57 prefs-log: no table, header not mounted");
        }
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        @try {
            NSMutableArray *specs = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:CFLYRuntimeString("由新到舊排列，僅顯示最近 200 行。清空是把檔案截斷，新的日誌會繼續寫進來。") forKey:CFLYRuntimeString("footerText")];
            [specs addObject:group];
            NSArray *buttons = [NSArray arrayWithObjects:CFLYRuntimeString("刷新"), CFLYRuntimeString("清空"), CFLYRuntimeString("分享"), nil];
            NSArray *actions = [NSArray arrayWithObjects:CFLYRuntimeString("cflyLogRefresh"), CFLYRuntimeString("cflyLogClear"), CFLYRuntimeString("cflyLogShare"), nil];
            for (NSUInteger i = 0; i < [buttons count]; i++) {
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:[buttons objectAtIndex:i] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
                [spec setProperty:[actions objectAtIndex:i] forKey:CFLYRuntimeString("action")];
                [specs addObject:spec];
            }
            _specifiers = specs;
        } @catch (NSException *e) {
            const char *why = [e reason] ? [[e reason] UTF8String] : "?";
            char buf[256];
            snprintf(buf, sizeof(buf), "v57 prefs-log: specifiers EXCEPTION %s", why);
            CFLYPrefsLogLine(buf);
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:CFLYRuntimeString("日志页组装出错（已记进日志），先回上一页再试。") forKey:CFLYRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
    }
    return _specifiers;
}

- (void)cflyLogRefresh:(PSSpecifier *)specifier {
    (void)specifier;
    @try {
        if (self.logView) self.logView.text = CFLYLogTailNewestFirst();
    } @catch (NSException *e) {
        CFLYPrefsLogLine("v57 prefs-log: refresh EXCEPTION");
    }
}

- (void)cflyLogClear:(PSSpecifier *)specifier {
    (void)specifier;
    NSError *err = nil;
    BOOL ok = [[NSData data] writeToFile:CFLYLogFilePath() options:NSDataWritingAtomic error:&err];
    if (ok) {
        if (self.logView) self.logView.text = CFLYLogTailNewestFirst();
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("日志已清空") message:CFLYRuntimeString("日志档案已截断，新的日志会继续写进来。") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:CFLYRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("清空失败") message:CFLYRuntimeString("日志档案写不动（权限问题），请用 Filza 手动清。") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:CFLYRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)cflyLogShare:(PSSpecifier *)specifier {
    (void)specifier;
    NSURL *url = [NSURL fileURLWithPath:CFLYLogFilePath()];
    if (!url) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:[NSArray arrayWithObject:url] applicationActivities:nil];
    [self presentViewController:share animated:YES completion:nil];
}

@end



// v53：悬浮图标——相冊選圖（PHPicker）、居中裁方形 512、
// 存設定目錄固定檔名、寫 flyTriggerIconCustom 鍵；恢復默認刪檔＋清鍵，
// 觸發鈕 2 秒內回默認圖（dylib tick 重讀）。照卡片頭像控制器樣式。
@interface CFLYFlyTriggerIconListController : PSListController <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIImageView *previewView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, assign) BOOL headerInstalled;
@end

@implementation CFLYFlyTriggerIconListController

// v43：按鈕行自己派發（CFLYDispatchButtonTap）；其他行走框架。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (CFLYDispatchButtonTap(self, tableView, indexPath)) return;
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
        CFLYPrefsLogLine(buf);
    }
    CFLYPrefsLogLine("v57 prefs-page: FlyTriggerIcon");
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
        [self cflyRefreshFlyTriggerPreview];
    } @catch (NSException *e) {
        const char *why = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-flyTriggericon: viewDidLoad EXCEPTION %s", why);
        CFLYPrefsLogLine(buf);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    @try {
        [super viewDidAppear:animated];
    } @catch (NSException *e) {
        CFLYPrefsLogLine("v57 prefs-flyTriggericon: super viewDidAppear EXCEPTION");
    }
    if (self.headerView && !self.headerInstalled) {
        UITableView *tv = CFLYSafeTableViewForController(self, "flyTriggericon");
        if (tv) {
            @try {
                tv.tableHeaderView = self.headerView;
                self.headerInstalled = YES;
                CFLYPrefsLogLine("v57 prefs-flyTriggericon: header mounted");
            } @catch (NSException *e) {
                const char *why = [e reason] ? [[e reason] UTF8String] : "?";
                char buf[256];
                snprintf(buf, sizeof(buf), "v57 prefs-flyTriggericon: mount EXCEPTION %s", why);
                CFLYPrefsLogLine(buf);
            }
        } else {
            CFLYPrefsLogLine("v57 prefs-flyTriggericon: no table, header not mounted");
        }
    }
}

- (void)cflyRefreshFlyTriggerPreview {
    @try {
        UIImage *img = [UIImage imageWithContentsOfFile:CFLYFlyTriggerIconPath()];
        if (!img) {
            // China Fly 1.0.0：沒有自訂圖就顯示代碼畫的紙飛機
            //（不要引用已刪的哆啦A夢 png）。
            img = CFLYPaperPlaneImage(120.0);
        }
        self.previewView.image = img;
    } @catch (NSException *e) {
        CFLYPrefsLogLine("v57 prefs-flyTriggericon: refresh EXCEPTION");
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        [group setProperty:CFLYRuntimeString("上面那张圆图是现在的触发钮图，默认是纸飞机；从相册选一张、居中裁成方形存起来，触发钮 2 秒内就换成它。") forKey:CFLYRuntimeString("footerText")];
        [specs addObject:group];
        PSSpecifier *pick = [PSSpecifier preferenceSpecifierNamed:CFLYRuntimeString("从相册选图（换钮图片）") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [pick setProperty:CFLYRuntimeString("cflyPickFlyTriggerIcon") forKey:CFLYRuntimeString("action")];
        [specs addObject:pick];
        PSSpecifier *restore = [PSSpecifier preferenceSpecifierNamed:CFLYRuntimeString("恢复默认触发钮图") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [restore setProperty:CFLYRuntimeString("cflyRestoreFlyTriggerIcon") forKey:CFLYRuntimeString("action")];
        [specs addObject:restore];
        _specifiers = specs;
    }
    return _specifiers;
}

- (void)cflyPickFlyTriggerIcon:(PSSpecifier *)specifier {
    (void)specifier;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter imagesFilter];
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)cflyRestoreFlyTriggerIcon:(PSSpecifier *)specifier {
    (void)specifier;
    [[NSFileManager defaultManager] removeItemAtPath:CFLYFlyTriggerIconPath() error:nil];
    CFLYWritePrefsBool("flyTriggerIconCustom", NO);
    [self cflyRefreshFlyTriggerPreview];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("已恢复默认触发钮图") message:CFLYRuntimeString("触发钮回到默认图。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CFLYRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
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
            UIImage *square = CFLYPrefsSquareCropImage(picked, 512.0);
            if (!square) return;
            NSData *data = UIImageJPEGRepresentation(square, 0.85);
            BOOL ok = data && [data writeToFile:CFLYFlyTriggerIconPath() atomically:YES];
            if (ok) {
                CFLYWritePrefsBool("flyTriggerIconCustom", YES);
                [self cflyRefreshFlyTriggerPreview];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("钮图片已换好") message:CFLYRuntimeString("触发钮 2 秒内就换成这张。") preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:CFLYRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("保存钮图片失败") message:CFLYRuntimeString("图片写不进设定目录。") preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:CFLYRuntimeString("好") style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

@end


// （CFLYPlistPageController 在文件後面定義，這裡先給完整接口聲明——
// 光是 @class 前向聲明不夠，[CFLYPlistPageController class] 會報錯。）
@interface CFLYPlistPageController : ChinaFlyRootListController
@end

// v72：LinkList 子清單控制器（見下面 CFLYHandleLinkListTap）——
// 框架原生的 PSListItemsController 在鍵盤頁上只顯示一個選項（子清單幾乎空白，
// plist 本身是對的、父頁也載了 7 項，框架子清單的生成／快取／渲染在這裡
// 黑盒修不了；同 v47 的做法：點按攔下來、推我們自己的控制器）。
// 它從點按那行的 specifier 現場讀 values／titles 建單選行，不走框架快取；
// 選項寫值走繼承的 setPreferenceValue（CFPreferences＋同步），並記
// v72 prefs-linklist 日誌，下次日誌能證明寫入。
@interface CFLYLinkListController : ChinaFlyRootListController
@end

// China Fly 1.0.0：子頁要跳的 plist 白名單（9 份真實檔案；不在裡面的
// 名字一律不載，免得 loadSpecifiersFromPlistName 拿到壞名字）。
// 舊頁（ARC、ARCButtons、Floating、Window、Shadow、Scheduler、Banner、
// GestureCustom、Keyboard、Info、Status、Other）已刪，不在白名單裡，
// 點了也不會載。Activation 是 1.0.0 新加的激活頁（照舊分屏 1.0.103
// 那套，碼表是 China Fly 自己的 codes-fly.json（1.0.2 起不再跟舊分屏共用）。
static BOOL CFLYPrefsIsKnownPlistName(const char *name) {
    if (!name || name[0] == '\0') return NO;
    static const char *known[] = {"ActionButtonLongPress", "ActionButtonTap", "Activation", "Dial", "Root", "SplitSettings", "Trigger"};
    size_t n = sizeof(known) / sizeof(known[0]);
    for (size_t i = 0; i < n; i++) {
        if (strcmp(name, known[i]) == 0) return YES;
    }
    return NO;
}


// China Fly 1.0.0：攔截 detail=CFLYMenuEditListController 的連結行，
// 自己推菜單編輯頁。CFLYMenuEditListController 是 UITableViewController
// 子類（不是 PSListController），框架預設的推頁路徑是照 PSListController
// 做的，直接交給框架會推不動；這裡用 navigationController 直推。
// 回傳 YES 表示這一行已經處理了（呼叫方直接 return，不要再走 super）。
static BOOL CFLYHandleMenuEditTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    if (!controller || !indexPath) return NO;
    PSSpecifier *spec = [controller specifierAtIndexPath:indexPath];
    if (!spec) return NO;
    if (spec.cellType != PSLinkCell) return NO;
    NSString *detail = spec.properties[CFLYRuntimeString("detail")];
    if (!detail || ![detail isEqualToString:CFLYRuntimeString("CFLYMenuEditListController")]) return NO;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CFLYMenuEditListController *page = [[CFLYMenuEditListController alloc] initWithStyle:UITableViewStyleGrouped];
    NSString *label = spec.name;
    page.title = (label && [label length] > 0) ? label : CFLYRuntimeString("當前列表");
    UINavigationController *nav = controller.navigationController;
    if (nav) {
        [nav pushViewController:page animated:YES];
        CFLYPrefsLogLine("cf prefs-menuedit push");
    } else {
        CFLYPrefsLogLine("cf prefs-menuedit push FAILED: no navigationController");
    }
    return YES;
}

// China Fly 1.0.4：攔截 detail=CFLYMenuAddListController 的連結行，
// 自己推菜單編輯點加入頁。CFLYMenuAddListController 是 PSListController
// 子類（動態組行），框架預設的推頁路徑推不動；這裡用 navigationController 直推。
// 回傳 YES 表示這一行已經處理了（呼叫方直接 return，不要再走 super）。
static BOOL CFLYHandleMenuAddTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    if (!controller || !indexPath) return NO;
    PSSpecifier *spec = [controller specifierAtIndexPath:indexPath];
    if (!spec) return NO;
    if (spec.cellType != PSLinkCell) return NO;
    NSString *detail = spec.properties[CFLYRuntimeString("detail")];
    if (!detail || ![detail isEqualToString:CFLYRuntimeString("CFLYMenuAddListController")]) return NO;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CFLYMenuAddListController *page = [[CFLYMenuAddListController alloc] init];
    NSString *label = spec.name;
    page.title = (label && [label length] > 0) ? label : CFLYRuntimeString("編輯菜單");
    UINavigationController *nav = controller.navigationController;
    if (nav) {
        [nav pushViewController:page animated:YES];
        CFLYPrefsLogLine("cf prefs-menuadd push");
    } else {
        CFLYPrefsLogLine("cf prefs-menuadd push FAILED: no navigationController");
    }
    return YES;
}

// v72：攔截 PSLinkListCell 的點按，自己推 CFLYLinkListController。
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
static BOOL CFLYHandleLinkListTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    if (!controller || !indexPath) return NO;
    PSSpecifier *spec = [controller specifierAtIndexPath:indexPath];
    if (!spec) return NO;
    if (spec.cellType != PSLinkListCell) return NO;
    NSArray *values = spec.properties[CFLYRuntimeString("values")];
    NSArray *titles = spec.properties[CFLYRuntimeString("titles")];
    // v43.11：plist 載入的 LinkList 行用 validValues／validTitles，沒有 values 屬性
    //（鍵盤彈出方式那些行就是這麼漏網的——30.log 6 次 no values）。
    //讀不到才改讀 validValues／validTitles，讀到就推我們自己的頁。
    if (!values || [values count] == 0) {
        values = spec.properties[CFLYRuntimeString("validValues")];
        titles = spec.properties[CFLYRuntimeString("validTitles")];
    }
    if (!values || [values count] == 0) {
        CFLYPrefsLogLine("v72 prefs-linklist no values, framework fallback");
        return NO;
    }
    (void)titles;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CFLYLinkListController *page = [[CFLYLinkListController alloc] init];
    page.specifier = spec;
    page.parentController = controller;
    page.rootController = controller.rootController;
    [controller pushController:page];
    NSString *key = spec.properties[CFLYRuntimeString("key")];
    const char *keyC = key ? [key UTF8String] : "?";
    char buf[256];
    snprintf(buf, sizeof(buf), "v72 prefs-linklist push %s options %lu", keyC, (unsigned long)[values count]);
    CFLYPrefsLogLine(buf);
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
// 手動推一個 CFLYPlistPageController：把 plist 名寫進 specifier 的非保留字鍵
// cflyTargetPlist，再 push。PlistPage 的 specifiers 是在我們自己的
// 子類身上載 plist（bundle 對得上），內容就出來了。detail 是類名、
// 或不在白名單裡的，一律回 NO 交回框架／super，不動它。
// PlistPage 繼承主頁控制器（同一個 didSelectRow），所以子頁裡的嵌套
// plist 連結（浮窗設置裡的陰影／橫幅／鍵盤／調度、其他雜項裡的
// 桌面圖標／懸浮圖標、ARC／高級設置裡的調度／手勢自定義）走同
// 一個攔截，一次全修；類名 detail 的嵌套行（排序頁、加入 App、
// 日誌／頭像／背景）繼續走框架，本來就正常。
// 回傳 YES 表示這一行已經處理了（呼叫方直接 return，不要再走 super）。
static BOOL CFLYHandlePlistDetailTap(PSListController *controller, UITableView *tableView, NSIndexPath *indexPath) {
    if (!controller || !indexPath) return NO;
    PSSpecifier *spec = [controller specifierAtIndexPath:indexPath];
    if (!spec) return NO;
    if (spec.cellType != PSLinkCell) return NO;
    NSString *detail = spec.properties[CFLYRuntimeString("detail")];
    if (!detail || [detail length] == 0) return NO;
    const char *detailC = [detail UTF8String];
    // 類名 detail——框架直接 alloc 那個類，本來就正常，不攔。
    if (NSClassFromString(detail) != Nil) return NO;
    if (!CFLYPrefsIsKnownPlistName(detailC)) {
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-nav REJECTED unknown plist detail %s", detailC ? detailC : "?");
        CFLYPrefsLogLine(buf);
        return NO;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [spec setProperty:detail forKey:CFLYRuntimeString("cflyTargetPlist")];
    CFLYPlistPageController *page = [[CFLYPlistPageController alloc] init];
    page.specifier = spec;
    page.parentController = controller;
    page.rootController = controller.rootController;
    [controller pushController:page];
    char buf[256];
    snprintf(buf, sizeof(buf), "v57 prefs-nav push plist %s", detailC ? detailC : "?");
    CFLYPrefsLogLine(buf);
    return YES;
}

// v42：任意 plist 頁——搜索結果點進來的頁：按 specifier 上的
// plistName 載入那份 plist。繼承主頁控制器，所以備份／導出／
// 導入／恢復／布局預設那些按鈕動作在這裡也一樣能用。
// （接口聲明在文件前面搜索控制器之前，這裡只寫實作。）
// v43：改讀 cflyTargetPlist（非保留字 key），先對白名單才載，
// 載入失敗只顯示空白頁、不閃退；進出寫檔日誌。
@implementation CFLYPlistPageController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *targetPlist = self.specifier.properties[CFLYRuntimeString("cflyTargetPlist")];
        if (!targetPlist || [targetPlist length] == 0) {
            // v43.19：重進設定恢復出來的頁，specifier 是新的，cflyTargetPlist
            // 那個運行期寫進去的鍵沒了；退回讀 detail（行裡本來就寫著 plist 名）。
            targetPlist = self.specifier.properties[CFLYRuntimeString("detail")];
        }
        const char *cname = targetPlist ? [targetPlist UTF8String] : NULL;
        char buf[256];
        snprintf(buf, sizeof(buf), "v57 prefs-search plistpage entry plist %s", cname ? cname : "(nil)");
        CFLYPrefsLogLine(buf);
        if (targetPlist && [targetPlist length] > 0 && CFLYPrefsIsKnownPlistName(cname)) {
            @try {
                _specifiers = [self loadSpecifiersFromPlistName:targetPlist target:self];
            } @catch (NSException *e) {
                char ebuf[512];
                snprintf(ebuf, sizeof(ebuf), "v57 prefs-search plistpage EXCEPTION %s %s", [[e name] UTF8String], [[e reason] UTF8String]);
                CFLYPrefsLogLine(ebuf);
                NSMutableArray *safe = [NSMutableArray array];
                PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
                [group setProperty:CFLYRuntimeString("这一页打不开（已记进日志），先回上一页再试。") forKey:CFLYRuntimeString("footerText")];
                [safe addObject:group];
                _specifiers = safe;
            }
            if (!_specifiers) _specifiers = [NSMutableArray array];
        } else {
            CFLYPrefsLogLine("v57 prefs-search plistpage REJECTED unknown plist");
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:CFLYRuntimeString("这一页打不开（已记进日志），先回上一页再试。") forKey:CFLYRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
        // China Fly 1.0.0：Keyboard.plist 已刪，鍵盤過濾整段拿掉。
        // v43.32：觸發方式下面三套按方式動態換行——ARC 只留 ARC 兩行
        //（arcStartAngle／arcFanAngle），邊緣只留邊緣那套（觸發側／
        // 滑幾次／左／右×豎／橫屏各三根滑桿），懸浮條只留懸浮條兩行
        //（floatingBarY／floatingBarSize）；調試開關和觸發方式行本身
        // 三套通用，一直留著。行和組頭都帶 cflyTriggerSet 標記
        //（arc／edge／bar），沒標記的都留。模式變了回這一頁時
        // viewWillAppear 已清快取重組（v71），讀到的就是新值。
        if (targetPlist && [targetPlist isEqualToString:CFLYRuntimeString("Trigger")]) {
            char *tmode = CFLYPrefsCString("triggerMode");
            const char *want = "edge";
            if (tmode) {
                if (strcmp(tmode, "arc") == 0) want = "arc";
                else if (strcmp(tmode, "bar") == 0) want = "bar";
                free(tmode);
            }
            NSMutableArray *kept = [NSMutableArray array];
            for (PSSpecifier *sp in _specifiers) {
                NSString *setTag = sp.properties[CFLYRuntimeString("cflyTriggerSet")];
                if (setTag && strcmp([setTag UTF8String], want) != 0) continue;
                [kept addObject:sp];
            }
            _specifiers = kept;
        }
        char buf2[128];
        snprintf(buf2, sizeof(buf2), "v57 prefs-search plistpage exit count %lu", (unsigned long)[_specifiers count]);
        CFLYPrefsLogLine(buf2);
        // v71：頁面載入時記一行 plist 名＋item 數量——下次日誌直接證明
        // 載的是新版還是舊版（1.0.70 兩行看不到，靠這行定位）。
        {
            char pbuf[256];
            snprintf(pbuf, sizeof(pbuf), "v71 prefs-page %s items %lu", cname ? cname : "(nil)", (unsigned long)[_specifiers count]);
            CFLYPrefsLogLine(pbuf);
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
        CFLYPrefsLogLine(buf);
    }
}

@end

@implementation CFLYLinkListController

// v72：LinkList 子清單——從點按那行（self.specifier）的 values／titles 現場建單選行。
// 每個選項一行 PSListItemCell（單選圓點行），values 只有那一個值；
// 當前值由繼承的 readPreferenceValue 讀（沒存過回 plist 的 default），框架照它打勾。
- (NSArray *)specifiers {
    if (!_specifiers) {
        PSSpecifier *parent = self.specifier;
        NSArray *values = parent ? parent.properties[CFLYRuntimeString("values")] : nil;
        NSArray *titles = parent ? parent.properties[CFLYRuntimeString("titles")] : nil;
        // v43.11：跟攔截一樣，values／titles 讀不到改讀 validValues／validTitles
        //（plist 行就是這個名字；建出來的選項行照舊只寫 values，寫值路只讀 values）。
        if (!values || [values count] == 0) {
            values = parent ? parent.properties[CFLYRuntimeString("validValues")] : nil;
            titles = parent ? parent.properties[CFLYRuntimeString("validTitles")] : nil;
        }
        NSString *key = parent ? parent.properties[CFLYRuntimeString("key")] : nil;
        NSString *defaults = parent ? parent.properties[CFLYRuntimeString("defaults")] : nil;
        id def = parent ? parent.properties[CFLYRuntimeString("default")] : nil;
        NSMutableArray *specs = [NSMutableArray array];
        if (values && [values count] > 0 && key) {
            for (NSUInteger i = 0; i < [values count]; i++) {
                id value = [values objectAtIndex:i];
                NSString *title = nil;
                if (titles && i < [titles count]) title = [titles objectAtIndex:i];
                if (!title) title = [value description];
                PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSListItemCell edit:nil];
                [spec setProperty:[NSArray arrayWithObject:value] forKey:CFLYRuntimeString("values")];
                [spec setProperty:key forKey:CFLYRuntimeString("key")];
                if (defaults) [spec setProperty:defaults forKey:CFLYRuntimeString("defaults")];
                if (def) [spec setProperty:def forKey:CFLYRuntimeString("default")];
                [specs addObject:spec];
            }
            const char *keyC = [key UTF8String];
            char buf[256];
            snprintf(buf, sizeof(buf), "v72 prefs-linklist %s options %lu", keyC ? keyC : "?", (unsigned long)[values count]);
            CFLYPrefsLogLine(buf);
        } else {
            // values 讀不到——不推空白頁，顯示一行說明（下次日誌能看到）。
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:CFLYRuntimeString("选项读不到，先回上一页再试。") forKey:CFLYRuntimeString("footerText")];
            [specs addObject:group];
            CFLYPrefsLogLine("v72 prefs-linklist no values at build");
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
        CFLYPrefsLogLine(buf);
    }
}

// v72：LinkList 選項寫值記一行（框架原生的 PSListItemsController 寫值走它
// 自己的控制器，繞過我們有記日誌的 setPreferenceValue——這就是 24.log 裡
// exitAnimation／launcherStyle／keyboardPopupMode 一行 prefs-set 都沒有的原因）。
// 這裡先記 v72 prefs-linklist，再調繼承的 setPreferenceValue 真正寫入
//（CFPreferencesSetAppValue＋AppSynchronize，跟開關／滑桿同一條路）。
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[CFLYRuntimeString("key")];
    const char *keyC = key ? [key UTF8String] : "?";
    const char *valC = value ? [[value description] UTF8String] : "?";
    char buf[256];
    snprintf(buf, sizeof(buf), "v72 prefs-linklist %s = %s", keyC, valC);
    CFLYPrefsLogLine(buf);
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
        NSArray *values = spec.properties[CFLYRuntimeString("values")];
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

// China Fly 1.0.0：狀態頁（CFLYStatusListController）與鍵盤助手標記
//（CFLYKbHelperMarkersText）已整段拿掉。激活頁（下面兩類）是 1.0.0
// 新加的（皇上 21:34 定，照舊分屏 1.0.103 那套；碼表是 China Fly 自己的
// codes-fly.json（1.0.2 起不再跟舊分屏共用），實現、鍵、通知名全用 China Fly 自己的）。
// 除了碼表是自己的，China Fly 別的什麼都不碰舊分屏（皇上 21:36 定）。

@interface CFLYActivationRowCell : PSTableCell
@end

@implementation CFLYActivationRowCell {
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
    NSString *title = specifier.properties[CFLYRuntimeString("label")];
    _actTitleLabel.text = title;
    NSString *subtitle = specifier.properties[CFLYRuntimeString("subtitle")];
    _actSubtitleLabel.text = subtitle;
    _actSubtitleLabel.hidden = (!subtitle || [subtitle length] == 0);
    NSString *iconName = specifier.properties[CFLYRuntimeString("iconName")];
    UIImage *icon = nil;
    if (iconName && [iconName length] > 0) icon = [UIImage systemImageNamed:iconName];
    _actIconView.image = icon;
    _actIconView.hidden = (icon == nil);
    NSString *value = specifier.properties[CFLYRuntimeString("valueText")];
    _actValueLabel.text = value;
    _actValueLabel.hidden = (!value || [value length] == 0);
    BOOL hasAction = (specifier.properties[CFLYRuntimeString("action")] != nil);
    if (hasAction) {
        _actChevronView.image = [UIImage systemImageNamed:CFLYRuntimeString("chevron.right")];
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
// CFLYPrefsActivationStatusText。值行在 -specifiers 里现填，viewWillAppear 重载。
@interface CFLYActivationListController : ChinaFlyRootListController
@end

@implementation CFLYActivationListController

- (void)viewDidLoad {
    @try {
        [super viewDidLoad];
    } @catch (NSException *e) {
        const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
        char buf[256];
        snprintf(buf, sizeof(buf), "ChinaFly prefs-activation viewDidLoad EXCEPTION %s", reason);
        CFLYPrefsLogLine(buf);
    }
    CFLYPrefsLogLine("ChinaFly prefs-page: Activation");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    char buf[160];
    snprintf(buf, sizeof(buf), "ChinaFly prefs-activation tap: section %ld row %ld", (long)indexPath.section, (long)indexPath.row);
    CFLYPrefsLogLine(buf);
    if (CFLYHandlePlistDetailTap(self, tableView, indexPath)) return;
    if (CFLYDispatchButtonTap(self, tableView, indexPath)) return;
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
            NSMutableArray *loaded = [self loadSpecifiersFromPlistName:CFLYRuntimeString("Activation") target:self];
            for (PSSpecifier *spec in loaded) {
                NSString *vk = spec.properties[CFLYRuntimeString("valueKey")];
                if (![vk isKindOfClass:[NSString class]]) continue;
                if ([vk isEqualToString:CFLYRuntimeString("activationState")]) {
                    [spec setProperty:CFLYPrefsActivationStatusText() forKey:CFLYRuntimeString("valueText")];
                } else if ([vk isEqualToString:CFLYRuntimeString("systemVersion")]) {
                    NSString *ver = [[UIDevice currentDevice] systemVersion];
                    NSString *txt = [CFLYRuntimeString("iOS ") stringByAppendingString:(ver ? ver : CFLYRuntimeString("?"))];
                    [spec setProperty:txt forKey:CFLYRuntimeString("valueText")];
                } else if ([vk isEqualToString:CFLYRuntimeString("pluginVersion")]) {
                    [spec setProperty:CFLYRuntimeString("1.0.5") forKey:CFLYRuntimeString("valueText")];
                }
            }
            // ChinaFly 1.0.1: 舊分屏開著時，第一組（激活授权）下方顯示休眠提示；
            // 1.0.3 改成開關開著 AND 舊 dylib 文件還在才提示（跟 dylib 同條件）。
            // specifiers 每次進頁都重建（viewWillAppear 會 reloadSpecifiers），
            // 所以重進頁面就重新判斷。舊包刪了、只剩殘留 prefs 時提示不再出現。
            if (CFLYPrefsShouldDormantForOldSplitscreen()) {
                for (PSSpecifier *spec in loaded) {
                    if (spec.cellType == PSGroupCell) {
                        [spec setProperty:CFLYRuntimeString("舊分屏開著，China Fly 休眠中") forKey:CFLYRuntimeString("footerText")];
                        break;
                    }
                }
            }
            _specifiers = loaded;
        } @catch (NSException *e) {
            const char *reason = [e reason] ? [[e reason] UTF8String] : "?";
            char buf[512];
            snprintf(buf, sizeof(buf), "ChinaFly prefs-activation specifiers EXCEPTION %s", reason);
            CFLYPrefsLogLine(buf);
            NSMutableArray *safe = [NSMutableArray array];
            PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
            [group setProperty:CFLYRuntimeString("激活页打不开（已记进日志），先回上一页再试。") forKey:CFLYRuntimeString("footerText")];
            [safe addObject:group];
            _specifiers = safe;
        }
        if (!_specifiers) _specifiers = [NSMutableArray array];
    }
    return _specifiers;
}

// 提示框改走最上层 presenter、主队列（同 cflyShowAlertWithTitle
// 的做法；本页的输入框／操作表不能走那个只带「好」的 helper）。
- (void)cflyActivationPresent:(UIAlertController *)alert {
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
            CFLYPrefsLogLine("ChinaFly prefs-activation present FAILED: no presenter");
        }
    });
}

// 发 Darwin 通知给 dylib 重抓名单对码，4 秒后重载本页（状态行自己翻成
// 「您的设备已授权」／「未授权」，不用退出重进）。
- (void)cflyActivationPostRecheck {
    notify_post("com.chinafly.fly.activationRecheck");
    CFLYPrefsLogLine("ChinaFly prefs-activation recheck posted");
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf reloadSpecifiers];
    });
}

// 上卡第 1 行：弹输入框输激活码，确认就写 prefs＋发检查（码不记日志）。
- (void)cflyActivationEnterCode:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("激活正版授权") message:CFLYRuntimeString("输入激活码来绑定当前的设备。") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = CFLYRuntimeString("激活码，如 SD-XXXX-XXXX-XXXX");
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:CFLYRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    __weak UIAlertController *weakAlert = alert;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:CFLYRuntimeString("确认") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        UIAlertController *strongAlert = weakAlert;
        NSString *raw = strongAlert ? strongAlert.textFields.firstObject.text : nil;
        NSString *code = [[raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
        if (!code || [code length] == 0) {
            [self cflyShowAlertWithTitle:CFLYRuntimeString("请输入激活码") message:CFLYRuntimeString("激活码是空的，先输入再确认。")];
            return;
        }
        CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
        if (domain) {
            CFStringRef cfKey = CFLYRuntimeCFString("activationCode");
            if (cfKey) {
                CFPreferencesSetAppValue(cfKey, (__bridge CFPropertyListRef)code, domain);
                CFRelease(cfKey);
            }
            CFPreferencesAppSynchronize(domain);
            CFRelease(domain);
        }
        [self cflyActivationPostRecheck];
        [self cflyShowAlertWithTitle:CFLYRuntimeString("已发送检查") message:CFLYRuntimeString("已发送检查，稍等几秒再看「当前授权状态」，通过了会显示「您的设备已授权」。")];
    }];
    [alert addAction:cancel];
    [alert addAction:ok];
    [self cflyActivationPresent:alert];
}

// 上卡第 2 行：没有在线购买页，去 Telegram 频道找 Lee 要码。
- (void)cflyActivationSponsor:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("赞助购买授权") message:CFLYRuntimeString("没有在线购买页，去 Telegram 频道找 Lee 要激活码。") preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:CFLYRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *open = [UIAlertAction actionWithTitle:CFLYRuntimeString("打开频道") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [self cflyActivationOpenTelegramChannel];
    }];
    [alert addAction:cancel];
    [alert addAction:open];
    [self cflyActivationPresent:alert];
}

// 设置页进程里 openURL 不可靠，先顺手试 tg:// 深链，
// 不管成不成都复制 https 邀请链接＋弹「已复制」，保证链接一定到手。
- (void)cflyActivationOpenTelegramChannel {
    NSURL *tgURL = [NSURL URLWithString:CFLYRuntimeString("tg://join?invite=UaeIYedetWtiZGQ1")];
    if (tgURL) {
        [[UIApplication sharedApplication] openURL:tgURL options:[NSDictionary dictionary] completionHandler:^(BOOL success) {
            (void)success;
            dispatch_async(dispatch_get_main_queue(), ^{
                CFLYPrefsLogLine("ChinaFly prefs-activation telegram tg attempted");
            });
        }];
    }
    [UIPasteboard generalPasteboard].string = CFLYRuntimeString("https://t.me/+UaeIYedetWtiZGQ1");
    CFLYPrefsLogLine("ChinaFly prefs-activation telegram copied");
    [self cflyShowAlertWithTitle:CFLYRuntimeString("已复制") message:CFLYRuntimeString("Telegram 频道链接已复制到剪贴板，去 Telegram 贴上进群找 Lee 要码。")];
}

// 上卡第 3 行：清除已保存的激活码、重新检查。
- (void)cflyActivationManage:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("管理配置授权") message:CFLYRuntimeString("重置配置，授权找回等操作。") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *clear = [UIAlertAction actionWithTitle:CFLYRuntimeString("清除已保存的激活码") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action;
        CFStringRef domain = CFLYRuntimeCFString("com.chinafly.fly");
        if (domain) {
            CFStringRef cfKey = CFLYRuntimeCFString("activationCode");
            if (cfKey) {
                CFPreferencesSetAppValue(cfKey, NULL, domain);
                CFRelease(cfKey);
            }
            CFPreferencesAppSynchronize(domain);
            CFRelease(domain);
        }
        [self cflyActivationPostRecheck];
        [self cflyShowAlertWithTitle:CFLYRuntimeString("已清除") message:CFLYRuntimeString("已保存的激活码已清除（1.0.5 起无需激活码，仍可正常使用）。")];
    }];
    UIAlertAction *recheck = [UIAlertAction actionWithTitle:CFLYRuntimeString("重新检查激活码") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [self cflyActivationPostRecheck];
        [self cflyShowAlertWithTitle:CFLYRuntimeString("已发送检查") message:CFLYRuntimeString("已发送检查，稍等几秒再看「当前授权状态」。")];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:CFLYRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    [sheet addAction:clear];
    [sheet addAction:recheck];
    [sheet addAction:cancel];
    [self cflyActivationPresent:sheet];
}

// 下卡：加入官方群组——Telegram 频道。（1.0.4：舊 QQ 群已删，
// 那是顧海龍抖音的群，跟 China Fly 無關。）
- (void)cflyActivationJoinGroup:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:CFLYRuntimeString("加入官方群组") message:CFLYRuntimeString("选择加入官方交流群") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *tg = [UIAlertAction actionWithTitle:CFLYRuntimeString("Telegram 频道") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [self cflyActivationOpenTelegramChannel];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:CFLYRuntimeString("取消") style:UIAlertActionStyleCancel handler:nil];
    [sheet addAction:tg];
    [sheet addAction:cancel];
    [self cflyActivationPresent:sheet];
}

@end
