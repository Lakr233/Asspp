#include "MachImage.h"
#include "SapMachine.h"
#include <unicorn/unicorn.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/machine.h>
#include <cassert>
#include <cstring>
#include <iostream>

template<class F> static void rejects(F body) {
    bool rejected = false;
    try { body(); } catch (const std::exception&) { rejected = true; }
    assert(rejected);
}

template<class T> static void append(std::vector<uint8_t>& bytes, const T& value) {
    const auto* begin = reinterpret_cast<const uint8_t*>(&value);
    bytes.insert(bytes.end(), begin, begin + sizeof(T));
}

static void malformedImages() {
    mach_header_64 header{};
    header.magic = MH_MAGIC_64;
    header.cputype = CPU_TYPE_X86_64;
    header.ncmds = 1;
    header.sizeofcmds = 4;
    std::vector<uint8_t> bytes;
    append(bytes, header);
    append(bytes, uint32_t(LC_SEGMENT_64));
    rejects([&] { MachImage::Open("truncated-command", bytes); });

    header.sizeofcmds = sizeof(load_command);
    bytes.clear(); append(bytes, header);
    append(bytes, load_command{LC_SEGMENT_64, sizeof(load_command)});
    rejects([&] { MachImage::Open("truncated-segment", bytes); });

    header.sizeofcmds = sizeof(symtab_command);
    bytes.clear(); append(bytes, header);
    symtab_command symbols{};
    symbols.cmd = LC_SYMTAB; symbols.cmdsize = sizeof(symbols);
    symbols.symoff = sizeof(header) + sizeof(symbols);
    symbols.nsyms = 1; symbols.stroff = symbols.symoff + sizeof(nlist_64);
    symbols.strsize = 3;
    append(bytes, symbols);
    nlist_64 symbol{};
    symbol.n_un.n_strx = 1; symbol.n_type = N_SECT | N_EXT; symbol.n_value = 1;
    append(bytes, symbol);
    bytes.insert(bytes.end(), {0, 'x', 'y'});
    rejects([&] { MachImage::Open("unterminated-symbol", bytes); });

    header.sizeofcmds = UINT32_MAX;
    bytes.clear(); append(bytes, header);
    rejects([&] { MachImage::Open("overflowing-commands", bytes); });
}

int main() {
    malformedImages();
    uc_engine* engine = nullptr;
    assert(uc_open(UC_ARCH_X86, UC_MODE_64, &engine) == UC_ERR_OK);
    {
        constexpr uint64_t heap = 0x10000000, stack = 0x20000000, stop = 0x30000000;
        assert(uc_mem_map(engine, heap, 64 * 1024 * 1024, UC_PROT_ALL) == UC_ERR_OK);
        assert(uc_mem_map(engine, stack, 4096, UC_PROT_ALL) == UC_ERR_OK);
        assert(uc_mem_map(engine, stop, 4096, UC_PROT_ALL) == UC_ERR_OK);
        SapShims shims(engine, {}, {}, {2, 0x41, 0x53, 0x53, 0x50, 0x50});
        shims.SetHeap(heap, 64 * 1024 * 1024);
        auto invoke = [&](const char* name, std::initializer_list<uint64_t> args) {
            shims.BeforeInvoke();
            const uint64_t entry = shims.Resolve(name);
            const int registers[] = {UC_X86_REG_RDI, UC_X86_REG_RSI, UC_X86_REG_RDX, UC_X86_REG_RCX};
            size_t index = 0;
            for (uint64_t value : args) assert(uc_reg_write(engine, registers[index++], &value) == UC_ERR_OK);
            uint64_t rsp = stack + 4096 - 8;
            assert(uc_mem_write(engine, rsp, &stop, 8) == UC_ERR_OK);
            assert(uc_reg_write(engine, UC_X86_REG_RSP, &rsp) == UC_ERR_OK);
            assert(uc_emu_start(engine, entry, stop, 1'000'000, 1000) == UC_ERR_OK);
            if (shims.HasFault()) throw std::runtime_error(shims.TakeFault());
            uint64_t result = 0;
            assert(uc_reg_read(engine, UC_X86_REG_RAX, &result) == UC_ERR_OK);
            return result;
        };
        std::vector<uint64_t> blocks;
        for (int i = 0; i < 512; ++i) {
            const uint64_t original = invoke("_malloc", {8});
            const uint64_t marker = 0x12345678 + i;
            assert(uc_mem_write(engine, original, &marker, 8) == UC_ERR_OK);
            const uint64_t resized = invoke("_realloc", {original, 128});
            uint64_t actual = 0;
            assert(uc_mem_read(engine, resized, &actual, 8) == UC_ERR_OK && actual == marker);
            blocks.push_back(resized);
        }
        for (auto block : blocks) invoke("_free", {block});
        rejects([&] { invoke("_calloc", {UINT64_MAX, 2}); });
        rejects([&] { invoke("_memcpy", {heap, heap, UINT64_MAX}); });
        rejects([&] { invoke("_memset", {heap, 0, UINT64_MAX}); });
        rejects([&] { invoke("_unsupported_test_import", {}); });
    }
    assert(uc_close(engine) == UC_ERR_OK);
    std::cout << "SAP runtime regression checks passed.\n";
}
