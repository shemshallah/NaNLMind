#include "nanlm/head_candidate.hpp"
#include "nanlm/global.hpp"

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#include <vector>

namespace nanlm {

int head_candidate_cli(int argc, char** argv) {
    if (argc != 6) {
        std::cerr << "usage: nanlm-universal head-candidate BASE_STATE HEAD_INDEX PATCH_MASK CANDIDATE_STATE\n";
        return 2;
    }
    const std::string base_path = argv[2];
    const std::string candidate_path = argv[5];
    unsigned head_index = 0;
    unsigned patch = 0;
    try {
        head_index = static_cast<unsigned>(std::stoul(argv[3], nullptr, 10));
        patch = static_cast<unsigned>(std::stoul(argv[4], nullptr, 0));
    } catch (...) {
        std::cerr << "invalid head index or patch mask\n";
        return 2;
    }
    if (head_index > 255u || patch == 0u || patch > 0xFFFFu) {
        std::cerr << "head index must be 0..255 and patch mask must be 1..65535\n";
        return 2;
    }
    std::error_code ec;
    const auto base_abs = std::filesystem::absolute(base_path, ec).lexically_normal();
    if (ec) { std::cerr << "cannot resolve base state path\n"; return 2; }
    const auto candidate_abs = std::filesystem::absolute(candidate_path, ec).lexically_normal();
    if (ec || candidate_abs == base_abs || std::filesystem::exists(candidate_abs)) {
        std::cerr << "candidate path must be distinct and must not already exist\n";
        return 2;
    }
    std::ifstream input(base_path, std::ios::binary);
    if (!input) { std::cerr << "cannot open base topology\n"; return 3; }
    std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(input)),
                                    std::istreambuf_iterator<char>());
    auto topology = GlobalTopology::from_bytes(bytes.data(), bytes.size());
    if (!topology) { std::cerr << "invalid base topology\n"; return 4; }
    const Hash256 base_digest = topology->global_digest();
    HeadArray heads = topology->root_heads();
    HeadView head = heads.at(static_cast<std::uint8_t>(head_index));
    const std::uint16_t mask_before = head.boolean_mask();
    const std::uint8_t rule_before = head.boolean_rule();
    if (!head.self_modify_boolean(static_cast<std::uint16_t>(patch))) {
        std::cerr << "head rejected candidate Boolean mutation (ACL or address protection)\n";
        return 5;
    }
    const std::uint16_t mask_after = head.boolean_mask();
    const std::uint8_t rule_after = head.boolean_rule();
    if (mask_before == mask_after) {
        std::cerr << "candidate mutation produced no state change\n";
        return 5;
    }
    const auto* root_page = topology->pages().entry(PageId::root());
    if (!root_page || !root_page->page) {
        std::cerr << "root page missing after candidate mutation\n";
        return 5;
    }
    root_page->page->refresh_checksums();
    const Hash256 mutated_digest = topology->global_digest();
    topology->commit(0x48u, 0x4Du, 0u, base_digest, mutated_digest,
                     static_cast<std::uint64_t>(topology->ledger().size() + 1u));
    const Hash256 candidate_digest = topology->global_digest();
    const auto output = topology->serialize();
    const auto parent = candidate_abs.parent_path();
    std::filesystem::create_directories(parent.empty() ? std::filesystem::path(".") : parent);
    const std::string temporary = candidate_path + ".tmp";
    {
        std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
        if (!stream) { std::cerr << "cannot create candidate state\n"; return 6; }
        stream.write(reinterpret_cast<const char*>(output.data()),
                     static_cast<std::streamsize>(output.size()));
        stream.flush();
        if (!stream) { std::cerr << "candidate state write failed\n"; std::filesystem::remove(temporary); return 6; }
    }
    std::filesystem::rename(temporary, candidate_path, ec);
    if (ec) {
        std::cerr << "candidate publish failed: " << ec.message() << "\n";
        std::filesystem::remove(temporary);
        return 6;
    }
    std::cout << "{"
              << "\"status\":\"candidate_only\","
              << "\"canonical_state_modified\":false,"
              << "\"head_index\":" << head_index << ","
              << "\"patch_mask\":" << patch << ","
              << "\"boolean_mask_before\":" << mask_before << ","
              << "\"boolean_mask_after\":" << mask_after << ","
              << "\"boolean_rule_before\":" << static_cast<unsigned>(rule_before) << ","
              << "\"boolean_rule_after\":" << static_cast<unsigned>(rule_after) << ","
              << "\"base_digest\":\"" << hex(base_digest) << "\","
              << "\"candidate_digest\":\"" << hex(candidate_digest) << "\","
              << "\"candidate_state_path\":\"" << candidate_path << "\""
              << "}\n";
    return 0;
}

} // namespace nanlm
