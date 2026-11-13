// One projection-runtime entry point for all native readout heads.
//
// The byte context readout uses field_driver.nan; word and token projections
// use their own worker images. Only one projection VM is resident at a time,
// which keeps the 128 MiB guest memory budget controlled and prevents two
// count tables from silently aliasing. Every mathematical operation still
// executes in the selected raw NaN16 image. Host code only loads images,
// transports arguments and forwards receipts.
#pragma once
#include "nanlm/raw_field.hpp"

#include <array>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace nanlm {

class ProjectionRuntime {
public:
    enum class Kind { None, Byte, Word, Token };

    explicit ProjectionRuntime(std::string build_dir = "build")
        : build_dir_(std::move(build_dir)) {}

    Kind kind() const noexcept { return kind_; }
    bool ready() const noexcept { return vm_ != nullptr; }
    const std::string& error() const noexcept { return error_; }

    bool load(Kind kind) {
        if (kind == kind_ && vm_) return true;
        vm_.reset();
        kind_ = Kind::None;
        std::string path;
        switch (kind) {
        case Kind::Byte: path = build_dir_ + "/field_driver.nan"; break;
        case Kind::Word: path = build_dir_ + "/word_worker.nan"; break;
        case Kind::Token: path = build_dir_ + "/token_worker.nan"; break;
        case Kind::None: return true;
        }
        vm_ = std::make_unique<RawFieldVM>(path);
        if (!vm_->ready()) {
            error_ = vm_->error();
            vm_.reset();
            return false;
        }
        kind_ = kind;
        error_.clear();
        return true;
    }
    void unload() noexcept {
        vm_.reset();
        kind_ = Kind::None;
    }

    // Byte direct-256 context readout (field_driver).
    bool byte_reset(std::size_t exact, std::size_t fallback) {
        if (kind_ != Kind::Byte) return wrong("byte");
        if (!vm_->context_backoff_select(exact + fallback, exact, selection_))
            return fail(vm_->error());
        return vm_->reset_context_direct(selection_.exact_count,
                                         selection_.fallback);
    }
    bool byte_build(const std::uint32_t* keys, std::size_t count) {
        if (kind_ != Kind::Byte) return wrong("byte");
        std::size_t inserted = 0;
        return vm_->context_backoff_build_batch(keys, count, inserted);
    }
    bool byte_step(std::uint8_t target, std::uint32_t key,
                   std::uint32_t& bucket, bool& exact) {
        if (kind_ != Kind::Byte) return wrong("byte");
        return vm_->context_direct_step(target, key, selection_.exact_count,
                                        selection_.fallback, bucket, exact);
    }
    bool byte_top5(std::uint8_t target, std::uint32_t key,
                   std::array<std::uint8_t, 5>& top, float& loss) {
        if (kind_ != Kind::Byte) return wrong("byte");
        return vm_->readout_context_direct_top5(
            target, key, selection_.exact_count, selection_.fallback, top, loss);
    }

    // Native word projection.
    bool word_clear(std::size_t vocabulary) {
        if (kind_ != Kind::Word) return wrong("word");
        return vm_->word_projection_clear(vocabulary);
    }
    bool word_build(const std::vector<std::uint32_t>& ids, std::size_t vocabulary) {
        if (kind_ != Kind::Word) return wrong("word");
        return vm_->word_projection_build(ids, vocabulary);
    }
    bool word_batch(const std::vector<std::uint32_t>& ids, std::size_t vocabulary,
                    std::uint32_t previous) {
        if (kind_ != Kind::Word) return wrong("word");
        return vm_->word_projection_batch(ids, vocabulary, previous);
    }
    bool word_top5(std::uint32_t target, std::uint32_t context,
                   std::size_t vocabulary, std::uint32_t token_count,
                   std::array<std::uint32_t, 5>& top, float& loss) {
        if (kind_ != Kind::Word) return wrong("word");
        return vm_->word_projection_top5(target, context, vocabulary,
                                         token_count, top, loss);
    }

    // Full-vocabulary token projection.
    bool token_clear(std::size_t vocabulary, std::size_t rows) {
        if (kind_ != Kind::Token) return wrong("token");
        return vm_->token_projection_clear(vocabulary, rows);
    }
    bool token_rowmap(const std::array<std::uint16_t, 65536>& map) {
        if (kind_ != Kind::Token) return wrong("token");
        return vm_->token_projection_write_rowmap(map);
    }
    bool token_batch(const std::vector<std::uint32_t>& ids,
                     std::size_t vocabulary, std::size_t rows,
                     std::uint32_t previous) {
        if (kind_ != Kind::Token) return wrong("token");
        return vm_->token_projection_batch(ids, vocabulary, rows, previous);
    }
    bool token_top5(std::uint32_t target, std::uint32_t row,
                    std::size_t vocabulary, std::uint32_t token_count,
                    std::array<std::uint32_t, 5>& top, float& loss) {
        if (kind_ != Kind::Token) return wrong("token");
        return vm_->token_projection_top5(target, row, vocabulary,
                                          token_count, top, loss);
    }

    const ContextBackoffSelection& byte_selection() const noexcept {
        return selection_;
    }

private:
    bool wrong(const char* expected) {
        error_ = std::string("projection runtime is not loaded for ") + expected;
        return false;
    }
    bool fail(std::string message) {
        error_ = std::move(message);
        return false;
    }

    std::string build_dir_;
    Kind kind_ = Kind::None;
    std::unique_ptr<RawFieldVM> vm_;
    ContextBackoffSelection selection_{};
    std::string error_;
};

} // namespace nanlm
