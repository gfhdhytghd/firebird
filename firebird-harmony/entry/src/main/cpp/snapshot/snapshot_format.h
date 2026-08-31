#pragma once

#include <cstdint>
#include <string>

struct SnapshotInfo {
    bool valid = false;
    bool harmonyFormat = false;
    uint32_t version = 0;
    uint32_t product = 0;
    uint64_t bootFingerprint = 0;
    uint64_t flashFingerprint = 0;
    uint64_t corePayloadSize = 0;
    uint64_t flashPayloadSize = 0;
    bool embeddedFlash = false;
    std::string error;
};

uint64_t FingerprintFile(const std::string &path, std::string &error);
SnapshotInfo InspectSnapshot(const std::string &path);
bool WrapHarmonySnapshot(const std::string &coreSnapshotPath, const std::string &destinationPath,
                         uint32_t product, const std::string &bootPath,
                         const std::string &flashPath, std::string &error);
bool UnwrapHarmonySnapshot(const std::string &sourcePath, const std::string &coreSnapshotPath,
                           std::string &error);
bool ValidateEmbeddedFlash(const std::string &sourcePath, std::string &error);
bool RestoreEmbeddedFlash(const std::string &sourcePath, const std::string &flashPath,
                          std::string &error);
