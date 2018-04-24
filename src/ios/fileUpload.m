/********* fileUpload.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import <AFNetworking/AFNetworking.h>

// 4 * 1024KB
const uint block = 1024 * 1024 * 4;
// 1kb
// const uint block = 1024 * 100;

typedef void (^ProcessBlock)(int64_t, int64_t);

@interface fileUpload : CDVPlugin {
    // Member variables go here.
}

- (void)upload:(CDVInvokedUrlCommand*)command;
@end

@implementation fileUpload

- (void)upload:(CDVInvokedUrlCommand*)command {
//    CDVPluginResult* pluginResult = nil;

    // 判断路径是否包含file:// 并且去掉
    NSString *path = [command.arguments objectAtIndex:0];
    if ([path hasPrefix:@"file://"]) {
        path = [path stringByReplacingOccurrencesOfString:@"file://" withString:@""];
    }
    NSLog(@"path -> %@", path);
    // 获取参数，服务器URL
    NSString *serverURL = [command.arguments objectAtIndex:1];
    // 服务器接收名
    NSString *fileKey = [command argumentAtIndex:2 withDefault:@"file"];
    // 获取文件名
    NSString *fileName = [command argumentAtIndex:3 withDefault:@"test.mp4"];
    // 获取mime类型
    NSString *mimeType = [command argumentAtIndex:4 withDefault:@"video/mp4"];
    // 获得参数
    NSDictionary *options = [command argumentAtIndex:5 withDefault:[NSDictionary dictionary]];
    // 获得请求头设置
    NSDictionary *headers = [command argumentAtIndex:6 withDefault:[NSDictionary dictionary]];

    // 获取视频
    NSData* videoData = [[NSData alloc] initWithContentsOfFile:path];

    // 获取字节长度
    NSUInteger totalLength = [videoData length];

    // 根据最小字节，获得切分次数
    NSUInteger count = totalLength / block + (totalLength % block ? 1 : 0);

    NSLog(@"totalLength: %lu - count: %lu", (unsigned long)totalLength, (unsigned long)count);

    // 分割视频, 将最后一次去掉. 记录分割区间
    NSMutableArray *rangeArray = [[NSMutableArray alloc] initWithCapacity:count];
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:count];
    for (int i = 0; i < count - 1; i++) {
        NSRange range = NSMakeRange(i * (block), block);
        NSData *d = [videoData subdataWithRange:range];
        [array addObject:d];
        [rangeArray addObject:[NSString stringWithFormat:@"%u-%u", i * (block), block + i * (block) - 1]];
    }
    // 处理最后一次分割
    NSUInteger lastLength = totalLength - (count - 1) * block;
    NSData *d = [videoData subdataWithRange:NSMakeRange((count - 1) * block, lastLength)];
    [array addObject:d];
    [rangeArray addObject:[NSString stringWithFormat:@"%lu-%lu", (count - 1) * block, totalLength-1]];

    __block dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_group_async(dispatch_group_create(), dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL), ^ {
        __block int64_t receive = 0;

        for (int i = 0; i < array.count; i++) {

            NSData *current = array[i];
            AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
            // 设置头信息
            [self requestHeaders:headers serializer:manager];

            NSString *range = [[NSString alloc] initWithFormat:@"%@%@/%lu", @"bytes ", rangeArray[i], (unsigned long)totalLength];
            NSLog(@"rang => %@", range);
            [manager.requestSerializer setValue:range forHTTPHeaderField:@"Content-Range"];

            manager.responseSerializer = [AFHTTPResponseSerializer serializer];
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:options.count];
            for (NSString *key in options) {
                id val = [options objectForKey:key];
                if (!val || (val == [NSNull null])) {
                    continue;
                }
                if (![val isKindOfClass:[NSString class]]) {
                    continue;
                }
                [dictionary setObject:[val dataUsingEncoding:NSUTF8StringEncoding] forKey:key];
            }
            // TODO 测试 最后删除
            [dictionary setValue:@(i) forKey:@"tmpId"];

            [manager POST:serverURL parameters:dictionary constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
                [formData appendPartWithFileData:current name:fileKey fileName:fileName mimeType:mimeType];
            } progress:^(NSProgress * _Nonnull uploadProgress) {

                NSUInteger unitCount = 1.0 * (receive + uploadProgress.completedUnitCount);
                float progress = (1.0 * unitCount) / (1.0 * totalLength);
//                NSLog(@"progress => %.2lf", progress);
                if (uploadProgress.completedUnitCount == uploadProgress.totalUnitCount) {
                    receive = receive + uploadProgress.totalUnitCount;
                }

                NSMutableDictionary* uploadProgressDic = [NSMutableDictionary dictionaryWithCapacity:3];
                [uploadProgressDic setObject:[NSNumber numberWithBool:true] forKey:@"lengthComputable"];
                [uploadProgressDic setObject:[NSNumber numberWithLongLong: progress] forKey:@"loaded"];
                [uploadProgressDic setObject:[NSNumber numberWithLongLong: totalLength] forKey:@"total"];
                CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:uploadProgressDic];
                [result setKeepCallbackAsBool:true];
                [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];

            } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
                NSData *data = responseObject;

                NSError *error = nil;
                NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                NSString *msg = responseDict[@"msg"];
                if ([msg isEqualToString:@"success"]) {
                    NSUInteger currentReceive = [responseDict[@"received"] longLongValue];
                    NSLog(@"%lu", (unsigned long)currentReceive);
                    if (i == (array.count - 1)) {
                        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"success"];
                        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    }
                } else {
                    NSLog(@"msg => %@", msg);
                }
                dispatch_semaphore_signal(semaphore);
            } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
                // TODO 失败重新发送
                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

                dispatch_semaphore_signal(semaphore);
            }];
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);


//            [self upload:array andIndex:i andHeader:headers andOptions:options andServerURL:serverURL andFileKey:fileKey andFileName:fileName andMimeType:mimeType andBlock:^void (int64_t completedUnitCount, int64_t totalUnitCount) {
//            } andSemaphore:semaphore];
        }
    });

//    if (path != nil && [path length] > 0) {
//        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:path];
//    } else {
//        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
//    }
//
//    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}
/** 分割并计算上次成功接收字节数，计算下次起始点
-(NSData*) calculateFile:(NSData*) videoData andIndex:(int) index andTotalLength:(NSUInteger) totalLength andReceived:(NSUInteger) receive {

    NSUInteger residueLength = totalLength - receive;
    if (residueLength <= 0) {
        return nil;
    }
    NSUInteger count = residueLength / block + (residueLength % block ? 1 : 0);

    // 分割视频, 将最后一次去掉
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:count];
    for (int i = 0; i < count - 1; i++) {
        NSRange range = NSMakeRange(i * (block) + receive, block);
        NSData *d = [videoData subdataWithRange:range];
        [array addObject:d];
    }
    // 处理最后一次分割
    NSUInteger lastLength = totalLength - (count - 1) * block;
    NSData *d = [videoData subdataWithRange:NSMakeRange((count -1) * block, lastLength)];
    [array addObject:d];

    NSLog(@"totalLength: %lu - residueLength: %lu - count: %lu", (unsigned long)totalLength, (unsigned long)residueLength, (unsigned long)count);
    return array.firstObject;
}

-(void) upload:(NSMutableArray* ) array andIndex:(int) i
     andHeader:(NSDictionary*) headers andOptions:(NSDictionary*) options andServerURL:(NSString*) serverURL andFileKey:(NSString*) fileKey andFileName:(NSString*) fileName andMimeType:(NSString*) mimeType andBlock:(ProcessBlock) block andSemaphore:(dispatch_semaphore_t) semaphore {

    NSData *current = array[i];
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    // 设置头信息
    [self requestHeaders:headers serializer:manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:options.count];
    for (NSString *key in options) {
        id val = [options objectForKey:key];
        if (!val || (val == [NSNull null])) {
            continue;
        }
        if (![val isKindOfClass:[NSString class]]) {
            continue;
        }
        [dictionary setObject:[val dataUsingEncoding:NSUTF8StringEncoding] forKey:key];
    }
    // TODO 测试 最后删除
    [dictionary setValue:@(i) forKey:@"tmpId"];

    [manager POST:serverURL parameters:dictionary constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
        [formData appendPartWithFileData:current name:fileKey fileName:fileName mimeType:mimeType];
    } progress:^(NSProgress * _Nonnull uploadProgress) {
        block(uploadProgress.completedUnitCount, uploadProgress.totalUnitCount);
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSData *data = responseObject;

        NSError *error = nil;
        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
        NSString *msg = responseDict[@"msg"];
        if ([msg isEqualToString:@"success"]) {
            NSUInteger currentReceive = [responseDict[@"received"] longLongValue];
            NSLog(@"%lu", (unsigned long)currentReceive);
        } else {
            NSLog(@"msg => %@", msg);
        }
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        // TODO 失败重新发送
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}
 */

- (void) requestHeaders:(NSDictionary*) headers serializer:(AFHTTPSessionManager *) manager {
    [manager.requestSerializer setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    for (NSString *header in headers) {
        id value = [headers objectForKey:header];
        if (!value || (value == [NSNull null])) {
            value = @"null";
        }
        [manager.requestSerializer setValue:nil forHTTPHeaderField:header];

        if (![value isKindOfClass:[NSArray class]]) {
            value = [NSArray arrayWithObject:value];
        }
        for (id __strong subValue in value) {
            if ([subValue respondsToSelector:@selector(stringValue)]) {
                subValue = [subValue stringValue];
            }
            if ([subValue isKindOfClass:[NSString class]]) {
                [manager.requestSerializer setValue:subValue forHTTPHeaderField:header];
            }
        }
    }
}

@end
