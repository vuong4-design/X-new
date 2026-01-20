#import "HttpRequest.h"
#define kMainUrl @"http://127.0.0.1:8888"

#pragma mark - 函数声明
// 辅助函数声明
NSArray* convertCollectionToJSONCompatible(id collection);
NSDictionary* convertDictionaryToJSONCompatible(NSDictionary *dictionary);
NSString* formEncodedStringFromDictionary(NSDictionary *dictionary);
void sendRequestWithMethod(NSString *urlString, NSString *method, id parameters, NSDictionary *headers, RequestCompletionHandler completion);

#pragma mark - GET请求函数
void daemonGET(NSString *urlString, RequestCompletionHandler completion){
    sendGETRequest([kMainUrl stringByAppendingString:urlString], completion);
}

void sendGETRequest(NSString *urlString, RequestCompletionHandler completion) {
    sendRequestWithMethod(urlString, @"GET", nil, nil, completion);
}

#pragma mark - POST请求函数
void daemonPOST(NSString *urlString, id parameters, RequestCompletionHandler completion) {
    sendPOSTRequest([kMainUrl stringByAppendingString:urlString], parameters, nil, completion);
}

void sendPOSTRequest(NSString *urlString, id parameters, NSDictionary *headers, RequestCompletionHandler completion) {
    sendRequestWithMethod(urlString, @"POST", parameters, headers, completion);
}

#pragma mark - 其他HTTP方法
void sendPUTRequest(NSString *urlString, id parameters, NSDictionary *headers, RequestCompletionHandler completion) {
    sendRequestWithMethod(urlString, @"PUT", parameters, headers, completion);
}

void sendDELETERequest(NSString *urlString, id parameters, NSDictionary *headers, RequestCompletionHandler completion) {
    sendRequestWithMethod(urlString, @"DELETE", parameters, headers, completion);
}

void sendPATCHRequest(NSString *urlString, id parameters, NSDictionary *headers, RequestCompletionHandler completion) {
    sendRequestWithMethod(urlString, @"PATCH", parameters, headers, completion);
}

#pragma mark - 通用请求方法
void sendRequestWithMethod(NSString *urlString, NSString *method, id parameters, NSDictionary *headers, RequestCompletionHandler completion) {
    // 检查 URL 是否有效
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"NetworkError" 
                                            code:-1 
                                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        if (completion) completion(nil, error);
        return;
    }

    // 创建不使用代理的Session配置
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.connectionProxyDictionary = @{}; // 关键设置：禁用代理
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData; // 忽略缓存
    
    // 创建自定义Session
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    // 创建请求
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:method];
    [request setTimeoutInterval:10];
    [request setValue:@"no-proxy" forHTTPHeaderField:@"Proxy-Connection"]; // 额外声明不要代理
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // 添加自定义请求头
    if (headers) {
        [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [request setValue:obj forHTTPHeaderField:key];
        }];
    }
    
    // 处理POST/PUT/PATCH等请求参数
    if (([method isEqualToString:@"POST"] || 
         [method isEqualToString:@"PUT"] || 
         [method isEqualToString:@"PATCH"] ||
         [method isEqualToString:@"DELETE"]) && parameters) {
        
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        
        
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters 
                                                          options:0 
                                                            error:&jsonError];
        
        if (!jsonError && jsonData) {
            [request setHTTPBody:jsonData];
        } else {
            // 如果JSON序列化失败，尝试使用表单格式
            [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
            
            // 将参数转换为字典格式
            NSDictionary *paramDict;
            if ([parameters isKindOfClass:[NSDictionary class]]) {
                paramDict = parameters;
            } else {
                paramDict = @{@"data": [parameters description]};
            }
            
            NSString *formData = formEncodedStringFromDictionary(paramDict);
            [request setHTTPBody:[formData dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    
    // 发起请求
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 处理响应
        id responseData = nil;
        
        if (error) {
            NSLog(@"Request failed: %@ | URL: %@", error.localizedDescription, urlString);
            if (completion) completion(nil, error);
            return;
        }
        
        // 获取HTTP状态码
        NSInteger statusCode = 0;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            statusCode = [(NSHTTPURLResponse *)response statusCode];
        }
        
        if (!data || data.length == 0) {
            if (statusCode >= 200 && statusCode < 300) {
                // 可能是204 No Content等情况
                if (completion) completion(@{@"status": @"success", @"code": @(statusCode)}, nil);
            } else {
                NSError *emptyError = [NSError errorWithDomain:@"NetworkError" 
                                                         code:-2 
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty response data",
                                                               @"statusCode": @(statusCode)}];
                if (completion) completion(nil, emptyError);
            }
            return;
        }
        
        // 自动识别JSON/文本
        NSError *jsonError;
        id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
        
        if (!jsonError) {
            responseData = jsonObject;
        } else {
            responseData = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!responseData) responseData = data; // 保留原始数据
        }
        
        if (completion) completion(responseData, nil);
    }];

    [task resume];
    
    // 注意：不要忘记在适当的时候调用 [session finishTasksAndInvalidate]
    [session finishTasksAndInvalidate];
}

#pragma mark - 辅助方法
// 转换集合类型为JSON兼容格式
NSArray* convertCollectionToJSONCompatible(id collection) {
    if (!collection) return nil;
    
    NSMutableArray *result = [NSMutableArray array];
    
    if ([collection isKindOfClass:[NSSet class]] || 
        [collection isKindOfClass:[NSMutableSet class]]) {
        // 处理Set类型
        NSSet *set = (NSSet *)collection;
        for (id item in set) {
            // 递归处理嵌套集合
            if ([item isKindOfClass:[NSSet class]] || 
                [item isKindOfClass:[NSMutableSet class]] ||
                [item isKindOfClass:[NSArray class]] ||
                [item isKindOfClass:[NSMutableArray class]]) {
                [result addObject:convertCollectionToJSONCompatible(item)];
            } else if ([item isKindOfClass:[NSDictionary class]] ||
                      [item isKindOfClass:[NSMutableDictionary class]]) {
                [result addObject:convertDictionaryToJSONCompatible(item)];
            } else if ([item isKindOfClass:[NSNumber class]] ||
                      [item isKindOfClass:[NSString class]] ||
                      [item isKindOfClass:[NSNull class]]) {
                [result addObject:item];
            } else {
                // 尝试转换为字符串
                [result addObject:[item description]];
            }
        }
    } else if ([collection isKindOfClass:[NSArray class]] ||
               [collection isKindOfClass:[NSMutableArray class]]) {
        // 处理数组类型
        NSArray *array = (NSArray *)collection;
        for (id item in array) {
            if ([item isKindOfClass:[NSSet class]] || 
                [item isKindOfClass:[NSMutableSet class]] ||
                [item isKindOfClass:[NSArray class]] ||
                [item isKindOfClass:[NSMutableArray class]]) {
                [result addObject:convertCollectionToJSONCompatible(item)];
            } else if ([item isKindOfClass:[NSDictionary class]] ||
                      [item isKindOfClass:[NSMutableDictionary class]]) {
                [result addObject:convertDictionaryToJSONCompatible(item)];
            } else if ([item isKindOfClass:[NSNumber class]] ||
                      [item isKindOfClass:[NSString class]] ||
                      [item isKindOfClass:[NSNull class]]) {
                [result addObject:item];
            } else {
                [result addObject:[item description]];
            }
        }
    }
    
    return [result copy];
}

// 转换字典类型为JSON兼容格式
NSDictionary* convertDictionaryToJSONCompatible(NSDictionary *dictionary) {
    if (!dictionary) return nil;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    for (id key in dictionary) {
        id value = dictionary[key];
        NSString *keyString = [key description];
        
        if ([value isKindOfClass:[NSSet class]] || 
            [value isKindOfClass:[NSMutableSet class]] ||
            [value isKindOfClass:[NSArray class]] ||
            [value isKindOfClass:[NSMutableArray class]]) {
            result[keyString] = convertCollectionToJSONCompatible(value);
        } else if ([value isKindOfClass:[NSDictionary class]] ||
                  [value isKindOfClass:[NSMutableDictionary class]]) {
            result[keyString] = convertDictionaryToJSONCompatible(value);
        } else if ([value isKindOfClass:[NSNumber class]] ||
                  [value isKindOfClass:[NSString class]] ||
                  [value isKindOfClass:[NSNull class]]) {
            result[keyString] = value;
        } else {
            // 其他类型转换为字符串
            result[keyString] = [value description];
        }
    }
    
    return [result copy];
}


// 表单编码字符串
NSString* formEncodedStringFromDictionary(NSDictionary *dictionary) {
    NSMutableArray *parts = [NSMutableArray array];
    
    for (NSString *key in dictionary) {
        id value = dictionary[key];
        
        // 处理数组或集合值
        if ([value isKindOfClass:[NSArray class]] || 
            [value isKindOfClass:[NSSet class]]) {
            for (id item in value) {
                NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                NSString *encodedValue = [[item description] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                [parts addObject:[NSString stringWithFormat:@"%@[]=%@", encodedKey, encodedValue]];
            }
        } else {
            NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            NSString *encodedValue = [[value description] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            [parts addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
        }
    }
    
    return [parts componentsJoinedByString:@"&"];
}

