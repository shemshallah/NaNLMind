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
#include "nanlm/unified_context_runtime.hpp"

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
        if (kind == Kind::None) { unload(); return true; }
        // One field_driver image owns byte, word and token kernels. Switching
        // kind changes the active table interpretation, not the VM.
        if (!vm_) {
            vm_ = std::make_unique<RawFieldVM>(build_dir_ + "/field_driver.nan");
            if (!vm_->ready()) {
                error_ = vm_->error();
                vm_.reset();
                kind_ = Kind::None;
                return false;
            }
        }
        kind_ = kind;
        error_.clear();
        return true;
    }
    void unload() noexcept {
        context_.reset();
        arena_.reset();
        context_vm_.reset();
        vm_.reset();
        kind_ = Kind::None;
    }
    // Hierarchical context and layered 64-token self-attention are always part
    // of the runtime, not a selectable projection mode.
    UnifiedContextRuntime& context() {
        if (!context_) {
            context_vm_ = std::make_unique<RawFieldVM>(build_dir_ + "/head_worker.nan");
            if (!context_vm_->ready())
                throw std::runtime_error(context_vm_->error());
            arena_ = std::make_unique<HeadPageArena>();
            context_ = std::make_unique<UnifiedContextRuntime>(*context_vm_, *arena_);
        }
        return *context_;
    }
    bool context_ready() const noexcept { return context_ != nullptr; }

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
        return vm_->unified_word_build(ids, vocabulary);
    }
    bool word_batch(const std::vector<std::uint32_t>& ids, std::size_t vocabulary,
                    std::uint32_t previous) {
        if (kind_ != Kind::Word) return wrong("word");
        return vm_->unified_word_batch(ids, vocabulary, previous);
    }
    bool word_top5(std::uint32_t target, std::uint32_t context,
                   std::size_t vocabulary, std::uint32_t token_count,
                   std::array<std::uint32_t, 5>& top, float& loss) {
        if (kind_ != Kind::Word) return wrong("word");
        return vm_->unified_word_top5(target, context, vocabulary,
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
        return vm_->unified_token_build(ids, vocabulary, rows, previous);
    }
    bool token_top5(std::uint32_t target, std::uint32_t row,
                    std::size_t vocabulary, std::uint32_t token_count,
                    std::array<std::uint32_t, 5>& top, float& loss) {
        if (kind_ != Kind::Token) return wrong("token");
        return vm_->unified_token_top5(target, row, vocabulary,
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
    std::unique_ptr<RawFieldVM> context_vm_;
    std::unique_ptr<HeadPageArena> arena_;
    std::unique_ptr<UnifiedContextRuntime> context_;
    ContextBackoffSelection selection_{};
    std::string error_;
};

// The same single-resident-VM boundary covers projections and long context.
using UnifiedRuntime = ProjectionRuntime;

} // namespace nanlm
