// Raw D=24 contextual role/sense corpus test.
//
// The host tokenizes text and stages word ids. Every forward pass, sigmoid or
// softmax, local-gradient, and parameter update runs in mth/drivers/field_driver.nas
// on the NaN0S VM. No C++ contextual learner is used here.
#include "nanlm/raw_field.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <map>
#include <numeric>
#include <random>
#include <string>
#include <vector>

namespace {

using nanlm::RawFieldVM;

struct RoleExample {
    std::string sentence;
    std::string subject;
    std::string object;
    std::string relation;
    std::uint8_t positive = 0;
};

struct SenseExample {
    std::string sentence;
    std::uint8_t target = 0;
};

std::vector<RoleExample> role_corpus(const std::vector<std::string>& names) {
    std::vector<RoleExample> rows;
    for (std::size_t i = 1; i < names.size(); i += 2) {
        const std::string& a = names[i - 1];
        const std::string& b = names[i];
        const std::vector<std::pair<std::string, std::string>> samples = {
            {a + " sent parcel to " + b, "transfer"},
            {a + " gave parcel to " + b, "transfer"},
            {a + " delivered parcel to " + b, "transfer"},
            {b + " received parcel from " + a, "transfer"},
            {b + " accepted parcel from " + a, "transfer"},
            {b + " got parcel from " + a, "transfer"},
            {a + " followed " + b, "follow"},
            {a + " walked behind " + b, "follow"},
            {a + " trailed " + b, "follow"},
            {b + " led " + a, "follow"},
            {b + " walked ahead of " + a, "follow"},
            {b + " was followed by " + a, "follow"},
        };
        for (const auto& [sentence, relation] : samples) {
            rows.push_back({sentence, a, b, relation, 1});
            rows.push_back({sentence, b, a, relation, 0});
        }
    }
    return rows;
}

std::vector<std::string> split_words(const std::string& sentence) {
    std::vector<std::string> words;
    std::string word;
    for (char c : sentence) {
        if (c == ' ') {
            if (!word.empty()) {
                words.push_back(word);
                word.clear();
            }
        } else {
            word.push_back(c);
        }
    }
    if (!word.empty()) words.push_back(word);
    return words;
}

using Vocab = std::map<std::string, std::uint8_t>;

void add_word(Vocab& vocab, const std::string& word) {
    if (vocab.find(word) == vocab.end()) {
        if (vocab.size() >= 64)
            throw std::runtime_error("raw contextual vocabulary exceeds 64 words");
        vocab.emplace(word, static_cast<std::uint8_t>(vocab.size()));
    }
}

Vocab role_vocabulary(const std::vector<RoleExample>& rows) {
    Vocab vocab;
    for (const RoleExample& row : rows) {
        for (const std::string& word : split_words(row.sentence)) {
            if (word != row.subject && word != row.object) add_word(vocab, word);
        }
    }
    return vocab;
}

Vocab sense_vocabulary(const std::vector<SenseExample>& rows,
                       const std::string& target) {
    Vocab vocab;
    for (const SenseExample& row : rows) {
        for (const std::string& word : split_words(row.sentence)) {
            if (word != target) add_word(vocab, word);
        }
    }
    return vocab;
}

struct SenseTokenized {
    std::vector<std::uint8_t> tokens;
    std::vector<std::uint8_t> positions;
};

SenseTokenized sense_tokenize(const std::string& sentence,
                              const std::string& target,
                              const Vocab& vocab) {
    const std::vector<std::string> words = split_words(sentence);
    std::size_t pos = words.size();
    for (std::size_t i = 0; i < words.size(); ++i)
        if (words[i] == target) pos = i;
    if (pos == words.size())
        throw std::runtime_error("sense target missing from sentence");
    SenseTokenized out;
    for (std::size_t i = 0; i < words.size(); ++i) {
        if (i == pos) continue;
        const auto found = vocab.find(words[i]);
        if (found == vocab.end()) continue;
        out.tokens.push_back(found->second);
        out.positions.push_back(static_cast<std::uint8_t>(i < pos ? 0u : 3u));
    }
    return out;
}

struct RoleTokenized {
    std::vector<std::uint8_t> tokens;
    std::vector<std::uint8_t> positions;
    float orientation = 1.0f;
};

RoleTokenized role_tokenize(const std::string& sentence,
                            const std::string& subject,
                            const std::string& object,
                            const Vocab& vocab) {
    const std::vector<std::string> words = split_words(sentence);
    std::size_t sa = words.size(), sb = words.size();
    for (std::size_t i = 0; i < words.size(); ++i) {
        if (words[i] == subject) sa = i;
        if (words[i] == object) sb = i;
    }
    RoleTokenized out;
    if (sa == words.size() || sb == words.size())
        throw std::runtime_error("role entity missing from sentence");
    out.orientation = sa < sb ? 1.0f : -1.0f;
    for (std::size_t i = 0; i < words.size(); ++i) {
        if (i == sa || i == sb) continue;
        const auto found = vocab.find(words[i]);
        if (found == vocab.end()) continue;
        out.tokens.push_back(found->second);
        out.positions.push_back(static_cast<std::uint8_t>(
            (i > sa ? 1u : 0u) + 2u * (i > sb ? 1u : 0u)));
    }
    return out;
}

std::array<float, 24> random_vector(std::mt19937& rng, float scale) {
    std::normal_distribution<float> normal(0.0f, scale);
    std::array<float, 24> out{};
    for (float& v : out) v = normal(rng);
    return out;
}

float evaluate_role(RawFieldVM& vm, const std::vector<RoleExample>& rows,
                    const std::vector<std::uint8_t>& relation_index,
                    const Vocab& vocab) {
    std::size_t correct = 0;
    for (const RoleExample& row : rows) {
        const RoleTokenized t = role_tokenize(row.sentence, row.subject,
                                             row.object, vocab);
        const std::uint8_t rel = relation_index[row.relation == "transfer" ? 0 : 1];
        float p = 0.0f, d = 0.0f;
        if (!vm.role_step24k_cached(t.tokens.size(), t.tokens, t.positions, rel,
                                    0.0f, 0.0f, t.orientation, p, d)) {
            throw std::runtime_error(vm.error());
        }
        if ((p > 0.5f) == (row.positive != 0)) ++correct;
    }
    return static_cast<float>(correct) / static_cast<float>(rows.size());
}

float evaluate_sense(RawFieldVM& vm, const std::vector<SenseExample>& rows,
                     const Vocab& vocab) {
    std::size_t correct = 0;
    for (const SenseExample& row : rows) {
        const SenseTokenized t = sense_tokenize(row.sentence, "bank", vocab);
        float p0 = 0.0f, loss0 = 0.0f;
        float p1 = 0.0f, loss1 = 0.0f;
        if (!vm.sense_step24_cached(t.tokens.size(), t.tokens, t.positions, 0,
                                    0.0f, 0.0f, p0, loss0) ||
            !vm.sense_step24_cached(t.tokens.size(), t.tokens, t.positions, 1,
                                    0.0f, 0.0f, p1, loss1)) {
            throw std::runtime_error(vm.error());
        }
        const std::uint8_t predicted = p1 > p0 ? 1 : 0;
        if (predicted == row.target) ++correct;
    }
    return static_cast<float>(correct) / static_cast<float>(rows.size());
}

} // namespace

int main() {
    const std::vector<std::string> train_names = {
        "ada", "bea", "cory", "dina", "elan", "faye", "gail", "hugo",
        "iris", "juno", "kira", "lora", "mira", "nora", "opal", "pavi",
        "quinn", "ravi", "sara", "tova", "uma", "vera", "wade", "xena"};
    const std::vector<std::string> dev_names = {
        "kato", "lena", "mavi", "navi", "orna", "pato",
        "reno", "sumi", "tali", "vito", "wila", "yori"};
    const std::vector<std::string> test_names = {
        "yara", "zena", "arun", "brin", "cato", "daro",
        "esme", "finn", "gora", "hexi", "ivon", "jace"};

    const auto train = role_corpus(train_names);
    const auto dev = role_corpus(dev_names);
    const auto test = role_corpus(test_names);
    const Vocab role_vocab = role_vocabulary(train);
    const std::vector<std::uint8_t> relation_index = {0, 1};

    std::mt19937 rng(20261109);
    std::vector<std::array<float, 24>> words(64);
    for (auto& w : words) w = random_vector(rng, 0.10f);
    std::array<std::array<float, 24>, 4> gates{};
    for (auto& gate : gates) gate = random_vector(rng, 0.02f);
    for (auto& gate : gates)
        for (float& v : gate) v += 1.0f;
    std::array<float, 24> bias{}, order{};
    std::vector<std::array<float, 24>> relations(2);
    relations[0] = random_vector(rng, 0.05f);
    relations[1] = random_vector(rng, 0.05f);
    std::vector<float> relation_bias(2, 0.0f);
    const auto role_initial_words = words;
    const auto role_initial_gates = gates;
    const auto role_initial_bias = bias;
    const auto role_initial_order = order;
    const auto role_initial_relations = relations;
    const auto role_initial_relation_bias = relation_bias;

    RawFieldVM role_vm("build/field_driver.nan");
    if (!role_vm.init_context24(words, gates, bias, order) ||
        !role_vm.init_role24k(relations, relation_bias)) {
        std::cerr << role_vm.error() << "\n";
        return 1;
    }
    constexpr std::size_t kRoleEpochs = 90;
    constexpr float kRoleLearningRate = 0.065f;
    for (std::size_t epoch = 0; epoch < kRoleEpochs; ++epoch) {
        for (const RoleExample& row : train) {
            const RoleTokenized t = role_tokenize(row.sentence, row.subject,
                                                  row.object, role_vocab);
            const std::uint8_t rel =
                relation_index[row.relation == "transfer" ? 0 : 1];
            float p = 0.0f, d = 0.0f;
            if (!role_vm.role_step24k_cached(
                    t.tokens.size(), t.tokens, t.positions, rel, row.positive,
                    kRoleLearningRate, t.orientation, p, d)) {
                std::cerr << role_vm.error() << "\n";
                return 1;
            }
        }
    }
    const float role_dev = evaluate_role(role_vm, dev, relation_index, role_vocab);
    const float role_test = evaluate_role(role_vm, test, relation_index, role_vocab);

    std::vector<std::array<float, 24>> saved_role_words;
    std::array<std::array<float, 24>, 4> saved_role_gates{};
    std::array<float, 24> saved_role_bias{}, saved_role_order{};
    std::vector<std::array<float, 24>> saved_relation_heads;
    std::vector<float> saved_relation_bias;
    if (!role_vm.read_context24(saved_role_words, saved_role_gates,
                                saved_role_bias, saved_role_order) ||
        !role_vm.read_role24k_state(saved_relation_heads, saved_relation_bias)) {
        std::cerr << role_vm.error() << "\n";
        return 1;
    }
    RawFieldVM restored_role_vm("build/field_driver.nan");
    if (!restored_role_vm.init_context24(saved_role_words, saved_role_gates,
                                         saved_role_bias, saved_role_order) ||
        !restored_role_vm.init_role24k(saved_relation_heads,
                                       saved_relation_bias)) {
        std::cerr << restored_role_vm.error() << "\n";
        return 1;
    }
    const float role_restored = evaluate_role(restored_role_vm, test,
                                              relation_index, role_vocab);

    std::vector<RoleExample> shuffled_role = train;
    std::vector<std::uint8_t> shuffled_labels;
    for (const RoleExample& row : shuffled_role)
        shuffled_labels.push_back(row.positive);
    std::mt19937 role_control_rng(20261109);
    std::shuffle(shuffled_labels.begin(), shuffled_labels.end(), role_control_rng);
    for (std::size_t i = 0; i < shuffled_role.size(); ++i)
        shuffled_role[i].positive = shuffled_labels[i];
    RawFieldVM role_control_vm("build/field_driver.nan");
    if (!role_control_vm.init_context24(role_initial_words, role_initial_gates,
                                        role_initial_bias, role_initial_order) ||
        !role_control_vm.init_role24k(role_initial_relations,
                                      role_initial_relation_bias)) {
        std::cerr << role_control_vm.error() << "\n";
        return 1;
    }
    for (std::size_t epoch = 0; epoch < kRoleEpochs; ++epoch) {
        for (const RoleExample& row : shuffled_role) {
            const RoleTokenized t = role_tokenize(row.sentence, row.subject,
                                                  row.object, role_vocab);
            const std::uint8_t rel =
                relation_index[row.relation == "transfer" ? 0 : 1];
            float p = 0.0f, d = 0.0f;
            if (!role_control_vm.role_step24k_cached(
                    t.tokens.size(), t.tokens, t.positions, rel, row.positive,
                    kRoleLearningRate, t.orientation, p, d)) {
                std::cerr << role_control_vm.error() << "\n";
                return 1;
            }
        }
    }
    const float role_control = evaluate_role(role_control_vm, test,
                                             relation_index, role_vocab);

    const std::vector<SenseExample> sense_prototypes = {
        {"the bank approved a loan", 0},
        {"cash was deposited at the bank", 0},
        {"the bank handled money and credit", 0},
        {"a teller served customers inside the bank", 0},
        {"she borrowed money from the bank", 0},
        {"the bank issued credit to clients", 0},
        {"the water rushed past the bank", 1},
        {"a boat floated beside the bank", 1},
        {"the bank was wet with river mud", 1},
        {"the stream flowed along the bank", 1},
        {"the bank collapsed during the flood", 1},
        {"the bank had reeds beside the river", 1}};
    const std::vector<SenseExample> sense_test = {
        {"the customer requested a loan at the bank", 0},
        {"the bank counted cash and money", 0},
        {"the teller went back to the bank", 0},
        {"credit was provided by the bank", 0},
        {"the boat moved by the bank in water", 1},
        {"the bank was covered with mud", 1},
        {"a river stream flowed near the bank", 1},
        {"the flood carried reeds across the bank", 1}};
    std::vector<SenseExample> sense_train;
    for (int repetition = 0; repetition < 10; ++repetition)
        for (const SenseExample& row : sense_prototypes)
            sense_train.push_back(row);
    const Vocab sense_vocab = sense_vocabulary(sense_train, "bank");

    std::mt19937 sense_rng(20261110);
    std::vector<std::array<float, 24>> sense_words(64);
    for (auto& w : sense_words) w = random_vector(sense_rng, 0.10f);
    std::array<std::array<float, 24>, 4> sense_gates{};
    for (auto& gate : sense_gates) gate = random_vector(sense_rng, 0.02f);
    for (auto& gate : sense_gates)
        for (float& v : gate) v += 1.0f;
    std::array<float, 24> sense_bias{}, sense_order{};
    std::vector<std::array<float, 24>> sense_heads(2);
    sense_heads[0] = random_vector(sense_rng, 0.05f);
    sense_heads[1] = random_vector(sense_rng, 0.05f);
    std::vector<float> sense_biases(2, 0.0f);
    const auto sense_initial_words = sense_words;
    const auto sense_initial_gates = sense_gates;
    const auto sense_initial_bias = sense_bias;
    const auto sense_initial_order = sense_order;
    const auto sense_initial_heads = sense_heads;
    const auto sense_initial_biases = sense_biases;

    RawFieldVM sense_vm("build/field_driver.nan");
    if (!sense_vm.init_context24(sense_words, sense_gates, sense_bias,
                                 sense_order) ||
        !sense_vm.init_sense24(sense_heads, sense_biases)) {
        std::cerr << sense_vm.error() << "\n";
        return 1;
    }
    constexpr std::size_t kSenseEpochs = 120;
    constexpr float kSenseLearningRate = 0.07f;
    for (std::size_t epoch = 0; epoch < kSenseEpochs; ++epoch) {
        for (const SenseExample& row : sense_train) {
            const SenseTokenized t = sense_tokenize(row.sentence, "bank",
                                                    sense_vocab);
            float p = 0.0f, loss = 0.0f;
            if (!sense_vm.sense_step24_cached(t.tokens.size(), t.tokens,
                                              t.positions, row.target,
                                              kSenseLearningRate, 0.0f, p, loss)) {
                std::cerr << sense_vm.error() << "\n";
                return 1;
            }
        }
    }
    const float sense_accuracy = evaluate_sense(sense_vm, sense_test, sense_vocab);

    std::vector<std::array<float, 24>> saved_sense_words;
    std::array<std::array<float, 24>, 4> saved_sense_gates{};
    std::array<float, 24> saved_sense_bias{}, saved_sense_order{};
    std::vector<std::array<float, 24>> saved_sense_heads;
    std::vector<float> saved_sense_biases;
    if (!sense_vm.read_context24(saved_sense_words, saved_sense_gates,
                                 saved_sense_bias, saved_sense_order) ||
        !sense_vm.read_sense24(saved_sense_heads, saved_sense_biases)) {
        std::cerr << sense_vm.error() << "\n";
        return 1;
    }
    RawFieldVM restored_sense_vm("build/field_driver.nan");
    if (!restored_sense_vm.init_context24(saved_sense_words, saved_sense_gates,
                                          saved_sense_bias, saved_sense_order) ||
        !restored_sense_vm.init_sense24(saved_sense_heads, saved_sense_biases)) {
        std::cerr << restored_sense_vm.error() << "\n";
        return 1;
    }
    const float sense_restored = evaluate_sense(restored_sense_vm, sense_test,
                                                sense_vocab);

    std::vector<SenseExample> shuffled_sense = sense_train;
    std::vector<std::uint8_t> shuffled_sense_targets;
    for (const SenseExample& row : shuffled_sense)
        shuffled_sense_targets.push_back(row.target);
    std::mt19937 sense_control_rng(20261110);
    std::shuffle(shuffled_sense_targets.begin(), shuffled_sense_targets.end(),
                 sense_control_rng);
    for (std::size_t i = 0; i < shuffled_sense.size(); ++i)
        shuffled_sense[i].target = shuffled_sense_targets[i];
    RawFieldVM sense_control_vm("build/field_driver.nan");
    if (!sense_control_vm.init_context24(sense_initial_words,
                                         sense_initial_gates,
                                         sense_initial_bias, sense_initial_order) ||
        !sense_control_vm.init_sense24(sense_initial_heads,
                                       sense_initial_biases)) {
        std::cerr << sense_control_vm.error() << "\n";
        return 1;
    }
    for (std::size_t epoch = 0; epoch < kSenseEpochs; ++epoch) {
        for (const SenseExample& row : shuffled_sense) {
            const SenseTokenized t = sense_tokenize(row.sentence, "bank",
                                                    sense_vocab);
            float p = 0.0f, loss = 0.0f;
            if (!sense_control_vm.sense_step24_cached(
                    t.tokens.size(), t.tokens, t.positions, row.target,
                    kSenseLearningRate, 0.0f, p, loss)) {
                std::cerr << sense_control_vm.error() << "\n";
                return 1;
            }
        }
    }
    const float sense_control = evaluate_sense(sense_control_vm, sense_test,
                                               sense_vocab);

    bool inverted = false;
    for (std::size_t i = 0; i + 1 < test.size(); i += 2) {
        const RoleTokenized yes_tokens = role_tokenize(
            test[i].sentence, test[i].subject, test[i].object, role_vocab);
        const RoleTokenized no_tokens = role_tokenize(
            test[i + 1].sentence, test[i + 1].subject, test[i + 1].object,
            role_vocab);
        const std::uint8_t rel =
            relation_index[test[i].relation == "transfer" ? 0 : 1];
        float p_yes = 0.0f, p_no = 0.0f, d = 0.0f;
        if (!role_vm.role_step24k_cached(yes_tokens.tokens.size(),
                                         yes_tokens.tokens, yes_tokens.positions,
                                         rel, 0.0f, 0.0f, yes_tokens.orientation,
                                         p_yes, d) ||
            !role_vm.role_step24k_cached(no_tokens.tokens.size(),
                                         no_tokens.tokens, no_tokens.positions,
                                         rel, 0.0f, 0.0f, no_tokens.orientation,
                                         p_no, d)) {
            std::cerr << role_vm.error() << "\n";
            return 1;
        }
        if (p_yes > p_no) {
            inverted = true;
            break;
        }
    }

    const bool role_ok = role_dev >= 0.75f && role_test >= 0.75f && inverted &&
                         role_restored == role_test &&
                         role_test > role_control + 0.15f;
    const bool sense_ok = sense_accuracy >= 0.875f &&
                          sense_restored == sense_accuracy &&
                          sense_accuracy > sense_control + 0.2f;
    std::cout << (role_ok && sense_ok ? "RAW_CONTEXTUAL PASS" : "RAW_CONTEXTUAL FAIL")
              << " role_train=" << train.size()
              << " role_dev=" << dev.size()
              << " role_test=" << test.size()
              << " role_dev_accuracy=" << role_dev
              << " role_test_accuracy=" << role_test
              << " role_inversion=" << (inverted ? "yes" : "no")
              << " role_restored_accuracy=" << role_restored
              << " role_shuffled_accuracy=" << role_control
              << " role_updates=" << train.size() * kRoleEpochs
              << " sense_train=" << sense_train.size()
              << " sense_test=" << sense_test.size()
              << " sense_accuracy=" << sense_accuracy
              << " sense_restored_accuracy=" << sense_restored
              << " sense_shuffled_accuracy=" << sense_control
              << " sense_updates=" << sense_train.size() * kSenseEpochs
              << "\n";
    return role_ok && sense_ok ? 0 : 1;
}
