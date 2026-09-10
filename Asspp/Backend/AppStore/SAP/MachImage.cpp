// Adapted from Sorvigolova/ipatool; see Resources/Licenses/ipatool.txt.
#include "MachImage.h"

#include <unicorn/unicorn.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/machine.h>
#include <bit>

#include <algorithm>
#include <cassert>
#include <cstring>
#include <format>
#include <span>
#include <stdexcept>

// Use the SDK Mach-O definitions on every supported Darwin target.

static constexpr uint64_t POINTER_SIZE  = 8;
static constexpr uint64_t PAGE_SIZE     = 0x1000;
static constexpr uint64_t MAX_IMG_SPAN = uint64_t(256) << 20;

// ─── helpers ─────────────────────────────────────────────────────────────────

static inline uint32_t bswap32(uint32_t v) {
    return ((v & 0xFF000000u) >> 24) | ((v & 0x00FF0000u) >> 8)
         | ((v & 0x0000FF00u) <<  8) | ((v & 0x000000FFu) << 24);
}

static uint64_t ReadULEB128(const uint8_t*& p, const uint8_t* end) {
    uint64_t value = 0;
    for (int shift = 0; shift < 64 && p < end; shift += 7) {
        const uint8_t byte = *p++;
        if (shift == 63 && (byte & 0x7E)) throw std::runtime_error("ULEB128 overflow");
        value |= uint64_t(byte & 0x7F) << shift;
        if (!(byte & 0x80)) return value;
    }
    throw std::runtime_error("Truncated or overflowing ULEB128");
}

static int64_t ReadSLEB128(const uint8_t*& p, const uint8_t* end) {
    uint64_t value = 0;
    for (int shift = 0; shift < 64 && p < end; shift += 7) {
        const uint8_t byte = *p++;
        const uint8_t bits = byte & 0x7F;
        if (shift == 63 && bits != 0 && bits != 0x7F) throw std::runtime_error("SLEB128 overflow");
        value |= uint64_t(bits) << shift;
        if (!(byte & 0x80)) {
            if (shift < 57 && (byte & 0x40)) value |= UINT64_MAX << (shift + 7);
            return std::bit_cast<int64_t>(value);
        }
    }
    throw std::runtime_error("Truncated or overflowing SLEB128");
}

static std::string ReadCString(const char* text, size_t remaining) {
    const size_t length = strnlen(text, remaining);
    if (length == remaining) throw std::runtime_error("Unterminated Mach-O string");
    return std::string(text, length);
}

static inline uint64_t AlignUp(uint64_t v, uint64_t a) {
    return (v + a - 1) & ~(a - 1);
}

// ─── Open ─────────────────────────────────────────────────────────────────────

std::unique_ptr<MachImage> MachImage::Open(std::string name, std::vector<uint8_t> data) {
    if (data.size() < 4)
        throw std::runtime_error(std::format("MachImage::Open({}): file too small", name));

    auto img = std::unique_ptr<MachImage>(new MachImage());
    img->name_ = std::move(name);

    // Fat binary? (big-endian magic)
    uint32_t magic;
    std::memcpy(&magic, data.data(), 4);
    if (magic == FAT_MAGIC || magic == FAT_CIGAM)
        img->data_ = ExtractAmd64Slice(data);
    else
        img->data_ = std::move(data);

    img->ParseLoadCommands();
    return img;
}

// ─── ExtractAmd64Slice ────────────────────────────────────────────────────────

std::vector<uint8_t> MachImage::ExtractAmd64Slice(const std::vector<uint8_t>& fat) {
    if (fat.size() < sizeof(fat_header))
        throw std::runtime_error("Fat binary: too small for header");

    fat_header hdr;
    std::memcpy(&hdr, fat.data(), sizeof(hdr));
    // Fat header is big-endian
    uint32_t narch = bswap32(hdr.nfat_arch);

    const uint8_t* p = fat.data() + sizeof(fat_header);
    for (uint32_t i = 0; i < narch; ++i) {
        if (size_t(fat.data() + fat.size() - p) < sizeof(fat_arch))
            throw std::runtime_error("Fat binary: arch table truncated");
        fat_arch arch;
        std::memcpy(&arch, p, sizeof(arch));
        p += sizeof(fat_arch);

        uint32_t cpu    = bswap32(arch.cputype);
        uint32_t offset = bswap32(arch.offset);
        uint32_t size   = bswap32(arch.size);

        if (cpu != CPU_TYPE_X86_64) continue;

        if (uint64_t(offset) + size > fat.size())
            throw std::runtime_error("Fat binary: x86-64 slice out of bounds");

        return std::vector<uint8_t>(fat.data() + offset,
                                    fat.data() + offset + size);
    }
    throw std::runtime_error("Fat binary has no x86-64 slice");
}

// ─── ParseLoadCommands ────────────────────────────────────────────────────────

void MachImage::ParseLoadCommands() {
    const uint8_t* base = data_.data();
    size_t total        = data_.size();

    if (total < sizeof(mach_header_64))
        throw std::runtime_error(std::format("{}: too small", name_));

    mach_header_64 mh;
    std::memcpy(&mh, base, sizeof(mh));

    if (mh.magic != MH_MAGIC_64)
        throw std::runtime_error(std::format("{}: not a 64-bit Mach-O (magic={:#x})", name_, mh.magic));
    if (mh.cputype != CPU_TYPE_X86_64)
        throw std::runtime_error(std::format("{}: not x86-64", name_));

    const uint8_t* lc_ptr = base + sizeof(mach_header_64);
    if (mh.sizeofcmds > total - sizeof(mach_header_64))
        throw std::runtime_error(std::format("{}: load commands extend past file", name_));
    const uint8_t* lc_end = lc_ptr + mh.sizeofcmds;
    uint32_t commandCount = 0;

    // Pointers to deferred sections (export trie, dyld info, symtab)
    const uint8_t* rebaseOpcodes    = nullptr; uint32_t rebaseSize    = 0;
    const uint8_t* bindOpcodes      = nullptr; uint32_t bindSize      = 0;
    const uint8_t* lazyBindOpcodes  = nullptr; uint32_t lazyBindSize  = 0;
    const uint8_t* exportTrie       = nullptr; uint32_t exportTrieSize = 0;
    const uint8_t* symtabSyms       = nullptr; uint32_t symtabNsyms   = 0;
    const char*    symtabStrtab     = nullptr; uint32_t symtabStrsize  = 0;

    bool firstText = true;

    while (lc_ptr < lc_end) {
        if (size_t(lc_end - lc_ptr) < sizeof(load_command)) throw std::runtime_error("Truncated load command");
        ++commandCount;
        load_command lc;
        std::memcpy(&lc, lc_ptr, sizeof(lc));

        if (lc.cmdsize < sizeof(load_command) || lc.cmdsize > size_t(lc_end - lc_ptr))
            throw std::runtime_error(std::format("{}: malformed load command", name_));

        if (lc.cmd == LC_SEGMENT_64) {
            if (lc.cmdsize < sizeof(segment_command_64)) throw std::runtime_error("Truncated Mach-O command payload");
            segment_command_64 sc;
            std::memcpy(&sc, lc_ptr, sizeof(sc));

            Segment seg;
            seg.name.assign(sc.segname, strnlen(sc.segname, 16));
            seg.vmAddr   = sc.vmaddr;
            seg.vmSize   = sc.vmsize;
            seg.fileOff  = sc.fileoff;
            seg.fileSize = sc.filesize;

            // Validate
            if (seg.fileSize > seg.vmSize)
                throw std::runtime_error(std::format("{}: segment {} file > mem", name_, seg.name));
            if (seg.fileOff > total || seg.fileSize > total - seg.fileOff)
                throw std::runtime_error(std::format("{}: segment {} beyond EOF", name_, seg.name));

            // Image base = vmaddr of first non-__PAGEZERO segment
            if (firstText && seg.name != "__PAGEZERO") {
                imageBase_ = seg.vmAddr;
                firstText  = false;
            }

            segments_.push_back(std::move(seg));
        }
        else if (lc.cmd == LC_DYLD_INFO || lc.cmd == LC_DYLD_INFO_ONLY) {
            if (lc.cmdsize < sizeof(dyld_info_command)) throw std::runtime_error("Truncated Mach-O command payload");
            dyld_info_command di;
            std::memcpy(&di, lc_ptr, sizeof(di));

            auto SafePtr = [&](uint32_t off, uint32_t sz) -> const uint8_t* {
                if (sz == 0) return nullptr;
                if (uint64_t(off) + sz > total)
                    throw std::runtime_error(std::format("{}: dyld_info out of bounds", name_));
                return base + off;
            };

            rebaseOpcodes   = SafePtr(di.rebase_off, di.rebase_size);
            rebaseSize      = di.rebase_size;
            bindOpcodes     = SafePtr(di.bind_off, di.bind_size);
            bindSize        = di.bind_size;
            lazyBindOpcodes = SafePtr(di.lazy_bind_off, di.lazy_bind_size);
            lazyBindSize    = di.lazy_bind_size;
            exportTrie      = SafePtr(di.export_off, di.export_size);
            exportTrieSize  = di.export_size;
        }
        else if (lc.cmd == LC_DYLD_EXPORTS_TRIE) {
            if (lc.cmdsize < sizeof(linkedit_data_command)) throw std::runtime_error("Truncated Mach-O command payload");
            linkedit_data_command led;
            std::memcpy(&led, lc_ptr, sizeof(led));
            if (led.datasize > 0 && uint64_t(led.dataoff) + led.datasize <= total) {
                exportTrie     = base + led.dataoff;
                exportTrieSize = led.datasize;
            }
        }
        else if (lc.cmd == LC_SYMTAB) {
            if (lc.cmdsize < sizeof(symtab_command)) throw std::runtime_error("Truncated Mach-O command payload");
            symtab_command sc;
            std::memcpy(&sc, lc_ptr, sizeof(sc));
            if (sc.nsyms > 0 && uint64_t(sc.symoff) + sc.nsyms * sizeof(nlist_64) <= total) {
                symtabSyms   = base + sc.symoff;
                symtabNsyms  = sc.nsyms;
            }
            if (sc.strsize > 0 && uint64_t(sc.stroff) + sc.strsize <= total) {
                symtabStrtab  = reinterpret_cast<const char*>(base + sc.stroff);
                symtabStrsize = sc.strsize;
            }
        }

        lc_ptr += lc.cmdsize;
    }

    if (commandCount != mh.ncmds) throw std::runtime_error("Mach-O load command count mismatch");

    // Parse deferred sections
    if (rebaseOpcodes) ParseRebaseOpcodes(rebaseOpcodes, rebaseSize);
    if (bindOpcodes)   ParseBindOpcodes(bindOpcodes,   bindSize,  /*isLazy=*/false);
    if (lazyBindOpcodes) ParseBindOpcodes(lazyBindOpcodes, lazyBindSize, /*isLazy=*/true);
    if (exportTrie)    ParseExportTrie(exportTrie, exportTrieSize);
    if (symtabSyms && symtabStrtab)
        ParseSymtab(symtabSyms, symtabNsyms, symtabStrtab, symtabStrsize);
}

// ─── ParseRebaseOpcodes ───────────────────────────────────────────────────────

void MachImage::ParseRebaseOpcodes(const uint8_t* start, size_t len) {
    const uint8_t* p   = start;
    const uint8_t* end = start + len;

    uint8_t  type    = 0;
    int      segIdx  = -1;
    uint64_t offset  = 0;

    auto CurrentSegName = [&]() -> const std::string& {
        if (segIdx < 0 || segIdx >= static_cast<int>(segments_.size()))
            throw std::runtime_error(std::format("{}: rebase: invalid segment index {}", name_, segIdx));
        return segments_[segIdx].name;
    };

    auto EmitRebase = [&]() {
        if (type != 1 /*REBASE_TYPE_POINTER*/)
            throw std::runtime_error(std::format("{}: unsupported rebase type {}", name_, type));
        // Read original pointer value from data[]
        uint64_t fileOff = SegmentFileOffset(CurrentSegName(), offset, POINTER_SIZE);
        uint64_t origVal = ReadPointer(fileOff);
        rebases_.push_back({ CurrentSegName(), offset, origVal });
    };

    while (p < end) {
        uint8_t b      = *p++;
        uint8_t opcode = b & REBASE_OPCODE_MASK;
        uint8_t imm    = b & REBASE_IMMEDIATE_MASK;

        switch (opcode) {
        case REBASE_OPCODE_DONE:
            return;
        case REBASE_OPCODE_SET_TYPE_IMM:
            type = imm;
            break;
        case REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            segIdx = imm;
            offset = ReadULEB128(p, end);
            break;
        case REBASE_OPCODE_ADD_ADDR_ULEB:
            offset += ReadULEB128(p, end);
            break;
        case REBASE_OPCODE_ADD_ADDR_IMM_SCALED:
            offset += imm * POINTER_SIZE;
            break;
        case REBASE_OPCODE_DO_REBASE_IMM_TIMES:
            for (uint8_t i = 0; i < imm; ++i) { EmitRebase(); offset += POINTER_SIZE; }
            break;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES: {
            uint64_t count = ReadULEB128(p, end);
            for (uint64_t i = 0; i < count; ++i) { EmitRebase(); offset += POINTER_SIZE; }
            break;
        }
        case REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB:
            EmitRebase();
            offset += POINTER_SIZE + ReadULEB128(p, end);
            break;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB: {
            uint64_t count = ReadULEB128(p, end);
            uint64_t skip  = ReadULEB128(p, end);
            for (uint64_t i = 0; i < count; ++i) { EmitRebase(); offset += POINTER_SIZE + skip; }
            break;
        }
        default:
            throw std::runtime_error(std::format("{}: unknown rebase opcode {:#x}", name_, opcode));
        }
    }
}

// ─── ParseBindOpcodes ─────────────────────────────────────────────────────────

void MachImage::ParseBindOpcodes(const uint8_t* start, size_t len, bool isLazy) {
    const uint8_t* p   = start;
    const uint8_t* end = start + len;

    int         segIdx  = -1;
    uint64_t    offset  = 0;
    std::string symName;
    int64_t     addend  = 0;
    // type/ordinal are tracked but not stored (we only support pointer binds)

    auto CurrentSegName = [&]() -> const std::string& {
        if (segIdx < 0 || segIdx >= static_cast<int>(segments_.size()))
            throw std::runtime_error(std::format("{}: bind: invalid segment {}", name_, segIdx));
        return segments_[segIdx].name;
    };

    auto EmitBind = [&]() {
        if (symName.empty())
            throw std::runtime_error(std::format("{}: bind: empty symbol name", name_));
        binds_.push_back({ CurrentSegName(), offset, symName, addend });
    };

    while (p < end) {
        uint8_t b      = *p++;
        uint8_t opcode = b & BIND_OPCODE_MASK;
        uint8_t imm    = b & BIND_IMMEDIATE_MASK;

        switch (opcode) {
        case BIND_OPCODE_DONE:
            if (!isLazy) return;
            // Lazy bind: DONE ends one symbol's record, stream continues.
            // Reset per-record state so the next entry starts clean.
            segIdx  = -1;
            offset  = 0;
            symName.clear();
            addend  = 0;
            break;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
        case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
            // We don't validate the library ordinal — all symbols route through resolve()
            break;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
            ReadULEB128(p, end); // consume, ignore
            break;
        case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM: {
            // NUL-terminated symbol name follows
            const char* s = reinterpret_cast<const char*>(p);
            symName = ReadCString(s, end - p);
            p += symName.size() + 1;
            break;
        }
        case BIND_OPCODE_SET_TYPE_IMM:
            // imm == 1 (pointer) — only type we support; others would throw in Relocate
            break;
        case BIND_OPCODE_SET_ADDEND_SLEB:
            addend = ReadSLEB128(p, end);
            break;
        case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            segIdx = imm;
            offset = ReadULEB128(p, end);
            break;
        case BIND_OPCODE_ADD_ADDR_ULEB:
            offset += ReadULEB128(p, end);
            break;
        case BIND_OPCODE_DO_BIND:
            EmitBind(); offset += POINTER_SIZE;
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB:
            EmitBind(); offset += POINTER_SIZE + ReadULEB128(p, end);
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
            EmitBind(); offset += POINTER_SIZE + imm * POINTER_SIZE;
            break;
        case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: {
            uint64_t count = ReadULEB128(p, end);
            uint64_t skip  = ReadULEB128(p, end);
            for (uint64_t i = 0; i < count; ++i) { EmitBind(); offset += POINTER_SIZE + skip; }
            break;
        }
        default:
            throw std::runtime_error(std::format("{}: unknown bind opcode {:#x}", name_, opcode));
        }
    }
}

// ─── ParseExportTrie ─────────────────────────────────────────────────────────

void MachImage::ParseExportTrie(const uint8_t* trie, size_t len) {
    std::string prefix;
    WalkTrie(trie, len, 0, prefix);
}

void MachImage::WalkTrie(const uint8_t* trie, size_t len,
                          size_t nodeOff, std::string& prefix, size_t depth) {
    if (nodeOff >= len || depth > 128 || prefix.size() > 4096)
        throw std::runtime_error("Invalid or cyclic Mach-O export trie");

    const uint8_t* p   = trie + nodeOff;
    const uint8_t* end = trie + len;

    // Terminal size ULEB128
    uint64_t termSize = ReadULEB128(p, end);
    if (termSize > uint64_t(end - p)) throw std::runtime_error("Truncated export trie terminal");
    if (termSize != 0) {
        // Exported: read flags and address
        const uint8_t* tp  = p;
        const uint8_t* te  = p + termSize;
        uint64_t flags     = ReadULEB128(tp, te);
        (void)flags;
        uint64_t addr      = ReadULEB128(tp, te);
        // addr is relative to image base (in-image vmAddr)
        exports_[prefix]   = imageBase_ + addr;
    }

    p += termSize;
    if (p >= end) return;

    uint8_t childCount = *p++;
    for (uint8_t i = 0; i < childCount; ++i) {
        // Edge label: NUL-terminated string
        const char* label = reinterpret_cast<const char*>(p);
        size_t labLen = ReadCString(label, end - p).size();
        p += labLen + 1;

        // Child node offset ULEB128
        uint64_t childOff = ReadULEB128(p, end);

        // Recurse
        size_t prevLen = prefix.size();
        prefix.append(label, labLen);
        WalkTrie(trie, len, static_cast<size_t>(childOff), prefix, depth + 1);
        prefix.resize(prevLen);
    }
}

// ─── ParseSymtab (fallback) ──────────────────────────────────────────────────

void MachImage::ParseSymtab(const uint8_t* syms, uint32_t nsyms,
                              const char* strtab, uint32_t strsize) {
    for (uint32_t i = 0; i < nsyms; ++i) {
        nlist_64 nl;
        std::memcpy(&nl, syms + i * sizeof(nlist_64), sizeof(nl));

        // Skip stabs, undefined, and non-external
        if ((nl.n_type & N_TYPE) != N_SECT) continue;
        if (!(nl.n_type & N_EXT)) continue;
        if (nl.n_value == 0) continue;
        if (nl.n_un.n_strx == 0 || nl.n_un.n_strx >= strsize) continue;

        std::string sym = ReadCString(strtab + nl.n_un.n_strx, strsize - nl.n_un.n_strx);
        if (exports_.count(sym) == 0)          // trie wins if both present
            exports_[std::move(sym)] = nl.n_value;
    }
}

// ─── Export ──────────────────────────────────────────────────────────────────

uint64_t MachImage::Export(std::string_view symbol, uint64_t loadBase) const {
    auto it = exports_.find(std::string(symbol));
    if (it == exports_.end())
        throw std::runtime_error(std::format("{}: symbol not found: {}", name_, symbol));

    uint64_t vmAddr = it->second;
    if (vmAddr < imageBase_)
        throw std::runtime_error(std::format("{}: symbol {} precedes image base", name_, symbol));

    return loadBase + (vmAddr - imageBase_);
}

// ─── Relocate ────────────────────────────────────────────────────────────────

void MachImage::Relocate(uint64_t loadBase,
                          std::function<uint64_t(std::string_view)> resolve) {
    if (relocated_)
        throw std::runtime_error(std::format("{}: already relocated", name_));

    // Apply rebases: pointer value is currently in-image vmAddr, slide it.
    for (const auto& r : rebases_) {
        if (r.origValue < imageBase_)
            throw std::runtime_error(std::format("{}: rebase value below image base", name_));

        uint64_t newAddr = loadBase + (r.origValue - imageBase_);
        uint64_t fileOff = SegmentFileOffset(r.segment, r.offset, POINTER_SIZE);
        PutPointer(fileOff, newAddr);
    }

    // Apply binds: resolve external symbol, apply addend, write pointer.
    for (const auto& b : binds_) {
        uint64_t symAddr = resolve(b.symbolName);

        // Apply signed addend
        uint64_t finalAddr;
        if (b.addend >= 0) {
            finalAddr = symAddr + static_cast<uint64_t>(b.addend);
        } else {
            uint64_t mag = static_cast<uint64_t>(-(b.addend + 1)) + 1;
            if (mag > symAddr)
                throw std::runtime_error(std::format("{}: bind addend underflow for {}", name_, b.symbolName));
            finalAddr = symAddr - mag;
        }

        uint64_t fileOff = SegmentFileOffset(b.segment, b.segOffset, POINTER_SIZE);
        PutPointer(fileOff, finalAddr);
    }

    relocated_   = true;
    loadedBase_  = loadBase;
}

// ─── Load ─────────────────────────────────────────────────────────────────────

void MachImage::Load(uc_engine* uc) const {
    if (!relocated_)
        throw std::runtime_error(std::format("{}: must be relocated before Load()", name_));

    // Calculate span: max (vmAddr + vmSize - imageBase) over all loadable segments.
    uint64_t span = 0;
    for (const auto& s : segments_) {
        if (s.name == "__PAGEZERO" || s.vmSize == 0) continue;
        if (s.vmAddr < imageBase_)
            throw std::runtime_error(std::format("{}: segment {} below image base", name_, s.name));
        const uint64_t offset = s.vmAddr - imageBase_;
        if (offset > MAX_IMG_SPAN || s.vmSize > MAX_IMG_SPAN - offset)
            throw std::runtime_error("Mach-O image exceeds mapping limit");
        span = std::max(span, offset + s.vmSize);
    }
    span = AlignUp(span, PAGE_SIZE);
    if (span == 0)
        throw std::runtime_error(std::format("{}: no loadable segments", name_));

    uc_err err = uc_mem_map(uc, loadedBase_, span, UC_PROT_ALL);
    if (err != UC_ERR_OK)
        throw std::runtime_error(std::format("{}: uc_mem_map failed: {}", name_, uc_strerror(err)));

    for (const auto& s : segments_) {
        if (s.name == "__PAGEZERO" || s.fileSize == 0) continue;

        uint64_t guestAddr = loadedBase_ + (s.vmAddr - imageBase_);
        err = uc_mem_write(uc, guestAddr,
                           data_.data() + s.fileOff, s.fileSize);
        if (err != UC_ERR_OK)
            throw std::runtime_error(std::format("{}: uc_mem_write segment {} failed: {}",
                                                  name_, s.name, uc_strerror(err)));
    }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

uint64_t MachImage::SegmentFileOffset(std::string_view segName,
                                       uint64_t offset, uint64_t size) const {
    for (const auto& s : segments_) {
        if (s.name != segName) continue;

        if (offset > s.vmSize || size > s.vmSize - offset)
            throw std::runtime_error(std::format("{}: fixup at {:#x} exceeds segment {}",
                                                  name_, offset, segName));
        if (offset > s.fileSize || size > s.fileSize - offset)
            throw std::runtime_error(std::format("{}: fixup at {:#x} past file data in {}",
                                                  name_, offset, segName));

        uint64_t result = s.fileOff + offset;
        if (result > data_.size() || size > data_.size() - result)
            throw std::runtime_error(std::format("{}: fixup at {:#x} beyond EOF", name_, result));

        return result;
    }
    throw std::runtime_error(std::format("{}: fixup references unknown segment {}", name_, segName));
}

void MachImage::PutPointer(uint64_t fileOffset, uint64_t value) {
    if (fileOffset > data_.size() || 8 > data_.size() - fileOffset)
        throw std::runtime_error(std::format("{}: PutPointer at {:#x} beyond EOF", name_, fileOffset));
    std::memcpy(data_.data() + fileOffset, &value, 8);
}

uint64_t MachImage::ReadPointer(uint64_t fileOffset) const {
    if (fileOffset > data_.size() || 8 > data_.size() - fileOffset)
        throw std::runtime_error(std::format("{}: ReadPointer at {:#x} beyond EOF", name_, fileOffset));
    uint64_t v;
    std::memcpy(&v, data_.data() + fileOffset, 8);
    return v;
}
