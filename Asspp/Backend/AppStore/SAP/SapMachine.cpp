// Adapted from Sorvigolova/ipatool; see Resources/Licenses/ipatool.txt.
#include "SapMachine.h"

#include <unicorn/unicorn.h>

#include <algorithm>
#include <cassert>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <format>
#include <stdexcept>

// UC_X86_REG_* come from <unicorn/x86.h> via <unicorn/unicorn.h> — no local defs needed.
static constexpr int kArgRegs[6] = {
    UC_X86_REG_RDI, UC_X86_REG_RSI, UC_X86_REG_RDX,
    UC_X86_REG_RCX, UC_X86_REG_R8,  UC_X86_REG_R9,
};

static inline void UC_CHECK(uc_err err, const char* what) {
    if (err != UC_ERR_OK)
        throw std::runtime_error(std::format("{}: {}", what, uc_strerror(err)));
}

static inline uint64_t AlignUp(uint64_t v, uint64_t a) { return (v + a - 1) & ~(a - 1); }

// From the Go source:
//   fakeHandle   = math.MaxUint64
//   coreFPFile   = 3
//   icxsPath     = "./../CoreFP.icxs"
//   coreFPPath   = "/System/Library/PrivateFrameworks/CoreFP.framework/CoreFP"
static constexpr uint64_t kFakeHandle = UINT64_MAX;
static constexpr uint64_t kCoreFPFile = 3;
static const char* kIcxsPath         = "./../CoreFP.icxs";
static const char* kCoreFPDlPath     = "/System/Library/PrivateFrameworks/CoreFP.framework/CoreFP";

// Keys for CFStringCreateWithCString check
static const char* kKeySerial  = "IOPlatformSerialNumber";
static const char* kKeyUUID    = "IOPlatformUUID";
static const char* kKeyBoard   = "board-id";
static const char* kKeyedMsg   = "objectForKey:";

static constexpr uint64_t kMaxGuestTransfer = uint64_t(64) << 20;

static size_t CheckedTransfer(uint64_t size) {
    if (size > kMaxGuestTransfer) throw std::runtime_error("guest transfer exceeds limit");
    return static_cast<size_t>(size);
}

// ═══════════════════════════════════════════════════════════════════════════
//  SapShims — construction
// ═══════════════════════════════════════════════════════════════════════════

SapShims::SapShims(uc_engine* uc,
                   std::unordered_map<std::string, uint64_t> coreFPExports,
                   std::vector<uint8_t> icxs,
                   std::vector<uint8_t> macAddress)
    : uc_(uc)
    , coreExports_(std::move(coreFPExports))
    , icxs_(std::move(icxs))
    , macAddress_(std::move(macAddress))
{
    UC_CHECK(uc_mem_map(uc_, kShimBase, kShimSize, UC_PROT_ALL), "map shim region");

    RegisterMemoryServices();
    RegisterPlatformServices();

    UC_CHECK(uc_hook_add(uc_, &hook_, UC_HOOK_CODE,
                         reinterpret_cast<void*>(&SapShims::HookCallback), this,
                         kShimBase, kShimBase + kShimCodeSize - 1),
             "add shim hook");
}

SapShims::~SapShims() {
    if (hook_) uc_hook_del(uc_, hook_);
}

void SapShims::SetHeap(uint64_t heapBase, uint64_t heapSize) {
    heapBase_   = heapBase;
    heapEnd_    = heapBase + heapSize;
    heapSize_   = heapSize;
    heapCursor_ = 0;   // ← cursor starts at 0, actual address = heapBase + cursor
}

// ─── registration helpers ─────────────────────────────────────────────────────

uint64_t SapShims::AddFunction(std::string name, Handler handler) {
    auto it = symbols_.find(name);
    if (it != symbols_.end()) return it->second;

    if (codeCursor_ + kSlotSize > kShimBase + kShimCodeSize)
        throw std::runtime_error(std::format("shim code area full (adding {})", name));

    uint64_t addr = codeCursor_;
    codeCursor_  += kSlotSize;

    uint8_t ret = 0xC3;
    UC_CHECK(uc_mem_write(uc_, addr, &ret, 1), "write shim stub");

    entries_[addr] = { name, std::move(handler) };
    symbols_[std::move(name)] = addr;
    return addr;
}

uint64_t SapShims::AddData(std::string name, const void* data, size_t len) {
    auto it = symbols_.find(name);
    if (it != symbols_.end()) return it->second;

    dataCursor_ = AlignUp(dataCursor_, 8);
    size_t reserved = std::max(len, size_t(8));
    if (dataCursor_ + reserved > kShimBase + kShimSize)
        throw std::runtime_error(std::format("shim data area full ({})", name));

    uint64_t addr = dataCursor_;
    dataCursor_  += reserved;

    if (data && len)
        UC_CHECK(uc_mem_write(uc_, addr, data, len), "write shim data");

    symbols_[std::move(name)] = addr;
    return addr;
}

void SapShims::AddAliases(std::initializer_list<const char*> names, Handler h) {
    // First name: AddFunction; rest: alias to same address
    uint64_t addr = 0;
    for (const char* n : names) {
        if (!addr) { addr = AddFunction(n, h); }
        else {
            symbols_[n] = addr;
            entries_[addr].first = n; // last name wins for display
        }
    }
}

// ─── dispatch ────────────────────────────────────────────────────────────────

void SapShims::HookCallback(uc_engine*, uint64_t addr, uint32_t, void* user) {
    static_cast<SapShims*>(user)->Dispatch(addr);
}

void SapShims::Dispatch(uint64_t addr) {
    auto it = entries_.find(addr);
    if (it == entries_.end()) {
        Fail(std::format("guest entered unknown shim {:#x}", addr));
        return;
    }
    try { it->second.second(); }
    catch (const std::exception& e) { Fail(std::format("{}: {}", it->second.first, e.what())); }
}

void SapShims::Fail(std::string msg) {
    if (fault_.empty()) fault_ = std::move(msg);
    uc_emu_stop(uc_);
}

// ─── ABI helpers ──────────────────────────────────────────────────────────────

uint64_t SapShims::Arg(int idx) {
    if (idx >= 0 && idx < 6) {
        uint64_t v = 0;
        UC_CHECK(uc_reg_read(uc_, kArgRegs[idx], &v), "read arg reg");
        return v;
    }
    if (idx < 0) throw std::runtime_error("negative arg index");
    uint64_t rsp = 0;
    UC_CHECK(uc_reg_read(uc_, UC_X86_REG_RSP, &rsp), "read RSP");
    uint64_t v = 0;
    UC_CHECK(uc_mem_read(uc_, rsp + 8 + uint64_t(idx - 6) * 8, &v, 8), "read stack arg");
    return v;
}

void SapShims::SetResult(uint64_t v) {
    UC_CHECK(uc_reg_write(uc_, UC_X86_REG_RAX, &v), "write RAX");
}

// ─── guest memory ─────────────────────────────────────────────────────────────

uint32_t SapShims::GuestRead32(uint64_t a) {
    uint32_t v = 0; UC_CHECK(uc_mem_read(uc_, a, &v, 4), "r32"); return v;
}
uint64_t SapShims::GuestRead64(uint64_t a) {
    uint64_t v = 0; UC_CHECK(uc_mem_read(uc_, a, &v, 8), "r64"); return v;
}
void SapShims::GuestWrite32(uint64_t a, uint32_t v) {
    UC_CHECK(uc_mem_write(uc_, a, &v, 4), "w32");
}
void SapShims::GuestWrite64(uint64_t a, uint64_t v) {
    UC_CHECK(uc_mem_write(uc_, a, &v, 8), "w64");
}
void SapShims::GuestRead(uint64_t a, void* dst, size_t n) {
    UC_CHECK(uc_mem_read(uc_, a, dst, n), "rN");
}
void SapShims::GuestWrite(uint64_t a, const void* src, size_t n) {
    UC_CHECK(uc_mem_write(uc_, a, src, n), "wN");
}
std::string SapShims::GuestReadCString(uint64_t a) {
    std::string s;
    for (size_t i = 0; i < 4096; ++i) {
        char c = 0; UC_CHECK(uc_mem_read(uc_, a + i, &c, 1), "rcs");
        if (!c) return s;
        s += c;
    }
    throw std::runtime_error("guest cstring too long");
}

// ─── heap (exact port of Go allocate/release/coalesceFreeBlocks) ─────────────

uint64_t SapShims::HeapAlloc(uint64_t size) {
    if (size > kMaxGuestTransfer)
        throw std::runtime_error(std::format("allocation {} exceeds limit", size));

    uint64_t reserved = AlignUp(std::max(size, uint64_t(1)), 16);

    // Check free list — use first block that fits, split if larger
    for (size_t i = 0; i < freeBlocks_.size(); ++i) {
        auto& blk = freeBlocks_[i];
        if (blk.size < reserved) continue;

        uint64_t addr = blk.addr;
        if (blk.size == reserved) {
            freeBlocks_.erase(freeBlocks_.begin() + i);
        } else {
            blk.addr += reserved;
            blk.size -= reserved;
        }
        allocations_[addr] = { size, reserved };
        return addr;
    }

    // Bump allocate — heapCursor is OFFSET from heapBase_
    if (heapCursor_ > heapSize_ || reserved > heapSize_ - heapCursor_)
        throw std::runtime_error("guest heap exhausted");

    uint64_t addr = heapBase_ + heapCursor_;
    heapCursor_  += reserved;
    allocations_[addr] = { size, reserved };
    return addr;
}

void SapShims::HeapFree(uint64_t ptr) {
    if (!ptr) return;
    auto it = allocations_.find(ptr);
    if (it == allocations_.end())
        throw std::runtime_error(std::format("free unknown pointer {:#x}", ptr));

    uint64_t reserved = it->second.reserved;

    // Zero the freed region (matches Go behaviour)
    std::vector<uint8_t> zeros(reserved, 0);
    uc_mem_write(uc_, ptr, zeros.data(), reserved);

    allocations_.erase(it);
    freeBlocks_.push_back({ ptr, reserved });
    CoalesceFreeBlocks();
}

uint64_t SapShims::HeapRealloc(uint64_t oldPtr, uint64_t newSize) {
    if (!oldPtr) return HeapAlloc(newSize);

    auto it = allocations_.find(oldPtr);
    if (it == allocations_.end())
        throw std::runtime_error(std::format("realloc unknown pointer {:#x}", oldPtr));

    // If new size fits in existing reservation — update in place
    if (newSize <= it->second.reserved) {
        it->second.size = newSize;
        return oldPtr;
    }

    // Allocate new, copy, free old
    const size_t oldSize = it->second.size; // HeapAlloc may rehash allocations_.
    uint64_t newPtr = HeapAlloc(newSize);
    std::vector<uint8_t> buf(oldSize);
    GuestRead(oldPtr, buf.data(), buf.size());
    GuestWrite(newPtr, buf.data(), buf.size());
    HeapFree(oldPtr);
    return newPtr;
}

void SapShims::CoalesceFreeBlocks() {
    // Sort by address
    std::sort(freeBlocks_.begin(), freeBlocks_.end(),
              [](const FreeBlock& a, const FreeBlock& b) { return a.addr < b.addr; });

    // Merge adjacent
    std::vector<FreeBlock> merged;
    for (auto& blk : freeBlocks_) {
        if (!merged.empty() && merged.back().addr + merged.back().size == blk.addr)
            merged.back().size += blk.size;
        else
            merged.push_back(blk);
    }
    freeBlocks_ = std::move(merged);

    // Trim trailing free blocks back into heapCursor
    while (!freeBlocks_.empty()) {
        auto& last = freeBlocks_.back();
        if (last.addr + last.size != heapBase_ + heapCursor_) break;
        heapCursor_ -= last.size;
        freeBlocks_.pop_back();
    }
}

// ─── Resolve ──────────────────────────────────────────────────────────────────

uint64_t SapShims::Resolve(std::string_view name) {
    std::string key(name);
    auto it = symbols_.find(key);
    if (it != symbols_.end()) return it->second;

    // CoreFP real exports
    auto ce = coreExports_.find(key);
    if (ce != coreExports_.end()) { symbols_[key] = ce->second; return ce->second; }

    // Resolve unused imports lazily, but never pretend an unsupported call succeeded.
    return AddFunction(key, [key]() { throw std::runtime_error("unsupported SAP import: " + key); });
}

// ═══════════════════════════════════════════════════════════════════════════
//  Memory services (exact port of shim_memory.go)
// ═══════════════════════════════════════════════════════════════════════════

void SapShims::RegisterMemoryServices() {
    // NOTE: All Apple dylib exports begin with '_' — this is the Mach-O convention.
    AddFunction("_malloc", [this]() {
        SetResult(HeapAlloc(Arg(0)));
    });
    AddFunction("_malloc_good_size", [this]() {
        uint64_t sz = Arg(0);
        SetResult(AlignUp(std::max(sz, uint64_t(1)), 16));
    });
    AddFunction("_malloc_size", [this]() {
        auto it = allocations_.find(Arg(0));
        SetResult(it != allocations_.end() ? it->second.reserved : 0);
    });
    AddFunction("_calloc", [this]() {
        uint64_t count = Arg(0), size = Arg(1);
        if (size && count > kMaxGuestTransfer / size)
            throw std::runtime_error("calloc exceeds guest allocation limit");
        uint64_t total = count * size;
        uint64_t addr  = HeapAlloc(total);
        if (total) {
            std::vector<uint8_t> z(total, 0);
            GuestWrite(addr, z.data(), total);
        }
        SetResult(addr);
    });
    AddAliases({"_realloc", "_reallocf"}, [this]() {
        SetResult(HeapRealloc(Arg(0), Arg(1)));
    });
    AddFunction("_free", [this]() {
        uint64_t ptr = Arg(0);
        if (ptr) HeapFree(ptr);
        SetResult(0);
    });

    // memcpy / memmove — identical behaviour for us (single-threaded, no overlap issues)
    AddAliases({"_memcpy", "_memmove"}, [this]() {
        uint64_t dst = Arg(0), src = Arg(1), n = Arg(2);
        if (n) {
            std::vector<uint8_t> buf(CheckedTransfer(n));
            GuestRead(src, buf.data(), n);
            GuestWrite(dst, buf.data(), n);
        }
        SetResult(dst);
    });
    AddFunction("_memset", [this]() {
        uint64_t dst = Arg(0); uint8_t c = static_cast<uint8_t>(Arg(1)); uint64_t n = Arg(2);
        if (n) { std::vector<uint8_t> buf(CheckedTransfer(n), c); GuestWrite(dst, buf.data(), n); }
        SetResult(dst);
    });
    AddFunction("___bzero", [this]() {  // triple underscore (Darwin mangling)
        uint64_t dst = Arg(0), n = Arg(1);
        if (n) { std::vector<uint8_t> z(CheckedTransfer(n), 0); GuestWrite(dst, z.data(), n); }
        SetResult(dst);
    });
    // __memcpy_chk(dst, src, len, dstlen) — check len <= dstlen, then copy
    AddFunction("___memcpy_chk", [this]() {
        uint64_t dst = Arg(0), src = Arg(1), len = Arg(2), cap = Arg(3);
        if (len > cap) throw std::runtime_error("___memcpy_chk: len > cap");
        if (len) { std::vector<uint8_t> buf(CheckedTransfer(len)); GuestRead(src, buf.data(), len); GuestWrite(dst, buf.data(), len); }
        SetResult(dst);
    });
    // __memset_chk(dst, c, len, dstlen)
    AddFunction("___memset_chk", [this]() {
        uint64_t dst = Arg(0); uint8_t c = static_cast<uint8_t>(Arg(1));
        uint64_t len = Arg(2), cap = Arg(3);
        if (len > cap) throw std::runtime_error("___memset_chk: len > cap");
        if (len) { std::vector<uint8_t> buf(CheckedTransfer(len), c); GuestWrite(dst, buf.data(), len); }
        SetResult(dst);
    });
    AddFunction("_memcmp", [this]() {
        uint64_t a = Arg(0), b = Arg(1), n = Arg(2);
        if (!n) { SetResult(0); return; }
        std::vector<uint8_t> ba(CheckedTransfer(n)), bb(CheckedTransfer(n));
        GuestRead(a, ba.data(), n); GuestRead(b, bb.data(), n);
        SetResult(static_cast<uint64_t>(static_cast<int64_t>(
            std::memcmp(ba.data(), bb.data(), n))));
    });
    AddFunction("_strcmp", [this]() {
        std::string a = GuestReadCString(Arg(0));
        std::string b = GuestReadCString(Arg(1));
        SetResult(static_cast<uint64_t>(static_cast<int64_t>(
            std::memcmp(a.data(), b.data(), std::min(a.size(), b.size()) + 1))));
    });
    AddFunction("_strncmp", [this]() {
        uint64_t la = Arg(0), lb = Arg(1), n = CheckedTransfer(Arg(2));
        // Page-safe comparison matching Go implementation
        for (uint64_t off = 0; off < n; ) {
            uint64_t chunk = std::min({n - off,
                                        uint64_t(0x1000) - (la + off) % 0x1000,
                                        uint64_t(0x1000) - (lb + off) % 0x1000});
            std::vector<uint8_t> a(chunk), b(chunk);
            GuestRead(la + off, a.data(), chunk);
            GuestRead(lb + off, b.data(), chunk);
            for (size_t i = 0; i < chunk; ++i) {
                if (a[i] != b[i]) { SetResult(uint64_t(int64_t(int(a[i]) - int(b[i])))); return; }
                if (a[i] == 0)    { SetResult(0); return; }
            }
            off += chunk;
        }
        SetResult(0);
    });
    AddFunction("_strlen", [this]() {
        SetResult(GuestReadCString(Arg(0)).size());
    });
}

// ═══════════════════════════════════════════════════════════════════════════
//  Platform services (exact port of shim_platform.go)
// ═══════════════════════════════════════════════════════════════════════════

void SapShims::RegisterPlatformServices() {
    // ── returnZero group ──────────────────────────────────────────────────────
    AddAliases({
        "_CFBundleGetMainBundle", "_CFDataGetBytePtr", "_CFDataGetLength",
        "_CFStringGetLength", "_CFStringGetMaximumSizeForEncoding",
        "_CFUUIDCreateString", "_IORegistryEntryFromPath",
        "_IORegistryEntrySearchCFProperty", "_IOServiceMatching",
        "_getenv", "_pthread_self",
    }, [this]() { SetResult(0); });

    // ── returnFakeHandle group ────────────────────────────────────────────────
    AddAliases({
        "_CFDictionaryGetValue", "_DADiskCopyDescription",
        "_DADiskCreateFromBSDName", "_DASessionCreate",
        "_IORegistryEntryCreateCFProperty",
    }, [this]() { SetResult(kFakeHandle); });

    // ── returnZero (release/mutex) group ──────────────────────────────────────
    AddAliases({
        "_CFRelease", "_IOObjectRelease",
        "_close", "_close$UNIX2003",
        "_pthread_mutex_lock", "_pthread_mutex_unlock",
        "_pthread_rwlock_init",  "_pthread_rwlock_init$UNIX2003",
        "_pthread_rwlock_unlock","_pthread_rwlock_unlock$UNIX2003",
        "_pthread_rwlock_wrlock","_pthread_rwlock_wrlock$UNIX2003",
    }, [this]() { SetResult(0); });

    // ── returnMinusOne group ───────────────────────────────────────────────────
    AddAliases({
        "_fcntl", "_fcntl$UNIX2003",
        "_lstat$INODE64", "_statfs", "_statfs$INODE64",
    }, [this]() { SetResult(UINT64_MAX); });

    // ── abort group ───────────────────────────────────────────────────────────
    AddAliases({"_abort", "___stack_chk_fail", "dyld_stub_binder"},
               []() { throw std::runtime_error("guest aborted"); });

    // ── CFString ──────────────────────────────────────────────────────────────
    AddFunction("_CFStringCreateWithCString", [this]() {
        std::string val = GuestReadCString(Arg(1)); // arg0=allocator, arg1=cstr
        if (val == kKeySerial || val == kKeyUUID || val == kKeyBoard)
            SetResult(kFakeHandle);
        else
            SetResult(0);
    });
    AddFunction("_CFStringCreateWithCStringNoCopy", [this]() { SetResult(0); });
    AddFunction("_CFStringGetCString", [this]() {
        uint64_t buf = Arg(1); uint64_t cap = Arg(2);
        if (buf && cap) { uint8_t nul = 0; GuestWrite(buf, &nul, 1); }
        SetResult(1);
    });

    // ── IOKit iterator simulation ─────────────────────────────────────────────
    AddFunction("_IOIteratorNext", [this]() {
        ++iterator_;
        SetResult(iterator_ % 2);
    });
    AddFunction("_IORegistryEntryGetParentEntry", [this]() {
        uint64_t parent = Arg(2);
        if (!parent) throw std::runtime_error("parent output is null");
        GuestWrite32(parent, UINT32_MAX);
        SetResult(0);
    });
    AddFunction("_IOServiceGetMatchingServices", [this]() {
        uint64_t iter = Arg(2);
        if (!iter) throw std::runtime_error("iterator output is null");
        iterator_ = 0;
        GuestWrite32(iter, UINT32_MAX);
        SetResult(0);
    });
    AddFunction("_IOServiceGetMatchingService", [this]() {
        SetResult(UINT32_MAX);
    });

    // ── OSAtomic ─────────────────────────────────────────────────────────────
    AddFunction("_OSAtomicCompareAndSwap32Barrier", [this]() {
        uint32_t oldVal = static_cast<uint32_t>(Arg(0));
        uint32_t newVal = static_cast<uint32_t>(Arg(1));
        uint64_t addr   = Arg(2);
        uint32_t cur    = GuestRead32(addr);
        if (cur != oldVal) { SetResult(0); return; }
        GuestWrite32(addr, newVal);
        SetResult(1);
    });

    // ── errno ─────────────────────────────────────────────────────────────────
    // errno cell: 8 bytes (matches Go: make([]byte, 8))
    std::vector<uint8_t> errnoZero(8, 0);
    errnoCell_ = AddData("guest.errno", errnoZero.data(), 8);
    AddFunction("___error", [this]() { SetResult(errnoCell_); });

    // ── stack guard ───────────────────────────────────────────────────────────
    static const uint8_t kGuard[8] = {0xA5, 0x71, 0x3C, 0xD9, 0x86, 0x42, 0xEF, 0x10};
    AddData("___stack_chk_guard", kGuard, 8);

    // ── CF constant data cells (8 bytes each) ─────────────────────────────────
    uint8_t z8[8] = {};
    AddData("_kCFAllocatorDefault",          z8, 8);
    AddData("_kCFAllocatorNull",             z8, 8);
    AddData("_kDADiskDescriptionVolumeUUIDKey", z8, 8);
    AddData("_kIOMasterPortDefault",         z8, 8);

    // ── arc4random ────────────────────────────────────────────────────────────
    AddFunction("_arc4random", [this]() {
        // Darwin's system CSPRNG, matching the guest API's contract.
        SetResult(arc4random());
    });

    // ── dlopen / dlsym ────────────────────────────────────────────────────────
    AddFunction("_dlopen", [this]() {
        std::string path = GuestReadCString(Arg(0));
        SetResult(path == kCoreFPDlPath ? kFakeHandle : 0);
    });
    AddFunction("_dlsym", [this]() {
        // arg0=handle, arg1=name — prepend '_' to look up in coreExports
        std::string name = "_" + GuestReadCString(Arg(1));
        auto it = coreExports_.find(name);
        SetResult(it != coreExports_.end() ? it->second : 0);
    });

    // ── gettimeofday ──────────────────────────────────────────────────────────
    AddFunction("_gettimeofday", [this]() {
        uint64_t tvAddr = Arg(0), tzAddr = Arg(1);
        auto now = std::chrono::system_clock::now();
        auto secs = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();
        auto usecs = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch()).count() % 1'000'000;
        if (tvAddr) {
            uint8_t tv[16] = {};
            uint64_t s64 = static_cast<uint64_t>(secs);
            uint32_t u32 = static_cast<uint32_t>(usecs);
            std::memcpy(tv,     &s64, 8);
            std::memcpy(tv + 8, &u32, 4);
            GuestWrite(tvAddr, tv, 16);
        }
        if (tzAddr) {
            uint8_t tz[8] = {};
            GuestWrite(tzAddr, tz, 8);
        }
        SetResult(0);
    });

    // ── objc_msgSend ──────────────────────────────────────────────────────────
    AddFunction("_objc_msgSend", [this]() {
        std::string sel = GuestReadCString(Arg(1));
        SetResult(sel == kKeyedMsg ? kFakeHandle : 0);
    });

    // ── open / read (CoreFP.icxs file simulation) ─────────────────────────────
    AddAliases({"_open", "_open$UNIX2003"}, [this]() {
        std::string path = GuestReadCString(Arg(0));
        if (path == kIcxsPath) {
            icxsOffset_ = 0;
            SetResult(kCoreFPFile);
        } else {
            SetResult(UINT64_MAX); // -1
        }
    });
    AddAliases({"_read", "_read$UNIX2003"}, [this]() {
        uint64_t fd  = Arg(0), buf = Arg(1), req = Arg(2);
        if (fd != kCoreFPFile) { SetResult(UINT64_MAX); return; }
        size_t rem  = icxs_.size() - icxsOffset_;
        size_t nread = std::min(rem, static_cast<size_t>(req));
        if (nread) GuestWrite(buf, icxs_.data() + icxsOffset_, nread);
        icxsOffset_ += nread;
        SetResult(nread);
    });

    // ── pthread_once ─────────────────────────────────────────────────────────
    // When control != 0: mark done, push initializer as fake return address
    // so when this shim's RET fires, execution goes to initializer.
    AddFunction("_pthread_once", [this]() {
        uint64_t control     = Arg(0);
        uint64_t initializer = Arg(1);

        uint64_t value = GuestRead64(control);
        if (value == 0) { SetResult(0); return; }   // already initialized

        GuestWrite64(control, 0);  // mark as done

        // Push initializer onto guest stack — when this stub's RET fires,
        // it will jump to initializer(). Initializer's RET returns to the
        // original caller of pthread_once.
        uint64_t rsp = 0;
        UC_CHECK(uc_reg_read(uc_, UC_X86_REG_RSP, &rsp), "read RSP");
        rsp -= 8;
        GuestWrite64(rsp, initializer);
        UC_CHECK(uc_reg_write(uc_, UC_X86_REG_RSP, &rsp), "write RSP");

        SetResult(0);
    });

    // ── _get_mac_address — returns actual machine MAC, NOT CommerceCore's IOKit impl ──
    AddFunction("_get_mac_address", [this]() {
        if (macAddress_.empty()) {
            SetResult(0);
            return;
        }
        uint64_t bufAddr = HeapAlloc(macAddress_.size() + 1);
        GuestWrite(bufAddr, macAddress_.data(), macAddress_.size());
        uint8_t nul = 0;
        GuestWrite(bufAddr + macAddress_.size(), &nul, 1);
        SetResult(bufAddr);
    });

    // ── sysctl / sysctlbyname ─────────────────────────────────────────────────
    AddFunction("_sysctl",       [this]() { SetResult(UINT64_MAX); });
    AddFunction("_sysctlbyname", [this]() {
        uint64_t lenAddr = Arg(2);
        if (lenAddr) GuestWrite64(lenAddr, 0);
        SetResult(0);
    });
}

// ═══════════════════════════════════════════════════════════════════════════
//  SapMachine::Create
// ═══════════════════════════════════════════════════════════════════════════

std::unique_ptr<SapMachine> SapMachine::Create(
    std::vector<uint8_t> coreFP,
    std::vector<uint8_t> commerceCore,
    std::vector<uint8_t> commerceKit,
    std::vector<uint8_t> coreFPIcxs,
    std::vector<uint8_t> hardwareID)
{
    auto m = std::unique_ptr<SapMachine>(new SapMachine());

    // 1. Open Unicorn x86-64
    UC_CHECK(uc_open(UC_ARCH_X86, UC_MODE_64, &m->uc_), "uc_open");

    // 2. Map fixed regions (same layout as machine.go)
    for (auto [addr, size] : std::initializer_list<std::pair<uint64_t,uint64_t>>{
        { kReturnAddr,  kPageSize    },
        { kScratchBase, kScratchSize },
        { kHeapBase,    kHeapSize    },
        { kStackBase,   kStackSize   },
    }) UC_CHECK(uc_mem_map(m->uc_, addr, size, UC_PROT_ALL), "uc_mem_map region");

    // HLT at returnAddress — acts as stop sentinel
    uint8_t hlt = 0xF4;
    UC_CHECK(uc_mem_write(m->uc_, kReturnAddr, &hlt, 1), "write HLT");

    // 3. Parse images
    auto imgCoreFP       = MachImage::Open("CoreFP",       std::move(coreFP));
    auto imgCommerceCore = MachImage::Open("CommerceCore", std::move(commerceCore));
    auto imgCommerceKit  = MachImage::Open("CommerceKit",  std::move(commerceKit));

    // 4. Collect CoreFP real exports (the 6 obfuscated names + get_mac_address)
    static const char* kCoreFPExportNames[] = {
        "_WIn9UJ86JKdV4dM", "_X46O5IeS",    "_YlCJ3lg",
        "_dku592fbFAj",     "_fdjkDSAFjklaf2s", "_lxpgvVMLd0S7uRl",
    };
    std::unordered_map<std::string, uint64_t> coreFPExports;
    for (const char* n : kCoreFPExportNames) {
        try { coreFPExports[n] = imgCoreFP->Export(n, kCoreFPBase); } catch (...) {}
    }
    try { coreFPExports["_get_mac_address"] = imgCommerceCore->Export("_get_mac_address", kCommerceBase); }
    catch (...) {}

    // 5. Create shims — pass hardwareID so _get_mac_address shim returns correct MAC
    m->shims_ = std::make_unique<SapShims>(m->uc_, std::move(coreFPExports), std::move(coreFPIcxs), std::move(hardwareID));
    m->shims_->SetHeap(kHeapBase, kHeapSize);

    // 6. Resolver: shims first, then cross-image
    auto resolver = [&](std::string_view name) -> uint64_t {
        return m->shims_->Resolve(name);
    };

    // 7. Relocate all images
    imgCoreFP      ->Relocate(kCoreFPBase,   resolver);
    imgCommerceCore->Relocate(kCommerceBase, resolver);
    imgCommerceKit ->Relocate(kKitBase,      resolver);

    // 8. Load into Unicorn memory
    imgCoreFP      ->Load(m->uc_);
    imgCommerceCore->Load(m->uc_);
    imgCommerceKit ->Load(m->uc_);

    // 9. Resolve CommerceKit entry points
    m->entry_.initialize = imgCommerceKit->Export("_cp2g1b9ro",   kKitBase);
    m->entry_.exchange   = imgCommerceKit->Export("_Mib5yocT",    kKitBase);
    m->entry_.sign       = imgCommerceKit->Export("_Fc3vhtJDvr",  kKitBase);
    m->entry_.teardown   = imgCommerceKit->Export("_IPaI1oem5iL", kKitBase);
    m->entry_.dispose    = imgCommerceKit->Export("_jEHf8Xzsv8K", kKitBase);

    return m;
}

SapMachine::~SapMachine() {
    shims_.reset();
    if (uc_) uc_close(uc_);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Invoke — x86-64 SysV ABI call into guest
// ═══════════════════════════════════════════════════════════════════════════

uint64_t SapMachine::Invoke(uint64_t fn, std::initializer_list<uint64_t> args) {
    if (!fn) throw std::runtime_error("SAP entry point is zero");

    shims_->BeforeInvoke();

    // Write register args
    int ri = 0;
    for (uint64_t a : args)
        if (ri < 6) UC_CHECK(uc_reg_write(uc_, kArgRegs[ri++], &a), "write arg reg");

    // Stack: align RSP to 16n+8 (as if after a CALL), push return address
    int extra = std::max(0, static_cast<int>(args.size()) - 6);
    uint64_t rsp = kStackEnd - uint64_t(extra + 1) * 8;
    if (rsp % 16 != 8) rsp -= 8;

    UC_CHECK(uc_mem_write(uc_, rsp, &kReturnAddr, 8), "push return addr");

    // Push extra stack args (rarely needed for our ≤8 arg entry points)
    {
        int si = 0;
        for (uint64_t a : args) {
            if (si++ < 6) continue;
            uint64_t slot = rsp + 8 + uint64_t(si - 7) * 8;
            UC_CHECK(uc_mem_write(uc_, slot, &a, 8), "push stack arg");
        }
    }

    UC_CHECK(uc_reg_write(uc_, UC_X86_REG_RSP, &rsp), "write RSP");

    // StartBounded: emulation stops when IP == kReturnAddr.
    // Unicorn accepts microseconds; the configured timeout is in milliseconds.
    uc_err err = uc_emu_start(uc_, fn, kReturnAddr, kTimeout * 1000, 0);

    if (err != UC_ERR_OK) {
        if (shims_->HasFault())
            throw std::runtime_error(shims_->TakeFault());
        throw std::runtime_error(std::format("uc_emu_start: {}", uc_strerror(err)));
    }

    if (shims_->HasFault())
        throw std::runtime_error(shims_->TakeFault());

    uint64_t rip = 0;
    UC_CHECK(uc_reg_read(uc_, UC_X86_REG_RIP, &rip), "read RIP");
    if (rip != kReturnAddr)
        throw std::runtime_error(std::format("guest stopped at {:#x}, expected {:#x}", rip, kReturnAddr));

    uint64_t rax = 0;
    UC_CHECK(uc_reg_read(uc_, UC_X86_REG_RAX, &rax), "read RAX");
    return rax;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Scratch helpers (clearScratch zeroes memory matching Go)
// ═══════════════════════════════════════════════════════════════════════════

uint64_t SapMachine::Scratch(const void* data, uint64_t len) {
    if (len > kScratchSize) throw std::runtime_error("scratch request exceeds limit");
    uint64_t reserved = AlignUp(std::max(len, uint64_t(1)), 16);
    if (scratchCursor_ > kScratchSize || reserved > kScratchSize - scratchCursor_)
        throw std::runtime_error("scratch exhausted");

    uint64_t addr = kScratchBase + scratchCursor_;
    scratchCursor_ += reserved;

    if (data && len) UC_CHECK(uc_mem_write(uc_, addr, data, len),      "scratch write");
    else if (len)    { std::vector<uint8_t> z(len,0); UC_CHECK(uc_mem_write(uc_, addr, z.data(), len), "scratch zero"); }
    return addr;
}

void SapMachine::ClearScratch() noexcept {
    const uint8_t zeros[4096] = {};
    for (uint64_t offset = 0; offset < scratchCursor_; offset += sizeof(zeros)) {
        const auto count = std::min(uint64_t(sizeof(zeros)), scratchCursor_ - offset);
        uc_mem_write(uc_, kScratchBase + offset, zeros, count);
    }
    scratchCursor_ = 0;
}

// ═══════════════════════════════════════════════════════════════════════════
//  SAP Protocol
// ═══════════════════════════════════════════════════════════════════════════

/*static*/ std::vector<uint8_t> SapMachine::HardwareBlock(std::span<const uint8_t> id) {
    if (id.empty() || id.size() > 20)
        throw std::runtime_error("hardware ID must be 1-20 bytes");
    std::vector<uint8_t> block(24, 0);
    uint32_t sz = static_cast<uint32_t>(id.size());
    std::memcpy(block.data(),     &sz,       4);
    std::memcpy(block.data() + 4, id.data(), id.size());
    return block;
}

uint64_t SapMachine::GuestRead64(uint64_t addr) {
    uint64_t v = 0; UC_CHECK(uc_mem_read(uc_, addr, &v, 8), "r64"); return v;
}
uint32_t SapMachine::GuestRead32(uint64_t addr) {
    uint32_t v = 0; UC_CHECK(uc_mem_read(uc_, addr, &v, 4), "r32"); return v;
}

std::vector<uint8_t> SapMachine::ConsumeOutput(uint64_t ptrFld, uint64_t lenFld) {
    uint64_t ptr = GuestRead64(ptrFld);
    uint64_t len = CheckedTransfer(GuestRead64(lenFld));
    if (len && !ptr) throw std::runtime_error("SAP output has a null pointer");
    std::vector<uint8_t> out;
    if (ptr && len) {
        out.resize(len);
        UC_CHECK(uc_mem_read(uc_, ptr, out.data(), len), "read output");
    }
    if (ptr) {
        int32_t st = static_cast<int32_t>(Invoke(entry_.dispose, { ptr }));
        (void)st; // non-fatal if dispose fails
    }
    return out;
}

uint64_t SapMachine::Initialize(std::span<const uint8_t> hwID) {
    auto hw = HardwareBlock(hwID);
    BeginCall();
    const ScratchCleanup cleanup{*this};
    uint64_t ctxFld = Scratch(8);
    uint64_t hwAddr = Scratch(hw.data(), hw.size());
    int32_t  status = static_cast<int32_t>(Invoke(entry_.initialize, { ctxFld, hwAddr }));
    uint64_t ctx    = GuestRead64(ctxFld);
    if (status != 0) throw std::runtime_error(std::format("Initialize returned {}", status));
    if (!ctx) throw std::runtime_error("Initialize returned null context");
    return ctx;
}

std::pair<std::vector<uint8_t>, int32_t>
SapMachine::Exchange(uint32_t version, std::span<const uint8_t> hwID,
                     uint64_t ctx, std::span<const uint8_t> input) {
    auto hw = HardwareBlock(hwID);
    BeginCall();
    const ScratchCleanup cleanup{*this};
    uint64_t hwAddr    = Scratch(hw.data(), hw.size());
    uint64_t inAddr    = Scratch(input.data(), input.size());
    uint64_t outPtrFld = Scratch(8);
    uint64_t outLenFld = Scratch(8);
    uint64_t resFld    = Scratch(4);

    int32_t status = static_cast<int32_t>(Invoke(entry_.exchange, {
        uint64_t(version), hwAddr, ctx,
        inAddr, uint64_t(input.size()),
        outPtrFld, outLenFld, resFld
    }));
    if (status != 0) throw std::runtime_error(std::format("Exchange returned {}", status));

    auto out = ConsumeOutput(outPtrFld, outLenFld);
    int32_t result = static_cast<int32_t>(GuestRead32(resFld));
    return { std::move(out), result };
}

std::vector<uint8_t> SapMachine::Sign(uint64_t ctx, std::span<const uint8_t> input) {
    BeginCall();
    const ScratchCleanup cleanup{*this};
    uint64_t inAddr    = Scratch(input.data(), input.size());
    uint64_t outPtrFld = Scratch(8);
    uint64_t outLenFld = Scratch(8);

    int32_t status = static_cast<int32_t>(Invoke(entry_.sign, {
        ctx, inAddr, uint64_t(input.size()), outPtrFld, outLenFld
    }));
    if (status != 0) throw std::runtime_error(std::format("Sign returned {}", status));

    auto sig = ConsumeOutput(outPtrFld, outLenFld);
    if (sig.empty()) throw std::runtime_error("Sign returned empty signature");
    return sig;
}

void SapMachine::Teardown(uint64_t ctx) {
    BeginCall();
    const ScratchCleanup cleanup{*this};
    int32_t st = static_cast<int32_t>(Invoke(entry_.teardown, { ctx }));
    if (st != 0) throw std::runtime_error(std::format("Teardown returned {}", st));
}
