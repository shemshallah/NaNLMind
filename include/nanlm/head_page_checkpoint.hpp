// Persistent checkpoint store for the 255 x 1 MiB head pages.
//
// A checkpoint is a directory with one 1 MiB page per active head plus a
// canonical manifest:
//
//   head-NNN.page
//   manifest.txt : "head generation sha256"
//
// Writes are page-temp + rename, then manifest-temp + rename. This protects
// against torn files; it does not claim power-loss ordering on every filesystem.
// The store is host storage/provenance only. It performs no head arithmetic.
#pragma once
#include "nanlm/head_page_arena.hpp"
#include "nanlm/sha256.hpp"

#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace nanlm {

class HeadPageCheckpoint {
public:
    static constexpr std::size_t kHeads = HeadPageArena::kHeadCount;
    static constexpr std::size_t kPageBytes = HeadPageArena::kPageBytes;

    struct Record {
        std::uint64_t generation = 0;
        std::string sha256;
        bool present = false;
    };

    explicit HeadPageCheckpoint(std::filesystem::path directory)
        : dir_(std::move(directory)) {
        std::filesystem::create_directories(dir_);
        load_manifest();
    }

    const std::filesystem::path& directory() const noexcept { return dir_; }

    std::filesystem::path page_path(std::size_t head) const {
        if (head >= kHeads) throw std::out_of_range("head page");
        std::string name = "head-";
        std::string s = std::to_string(head);
        while (s.size() < 3) s.insert(s.begin(), '0');
        return dir_ / (name + s + ".page");
    }

    void write_page(std::size_t head, const std::uint8_t* data,
                    std::size_t bytes, std::uint64_t generation) {
        if (!data || bytes != kPageBytes)
            throw std::invalid_argument("head checkpoint page must be 1 MiB");
        if (!valid_page_header(data))
            throw std::invalid_argument("head checkpoint page header invalid");
        const auto path = page_path(head);
        const auto temp = path.string() + ".tmp";
        {
            std::ofstream out(temp, std::ios::binary | std::ios::trunc);
            if (!out) throw std::runtime_error("cannot write " + temp);
            out.write(reinterpret_cast<const char*>(data),
                      static_cast<std::streamsize>(bytes));
            if (!out) throw std::runtime_error("short write " + temp);
        }
        std::filesystem::rename(temp, path);
        records_[head].generation = generation;
        records_[head].sha256 = hex(Sha256::hash(data, bytes));
        records_[head].present = true;
        write_manifest();
    }

    bool read_page(std::size_t head, std::vector<std::uint8_t>& out) const {
        if (head >= kHeads) throw std::out_of_range("head page");
        if (!records_[head].present) return false;
        std::ifstream in(page_path(head), std::ios::binary);
        if (!in) return false;
        out.assign(std::istreambuf_iterator<char>(in),
                   std::istreambuf_iterator<char>());
        if (out.size() != kPageBytes) return false;
        if (hex(Sha256::hash(out.data(), out.size())) != records_[head].sha256)
            return false;
        return valid_page_header(out.data());
    }

    bool read_page(std::size_t head, HeadPageArena& arena) const {
        std::vector<std::uint8_t> bytes;
        if (!read_page(head, bytes)) return false;
        arena.load_page(head, bytes.data(), bytes.size());
        return true;
    }

    bool present(std::size_t head) const {
        if (head >= kHeads) throw std::out_of_range("head page");
        return records_[head].present;
    }
    const Record& record(std::size_t head) const {
        if (head >= kHeads) throw std::out_of_range("head page");
        return records_[head];
    }
    std::size_t page_count() const {
        std::size_t n = 0;
        for (const auto& r : records_) n += r.present ? 1u : 0u;
        return n;
    }

    bool verify_all(std::string* error = nullptr) const {
        for (std::size_t h = 0; h < kHeads; ++h) {
            if (!records_[h].present) continue;
            std::vector<std::uint8_t> bytes;
            if (!read_page(h, bytes)) {
                if (error) *error = "page verification failed for head " +
                                    std::to_string(h);
                return false;
            }
        }
        return true;
    }

    std::string root_digest() const {
        Sha256 sha;
        for (std::size_t h = 0; h < kHeads; ++h) {
            if (!records_[h].present) continue;
            const std::array<std::uint8_t, 2> head_bytes = {
                static_cast<std::uint8_t>(h & 0xFFu),
                static_cast<std::uint8_t>((h >> 8) & 0xFFu)};
            sha.update(head_bytes.data(), head_bytes.size());
            const auto gen = records_[h].generation;
            std::array<std::uint8_t, 8> gen_bytes{};
            for (unsigned i = 0; i < 8; ++i)
                gen_bytes[i] = static_cast<std::uint8_t>(gen >> (8 * i));
            sha.update(gen_bytes.data(), gen_bytes.size());
            sha.update(records_[h].sha256.data(), records_[h].sha256.size());
        }
        return hex(sha.final());
    }

    static bool valid_page_header(const std::uint8_t* data) {
        if (!data) return false;
        constexpr std::size_t kHeader = 0xFCC00u;
        const std::uint32_t magic =
            static_cast<std::uint32_t>(data[kHeader + 0]) |
            (static_cast<std::uint32_t>(data[kHeader + 1]) << 8) |
            (static_cast<std::uint32_t>(data[kHeader + 2]) << 16) |
            (static_cast<std::uint32_t>(data[kHeader + 3]) << 24);
        return magic == 0x48315233u;
    }

private:
    void load_manifest() {
        records_.fill(Record{});
        std::ifstream in(dir_ / "manifest.txt");
        if (!in) return;
        std::string line;
        while (std::getline(in, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty()) continue;
            std::istringstream ss(line);
            unsigned head = 0;
            std::uint64_t generation = 0;
            std::string digest;
            if (!(ss >> head >> generation >> digest) || head >= kHeads ||
                digest.size() != 64)
                throw std::runtime_error("malformed head checkpoint manifest");
            records_[head].generation = generation;
            records_[head].sha256 = digest;
            records_[head].present = true;
        }
    }

    void write_manifest() const {
        const auto temp = (dir_ / "manifest.txt.tmp").string();
        const auto final = (dir_ / "manifest.txt").string();
        std::ofstream out(temp, std::ios::trunc);
        if (!out) throw std::runtime_error("cannot write manifest");
        for (std::size_t h = 0; h < kHeads; ++h) {
            if (!records_[h].present) continue;
            out << h << ' ' << records_[h].generation << ' '
                << records_[h].sha256 << '\n';
        }
        if (!out) throw std::runtime_error("short manifest write");
        out.close();
        std::filesystem::rename(temp, final);
    }

    std::filesystem::path dir_;
    std::array<Record, kHeads> records_{};
};

} // namespace nanlm
