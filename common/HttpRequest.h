// HttpRequest.h
#import <Foundation/Foundation.h>

typedef void (^RequestCompletionHandler)(id responseData, NSError *error);

// GET请求
void daemonGET(NSString *urlString, RequestCompletionHandler completion);
void sendGETRequest(NSString *urlString, RequestCompletionHandler completion);

// POST请求 - 支持多种数据类型
void daemonPOST(NSString *urlString, id parameters, RequestCompletionHandler completion);
void sendPOSTRequest(NSString *urlString, id parameters, NSDictionary *headers, RequestCompletionHandler completion);

// 其他HTTP方法
void sendPUTRequest(NSString *urlString, id parameters, NSDictionary *headers, RequestCompletionHandler completion);
void sendDELETERequest(NSString *urlString, id parameters, NSDictionary *headers, RequestCompletionHandler completion);
void sendPATCHRequest(NSString *urlString, id parameters, NSDictionary *headers, RequestCompletionHandler completion);
