#include "snapshot_format.h"

#include <array>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>

#include <zlib.h>

namespace {
constexpr uint32_t HARMONY_MAGIC = 0x53484246; // "FBHS" little endian
constexpr uint32_t HARMONY_VERSION = 5;
constexpr uint32_t HARMONY_VERSION_V4 = 4;
constexpr uint32_t CORE_MAGIC = 0xCAFEBEE0;
constexpr uint32_t CORE_VERSION = 3;

#pragma pack(push, 1)
struct HarmonyHeaderV4 {
    uint32_t magic;
    uint32_t version;
    uint32_t headerSize;
    uint32_t product;
    uint64_t bootFingerprint;
    uint64_t flashFingerprint;
    uint64_t payloadSize;
    char bootId[24];
    char flashId[24];
};

struct HarmonyHeader {
    uint32_t magic;
    uint32_t version;
    uint32_t headerSize;
    uint32_t product;
    uint64_t bootFingerprint;
    uint64_t flashFingerprint;
    uint64_t corePayloadSize;
    uint64_t flashPayloadSize;
    char bootId[24];
    char flashId[24];
};

struct CoreHeader {
    uint32_t magic;
    uint32_t version;
    char bootPath[512];
    char flashPath[512];
};

struct LegacyNandMetrics {
    uint8_t chipManufacturer;
    uint8_t chipModel;
    uint16_t pageSize;
    uint8_t log2PagesPerBlock;
    uint8_t padding[3];
    uint32_t pageCount;
};
#pragma pack(pop)

bool IsCx2Geometry(const LegacyNandMetrics &metrics)
{
    return metrics.chipManufacturer == 0xEC && metrics.chipModel == 0xA1 &&
           metrics.pageSize == 0x840 && metrics.log2PagesPerBlock == 6 &&
           metrics.pageCount == 0x10000;
}

bool CopyBytes(std::istream &input, std::ostream &output, uint64_t bytes, std::string &error)
{
    std::array<char, 64 * 1024> buffer {};
    while (bytes > 0) {
        const std::streamsize requested = static_cast<std::streamsize>(
            std::min<uint64_t>(bytes, buffer.size()));
        input.read(buffer.data(), requested);
        if (input.gcount() != requested) {
            error = "Snapshot payload is truncated";
            return false;
        }
        output.write(buffer.data(), requested);
        if (!output) {
            error = "Could not write snapshot payload";
            return false;
        }
        bytes -= static_cast<uint64_t>(requested);
    }
    return true;
}

uint64_t FingerprintBytes(std::istream &input, uint64_t bytes, std::ostream *output,
                          std::string &error)
{
    uint64_t hash = 1469598103934665603ull;
    std::array<char, 64 * 1024> buffer {};
    while (bytes > 0) {
        const std::streamsize requested = static_cast<std::streamsize>(
            std::min<uint64_t>(bytes, buffer.size()));
        input.read(buffer.data(), requested);
        if (input.gcount() != requested) {
            error = "Embedded flash payload is truncated";
            return 0;
        }
        for (std::streamsize i = 0; i < requested; ++i) {
            hash ^= static_cast<unsigned char>(buffer[static_cast<size_t>(i)]);
            hash *= 1099511628211ull;
        }
        if (output) {
            output->write(buffer.data(), requested);
            if (!*output) {
                error = "Could not write restored flash image";
                return 0;
            }
        }
        bytes -= static_cast<uint64_t>(requested);
    }
    return hash;
}
}

uint64_t FingerprintFile(const std::string &path, std::string &error)
{
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        error = "Could not open file for fingerprinting";
        return 0;
    }
    uint64_t hash = 1469598103934665603ull;
    std::array<char, 64 * 1024> buffer {};
    while (input) {
        input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
        const std::streamsize count = input.gcount();
        for (std::streamsize i = 0; i < count; ++i) {
            hash ^= static_cast<unsigned char>(buffer[static_cast<size_t>(i)]);
            hash *= 1099511628211ull;
        }
    }
    if (!input.eof()) {
        error = "Could not read file while fingerprinting";
        return 0;
    }
    return hash;
}

SnapshotInfo InspectSnapshot(const std::string &path)
{
    SnapshotInfo result;
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        result.error = "Snapshot cannot be opened";
        return result;
    }
    uint32_t magic = 0;
    input.read(reinterpret_cast<char *>(&magic), sizeof(magic));
    if (!input) {
        result.error = "Snapshot is truncated";
        return result;
    }
    input.seekg(0);
    if (magic == HARMONY_MAGIC) {
        uint32_t prefix[3] {};
        input.read(reinterpret_cast<char *>(prefix), sizeof(prefix));
        input.seekg(0);
        uint64_t headerSize = 0;
        if (prefix[1] == HARMONY_VERSION_V4 && prefix[2] == sizeof(HarmonyHeaderV4)) {
            HarmonyHeaderV4 header {};
            input.read(reinterpret_cast<char *>(&header), sizeof(header));
            result.version = header.version;
            result.product = header.product;
            result.bootFingerprint = header.bootFingerprint;
            result.flashFingerprint = header.flashFingerprint;
            result.corePayloadSize = header.payloadSize;
            headerSize = sizeof(header);
        } else if (prefix[1] == HARMONY_VERSION && prefix[2] == sizeof(HarmonyHeader)) {
            HarmonyHeader header {};
            input.read(reinterpret_cast<char *>(&header), sizeof(header));
            result.version = header.version;
            result.product = header.product;
            result.bootFingerprint = header.bootFingerprint;
            result.flashFingerprint = header.flashFingerprint;
            result.corePayloadSize = header.corePayloadSize;
            result.flashPayloadSize = header.flashPayloadSize;
            result.embeddedFlash = header.flashPayloadSize != 0;
            headerSize = sizeof(header);
        } else {
            result.error = "Unsupported or damaged Harmony snapshot header";
            return result;
        }
        if (!input || !result.corePayloadSize ||
            (result.version == HARMONY_VERSION && !result.embeddedFlash)) {
            result.error = "Unsupported or damaged Harmony snapshot header";
            return result;
        }
        std::error_code ec;
        const uint64_t fileSize = std::filesystem::file_size(path, ec);
        if (ec || fileSize != headerSize + result.corePayloadSize + result.flashPayloadSize) {
            result.error = "Harmony snapshot payload length does not match its header";
            return result;
        }
        result.valid = true;
        result.harmonyFormat = true;
        return result;
    }

    gzFile compressed = gzopen(path.c_str(), "rb");
    if (!compressed) {
        result.error = "Snapshot is neither FBHS nor a gzip Firebird snapshot";
        return result;
    }
    CoreHeader header {};
    const int count = gzread(compressed, &header, sizeof(header));
    if (count != sizeof(header) || header.magic != CORE_MAGIC || header.version != CORE_VERSION) {
        gzclose(compressed);
        result.error = "Unsupported or damaged desktop Firebird snapshot";
        return result;
    }
    LegacyNandMetrics metrics {};
    if (gzread(compressed, &metrics, sizeof(metrics)) != sizeof(metrics) ||
        !IsCx2Geometry(metrics)) {
        gzclose(compressed);
        result.error = "Desktop snapshot does not contain CX II flash geometry";
        return result;
    }
    std::array<char, 64 * 1024> validationBuffer {};
    int readCount = 0;
    while ((readCount = gzread(compressed, validationBuffer.data(), validationBuffer.size())) > 0) {}
    const bool complete = readCount == 0 && gzeof(compressed);
    const int closeResult = gzclose(compressed);
    if (!complete || closeResult != Z_OK) {
        result.error = "Desktop Firebird snapshot gzip payload is truncated or corrupt";
        return result;
    }
    result.valid = true;
    result.harmonyFormat = false;
    result.version = header.version;
    return result;
}

bool WrapHarmonySnapshot(const std::string &coreSnapshotPath, const std::string &destinationPath,
                         uint32_t product, const std::string &bootPath,
                         const std::string &flashPath, std::string &error)
{
    SnapshotInfo core = InspectSnapshot(coreSnapshotPath);
    if (!core.valid || core.harmonyFormat) {
        error = core.error.empty() ? "Core snapshot is not a desktop v3 payload" : core.error;
        return false;
    }
    const uint64_t bootFingerprint = FingerprintFile(bootPath, error);
    if (!error.empty()) return false;
    const uint64_t flashFingerprint = FingerprintFile(flashPath, error);
    if (!error.empty()) return false;

    std::error_code ec;
    const uint64_t payloadSize = std::filesystem::file_size(coreSnapshotPath, ec);
    if (ec) {
        error = "Could not determine core snapshot size";
        return false;
    }
    HarmonyHeader header {};
    header.magic = HARMONY_MAGIC;
    header.version = HARMONY_VERSION;
    header.headerSize = sizeof(header);
    header.product = product;
    header.bootFingerprint = bootFingerprint;
    header.flashFingerprint = flashFingerprint;
    header.corePayloadSize = payloadSize;
    header.flashPayloadSize = std::filesystem::file_size(flashPath, ec);
    if (ec || header.flashPayloadSize == 0) {
        error = "Could not determine flash image size";
        return false;
    }
    std::strncpy(header.bootId, "images/boot1.rom", sizeof(header.bootId) - 1);
    std::strncpy(header.flashId, "images/flash.img", sizeof(header.flashId) - 1);

    const std::string temporary = destinationPath + ".tmp";
    std::ifstream input(coreSnapshotPath, std::ios::binary);
    std::ifstream flashInput(flashPath, std::ios::binary);
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    output.write(reinterpret_cast<const char *>(&header), sizeof(header));
    if (!input || !flashInput || !output || !CopyBytes(input, output, payloadSize, error) ||
        !CopyBytes(flashInput, output, header.flashPayloadSize, error)) {
        output.close();
        std::filesystem::remove(temporary, ec);
        if (error.empty()) error = "Could not create Harmony snapshot";
        return false;
    }
    output.flush();
    output.close();
    if (!output) {
        error = "Could not flush Harmony snapshot";
        std::filesystem::remove(temporary, ec);
        return false;
    }
    std::filesystem::rename(temporary, destinationPath, ec);
    if (ec) {
        error = "Could not atomically install Harmony snapshot";
        std::filesystem::remove(temporary, ec);
        return false;
    }
    return true;
}

bool UnwrapHarmonySnapshot(const std::string &sourcePath, const std::string &coreSnapshotPath,
                           std::string &error)
{
    SnapshotInfo info = InspectSnapshot(sourcePath);
    if (!info.valid || !info.harmonyFormat) {
        error = info.error.empty() ? "Not a Harmony snapshot" : info.error;
        return false;
    }
    std::ifstream input(sourcePath, std::ios::binary);
    const uint64_t headerSize = info.version == HARMONY_VERSION ?
                                sizeof(HarmonyHeader) : sizeof(HarmonyHeaderV4);
    input.seekg(static_cast<std::streamoff>(headerSize));
    std::ofstream output(coreSnapshotPath, std::ios::binary | std::ios::trunc);
    if (!input || !output || !CopyBytes(input, output, info.corePayloadSize, error)) {
        std::error_code ec;
        output.close();
        std::filesystem::remove(coreSnapshotPath, ec);
        return false;
    }
    output.flush();
    return static_cast<bool>(output);
}

bool ValidateEmbeddedFlash(const std::string &sourcePath, std::string &error)
{
    const SnapshotInfo info = InspectSnapshot(sourcePath);
    if (!info.valid || !info.embeddedFlash) {
        error = info.error.empty() ? "Snapshot has no embedded flash image" : info.error;
        return false;
    }
    std::ifstream input(sourcePath, std::ios::binary);
    input.seekg(static_cast<std::streamoff>(sizeof(HarmonyHeader) + info.corePayloadSize));
    const uint64_t fingerprint = FingerprintBytes(input, info.flashPayloadSize, nullptr, error);
    if (!error.empty()) return false;
    if (fingerprint != info.flashFingerprint) {
        error = "Embedded flash fingerprint does not match snapshot header";
        return false;
    }
    return true;
}

bool RestoreEmbeddedFlash(const std::string &sourcePath, const std::string &flashPath,
                          std::string &error)
{
    const SnapshotInfo info = InspectSnapshot(sourcePath);
    if (!info.valid || !info.embeddedFlash) {
        error = info.error.empty() ? "Snapshot has no embedded flash image" : info.error;
        return false;
    }
    const std::string temporary = flashPath + ".snapshot.tmp";
    std::ifstream input(sourcePath, std::ios::binary);
    input.seekg(static_cast<std::streamoff>(sizeof(HarmonyHeader) + info.corePayloadSize));
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    const uint64_t fingerprint = FingerprintBytes(input, info.flashPayloadSize, &output, error);
    output.flush();
    output.close();
    std::error_code ec;
    if (!error.empty() || fingerprint != info.flashFingerprint || !output) {
        if (error.empty()) error = "Embedded flash fingerprint does not match snapshot header";
        std::filesystem::remove(temporary, ec);
        return false;
    }
    std::filesystem::rename(temporary, flashPath, ec);
    if (ec) {
        error = "Could not atomically restore snapshot flash image";
        std::filesystem::remove(temporary, ec);
        return false;
    }
    return true;
}
