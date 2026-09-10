#import "SAPContext.h"
#import <CommonCrypto/CommonDigest.h>
#include "SapMachine.h"

static std::vector<uint8_t> ReadVerifiedAsset(NSURL *root, NSString *name, NSUInteger size, NSString *hash) {
    NSData *data = [NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:name]];
    if (data.length != size) throw std::runtime_error("Missing or truncated SAP assets. Rebuild the app.");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *actual = [NSMutableString string];
    for (unsigned char byte : digest) [actual appendFormat:@"%02x", byte];
    if (![actual isEqualToString:hash]) throw std::runtime_error("SAP asset integrity check failed. Rebuild the app.");
    auto bytes = static_cast<const uint8_t *>(data.bytes);
    return {bytes, bytes + data.length};
}

static void SetError(NSError **error, const std::exception &exception) {
    if (error) *error = [NSError errorWithDomain:@"Asspp.SAP" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:exception.what()]}];
}

@implementation SAPContext {
    std::unique_ptr<SapMachine> _machine;
    std::vector<uint8_t> _hardwareID;
    uint64_t _context;
    BOOL _complete;
    NSUInteger _exchanges;
}

- (instancetype)initWithAssetsURL:(NSURL *)url hardwareID:(NSData *)hardwareID error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    try {
        if (hardwareID.length != 6) throw std::runtime_error("Invalid SAP device identifier.");
        auto bytes = static_cast<const uint8_t *>(hardwareID.bytes);
        _hardwareID.assign(bytes, bytes + hardwareID.length);
        _machine = SapMachine::Create(
            ReadVerifiedAsset(url, @"CoreFP", 29014912, @"f19141336be4198d0f8991bb00017c915efc7aeaece36c345f7faa1237ea6074"),
            ReadVerifiedAsset(url, @"CommerceCore", 207744, @"c5401e57402230f3c876409d295319ddf1e61287bc882683c5d61277be7bc1f2"),
            ReadVerifiedAsset(url, @"CommerceKit", 3271840, @"b84ff12c21987856c0a17b78f1ad82b73195a6dec5f3b208a17d245555a2c8a2"),
            ReadVerifiedAsset(url, @"CoreFP.icxs", 5288352, @"473e78af86979f5bd4f6269561caf770b3d16c098d918846eeac8cdd2fe6566a"),
            _hardwareID
        );
        _context = _machine->Initialize(_hardwareID);
        return self;
    } catch (const std::exception &exception) {
        SetError(error, exception);
        return nil;
    }
}

- (BOOL)complete { return _complete; }

- (NSData *)exchangeData:(NSData *)data version:(uint32_t)version error:(NSError **)error {
    try {
        if (!_machine || version != 200 || _exchanges >= 2 || !data.length || data.length > 1024 * 1024)
            throw std::runtime_error("Invalid SAP handshake.");
        auto [output, state] = _machine->Exchange(version, _hardwareID, _context, {static_cast<const uint8_t *>(data.bytes), data.length});
        if (state != (_exchanges == 0 ? 1 : 0)) throw std::runtime_error("Unexpected SAP handshake state.");
        _exchanges++;
        _complete = state == 0;
        return [NSData dataWithBytes:output.data() length:output.size()];
    } catch (const std::exception &exception) {
        SetError(error, exception);
        return nil;
    }
}

- (NSData *)signData:(NSData *)data error:(NSError **)error {
    try {
        if (!_complete || data.length > 1024 * 1024) throw std::runtime_error("SAP session is not ready.");
        auto signature = _machine->Sign(_context, {static_cast<const uint8_t *>(data.bytes), data.length});
        if (signature.empty()) throw std::runtime_error("SAP returned an empty signature.");
        return [NSData dataWithBytes:signature.data() length:signature.size()];
    } catch (const std::exception &exception) {
        SetError(error, exception);
        return nil;
    }
}

- (void)dealloc {
    if (_machine && _context) {
        try { _machine->Teardown(_context); } catch (...) { /* Destructors must not throw. */ }
    }
}
@end
