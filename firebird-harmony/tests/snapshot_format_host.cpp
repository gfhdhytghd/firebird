#include <cassert>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

#include <zlib.h>

#include "../entry/src/main/cpp/snapshot/snapshot_format.h"

namespace {
#pragma pack(push, 1)
struct CoreHeader {
    uint32_t magic = 0xCAFEBEE0;
    uint32_t version = 3;
    char bootPath[512] {};
    char flashPath[512] {};
};

struct LegacyNandMetrics {
    uint8_t chipManufacturer = 0xEC;
    uint8_t chipModel = 0xA1;
    uint16_t pageSize = 0x840;
    uint8_t log2PagesPerBlock = 6;
    uint8_t padding[3] {};
    uint32_t pageCount = 0x10000;
};

struct HarmonyHeaderV4 {
    uint32_t magic = 0x53484246;
    uint32_t version = 4;
    uint32_t headerSize = sizeof(HarmonyHeaderV4);
    uint32_t product = 0x1C0;
    uint64_t bootFingerprint = 1;
    uint64_t flashFingerprint = 2;
    uint64_t payloadSize = 0;
    char bootId[24] {};
    char flashId[24] {};
};
#pragma pack(pop)
}

int main()
{
    const auto root = std::filesystem::temp_directory_path() / "firebird-harmony-snapshot-test";
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root);
    const auto boot = root / "boot";
    const auto flash = root / "flash";
    std::ofstream(boot, std::ios::binary) << "boot";
    std::ofstream(flash, std::ios::binary) << "flash";

    const auto core = root / "core.snapshot";
    gzFile output = gzopen(core.c_str(), "wb");
    CoreHeader header;
    std::strcpy(header.bootPath, "/private/source/boot");
    std::strcpy(header.flashPath, "/private/source/flash");
    assert(gzwrite(output, &header, sizeof(header)) == sizeof(header));
    LegacyNandMetrics metrics;
    assert(gzwrite(output, &metrics, sizeof(metrics)) == sizeof(metrics));
    const char payload[] = "payload";
    assert(gzwrite(output, payload, sizeof(payload)) == sizeof(payload));
    assert(gzclose(output) == Z_OK);

    SnapshotInfo legacy = InspectSnapshot(core.string());
    assert(legacy.valid && !legacy.harmonyFormat && legacy.version == 3);

    const auto wrapped = root / "wrapped.fbhs";
    std::string error;
    assert(WrapHarmonySnapshot(core.string(), wrapped.string(), 0x1C0,
                               boot.string(), flash.string(), error));
    SnapshotInfo info = InspectSnapshot(wrapped.string());
    assert(info.valid && info.harmonyFormat && info.version == 5 && info.product == 0x1C0);
    assert(info.bootFingerprint != 0 && info.flashFingerprint != 0);
    assert(info.embeddedFlash && info.flashPayloadSize == 5);
    assert(ValidateEmbeddedFlash(wrapped.string(), error));

    const auto restored = root / "restored.snapshot";
    assert(UnwrapHarmonySnapshot(wrapped.string(), restored.string(), error));
    assert(std::filesystem::file_size(core) == std::filesystem::file_size(restored));

    const auto restoredFlash = root / "restored.flash";
    assert(RestoreEmbeddedFlash(wrapped.string(), restoredFlash.string(), error));
    assert(FingerprintFile(restoredFlash.string(), error) == info.flashFingerprint);

    const auto legacyWrapper = root / "legacy-v4.fbhs";
    HarmonyHeaderV4 legacyHeader;
    legacyHeader.payloadSize = std::filesystem::file_size(core);
    std::ofstream legacyOutput(legacyWrapper, std::ios::binary);
    legacyOutput.write(reinterpret_cast<const char *>(&legacyHeader), sizeof(legacyHeader));
    std::ifstream coreInput(core, std::ios::binary);
    legacyOutput << coreInput.rdbuf();
    legacyOutput.close();
    SnapshotInfo legacyInfo = InspectSnapshot(legacyWrapper.string());
    assert(legacyInfo.valid && legacyInfo.harmonyFormat && legacyInfo.version == 4);
    assert(!legacyInfo.embeddedFlash && legacyInfo.corePayloadSize == legacyHeader.payloadSize);

    const auto corrupt = root / "corrupt.fbhs";
    std::filesystem::copy_file(wrapped, corrupt);
    std::fstream corruptStream(corrupt, std::ios::binary | std::ios::in | std::ios::out);
    corruptStream.seekp(-1, std::ios::end);
    const char damaged = '\0';
    corruptStream.write(&damaged, 1);
    corruptStream.close();
    error.clear();
    assert(!ValidateEmbeddedFlash(corrupt.string(), error));
    assert(error.find("fingerprint") != std::string::npos);

    const auto wrongGeometry = root / "wrong-geometry.snapshot";
    output = gzopen(wrongGeometry.c_str(), "wb");
    assert(gzwrite(output, &header, sizeof(header)) == sizeof(header));
    metrics.pageSize = 0x210;
    assert(gzwrite(output, &metrics, sizeof(metrics)) == sizeof(metrics));
    assert(gzclose(output) == Z_OK);
    SnapshotInfo rejected = InspectSnapshot(wrongGeometry.string());
    assert(!rejected.valid && rejected.error.find("CX II") != std::string::npos);
    std::filesystem::remove_all(root);
    return 0;
}
