// Persistent checkpoint for the 512-slot chunk-summary bank.
//
// Directory: summary-NNN.bin + manifest.txt. Each record is a canonical
// little-endian NSB1 file with a SHA-256 in the manifest. Writes are temp +
// rename; the summary bank remains host storage only.
#pragma once
#include "nanlm/chunk_summary.hpp"
#include "nanlm/sha256.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <optional>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace nanlm {

class SummaryBankCheckpoint {
public:
    static constexpr std::size_t kCapacity = 512;

    struct Record {
        std::uint64_t generation = 0;
        std::string sha256;
        std::uint64_t chunk_id = 0;
        std::uint64_t token_count = 0;
        std::uint16_t head_count = 0;
        bool present = false;
    };

    explicit SummaryBankCheckpoint(std::filesystem::path directory)
        : dir_(std::move(directory)) {
        std::filesystem::create_directories(dir_);
        load_manifest();
    }

    const std::filesystem::path& directory() const noexcept { return dir_; }
    std::filesystem::path record_path(std::size_t slot) const {
        if (slot >= kCapacity) throw std::out_of_range("summary slot");
        std::string s = std::to_string(slot);
        while (s.size() < 3) s.insert(s.begin(), '0');
        return dir_ / ("summary-" + s + ".bin");
    }

    void write_record(std::size_t slot, const ChunkSummary& summary,
                      std::uint64_t generation) {
        if (slot >= kCapacity) throw std::out_of_range("summary slot");
        if (summary.heads.size() != summary.states.size() ||
            summary.heads.empty() || summary.heads.size() > 255u)
            throw std::invalid_argument("summary shape");
        std::array<bool, 255> seen{};
        for (unsigned head : summary.heads) {
            if (head >= 255u || seen[head])
                throw std::invalid_argument("summary head invalid/duplicate");
            seen[head] = true;
        }
        const std::size_t bytes = 40u + 516u * summary.heads.size();
        std::vector<std::uint8_t> data(bytes, 0);
        data[0] = 'N'; data[1] = 'S'; data[2] = 'B'; data[3] = '1';
        put16(data.data() + 4, 1);
        put16(data.data() + 6, 40);
        put64(data.data() + 8, generation);
        put64(data.data() + 16, summary.chunk_id);
        put64(data.data() + 24, summary.token_count);
        put32(data.data() + 32, static_cast<std::uint32_t>(summary.heads.size()));
        for (std::size_t i = 0; i < summary.heads.size(); ++i) {
            auto* p = data.data() + 40u + i * 516u;
            put16(p, static_cast<std::uint16_t>(summary.heads[i]));
            put16(p + 2, 0);
            for (unsigned d = 0; d < 128u; ++d) {
                const float value = summary.states[i][d];
                if (!std::isfinite(value))
                    throw std::invalid_argument("summary state nonfinite");
                std::uint32_t bits = 0;
                std::memcpy(&bits, &value, sizeof(bits));
                put32(p + 4u + d * 4u, bits);
            }
        }
        const auto path = record_path(slot);
        const auto temp = path.string() + ".tmp";
        {
            std::ofstream out(temp, std::ios::binary | std::ios::trunc);
            if (!out) throw std::runtime_error("cannot write summary record");
            out.write(reinterpret_cast<const char*>(data.data()),
                      static_cast<std::streamsize>(data.size()));
            if (!out) throw std::runtime_error("short summary write");
        }
        std::filesystem::rename(temp, path);
        auto& rec = records_[slot];
        rec.generation = generation;
        rec.sha256 = hex(Sha256::hash(data.data(), data.size()));
        rec.chunk_id = summary.chunk_id;
        rec.token_count = summary.token_count;
        rec.head_count = static_cast<std::uint16_t>(summary.heads.size());
        rec.present = true;
        write_manifest();
    }

    void write_bank(const SummaryBank& bank, std::uint64_t generation) {
        if (bank.size() > kCapacity)
            throw std::invalid_argument("summary bank exceeds checkpoint capacity");
        for (std::size_t i = 0; i < bank.size(); ++i)
            write_record(i, bank.at(i), generation);
    }

    bool read_record(std::size_t slot, ChunkSummary& out) const {
        if (slot >= kCapacity) throw std::out_of_range("summary slot");
        if (!records_[slot].present) return false;
        std::ifstream in(record_path(slot), std::ios::binary);
        if (!in) return false;
        std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(in)),
                                       std::istreambuf_iterator<char>());
        if (hex(Sha256::hash(data.data(), data.size())) != records_[slot].sha256)
            return false;
        const auto decoded = decode(data);
        if (!decoded) return false;
        out = *decoded;
        return out.chunk_id == records_[slot].chunk_id &&
               out.token_count == records_[slot].token_count &&
               out.heads.size() == records_[slot].head_count;
    }

    bool load(SummaryBank& bank, std::string* error = nullptr) const {
        std::vector<ChunkSummary> staged;
        for (std::size_t i = 0; i < kCapacity; ++i) {
            if (!records_[i].present) continue;
            ChunkSummary summary{};
            if (!read_record(i, summary)) {
                if (error) *error = "summary record failed at slot " + std::to_string(i);
                return false;
            }
            staged.push_back(std::move(summary));
        }
        bank.clear();
        for (auto& summary : staged) bank.append(std::move(summary));
        return true;
    }

    bool verify_all(std::string* error = nullptr) const {
        for (std::size_t i = 0; i < kCapacity; ++i) {
            if (!records_[i].present) continue;
            ChunkSummary summary{};
            if (!read_record(i, summary)) {
                if (error) *error = "summary verification failed at " + std::to_string(i);
                return false;
            }
        }
        return true;
    }

    bool present(std::size_t slot) const {
        if (slot >= kCapacity) throw std::out_of_range("summary slot");
        return records_[slot].present;
    }
    const Record& record(std::size_t slot) const {
        if (slot >= kCapacity) throw std::out_of_range("summary slot");
        return records_[slot];
    }
    std::size_t record_count() const {
        std::size_t n = 0;
        for (const auto& r : records_) n += r.present ? 1u : 0u;
        return n;
    }

    std::string root_digest() const {
        Sha256 sha;
        for (std::size_t i = 0; i < kCapacity; ++i) {
            if (!records_[i].present) continue;
            const auto& r = records_[i];
            std::array<std::uint8_t, 32> buf{};
            put16(buf.data(), static_cast<std::uint16_t>(i));
            put64(buf.data() + 2, r.generation);
            put64(buf.data() + 10, r.chunk_id);
            put64(buf.data() + 18, r.token_count);
            put16(buf.data() + 26, r.head_count);
            sha.update(buf.data(), 28);
            sha.update(r.sha256.data(), r.sha256.size());
        }
        return hex(sha.final());
    }

private:
    static void put16(std::uint8_t* p, std::uint16_t v) {
        p[0] = static_cast<std::uint8_t>(v);
        p[1] = static_cast<std::uint8_t>(v >> 8);
    }
    static void put32(std::uint8_t* p, std::uint32_t v) {
        for (unsigned i = 0; i < 4; ++i)
            p[i] = static_cast<std::uint8_t>(v >> (8 * i));
    }
    static void put64(std::uint8_t* p, std::uint64_t v) {
        for (unsigned i = 0; i < 8; ++i)
            p[i] = static_cast<std::uint8_t>(v >> (8 * i));
    }
    static std::uint16_t get16(const std::uint8_t* p) {
        return static_cast<std::uint16_t>(p[0] | (p[1] << 8));
    }
    static std::uint32_t get32(const std::uint8_t* p) {
        std::uint32_t v = 0;
        for (unsigned i = 0; i < 4; ++i)
            v |= static_cast<std::uint32_t>(p[i]) << (8 * i);
        return v;
    }
    static std::uint64_t get64(const std::uint8_t* p) {
        std::uint64_t v = 0;
        for (unsigned i = 0; i < 8; ++i)
            v |= static_cast<std::uint64_t>(p[i]) << (8 * i);
        return v;
    }
    static std::optional<ChunkSummary> decode(const std::vector<std::uint8_t>& data) {
        if (data.size() < 40u || data[0] != 'N' || data[1] != 'S' ||
            data[2] != 'B' || data[3] != '1' || get16(data.data() + 4) != 1 ||
            get16(data.data() + 6) != 40 || get32(data.data() + 36) != 0)
            return std::nullopt;
        const std::uint64_t chunk_id = get64(data.data() + 16);
        const std::uint64_t token_count = get64(data.data() + 24);
        const std::uint32_t head_count = get32(data.data() + 32);
        if (head_count == 0 || head_count > 255 ||
            data.size() != 40u + 516u * head_count)
            return std::nullopt;
        ChunkSummary summary{};
        summary.chunk_id = chunk_id;
        summary.token_count = token_count;
        std::array<bool, 255> seen{};
        for (std::uint32_t i = 0; i < head_count; ++i) {
            const auto* p = data.data() + 40u + i * 516u;
            const unsigned head = get16(p);
            if (head >= 255u || seen[head] || get16(p + 2) != 0)
                return std::nullopt;
            seen[head] = true;
            summary.heads.push_back(head);
            std::array<float, 128> state{};
            for (unsigned d = 0; d < 128u; ++d) {
                const std::uint32_t bits = get32(p + 4u + d * 4u);
                std::memcpy(&state[d], &bits, sizeof(float));
                if (!std::isfinite(state[d])) return std::nullopt;
            }
            summary.states.push_back(state);
        }
        return summary;
    }

    void load_manifest() {
        records_.fill(Record{});
        std::ifstream in(dir_ / "manifest.txt");
        if (!in) return;
        std::string line;
        while (std::getline(in, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty()) continue;
            std::istringstream ss(line);
            unsigned slot = 0;
            std::uint64_t generation = 0, chunk_id = 0, token_count = 0;
            std::string digest;
            unsigned head_count = 0;
            if (!(ss >> slot >> generation >> digest >> chunk_id >>
                  token_count >> head_count) ||
                slot >= kCapacity || digest.size() != 64 || head_count == 0 ||
                head_count > 255 || records_[slot].present)
                throw std::runtime_error("malformed summary manifest");
            records_[slot] = Record{generation, digest, chunk_id, token_count,
                                    static_cast<std::uint16_t>(head_count), true};
        }
    }

    void write_manifest() const {
        const auto temp = (dir_ / "manifest.txt.tmp").string();
        const auto final = (dir_ / "manifest.txt").string();
        std::ofstream out(temp, std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write summary manifest");
        for (std::size_t i = 0; i < kCapacity; ++i) {
            const auto& r = records_[i];
            if (!r.present) continue;
            out << i << ' ' << r.generation << ' ' << r.sha256 << ' '
                << r.chunk_id << ' ' << r.token_count << ' ' << r.head_count << '\n';
        }
        if (!out) throw std::runtime_error("short summary manifest");
        out.close();
        std::filesystem::rename(temp, final);
    }

    std::filesystem::path dir_;
    std::array<Record, kCapacity> records_{};
};

} // namespace nanlm
