#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Owns one interpreted SAP session. Call from a single actor, never the main thread.
@interface SAPContext : NSObject
- (nullable instancetype)initWithAssetsURL:(NSURL *)url hardwareID:(NSData *)hardwareID error:(NSError **)error;
@property(nonatomic, readonly) BOOL complete;
- (nullable NSData *)exchangeData:(NSData *)data version:(uint32_t)version error:(NSError **)error;
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
