#include "nanlm/endpoint_evidence.hpp"
#include "test_util.hpp"

#include <limits>
#include <string>

using namespace nanlm;

namespace {
std::string event_id(char c) { return std::string(64, c); }
}

int main() {
    EndpointEvidenceFold fold;
    EndpointObservation clocked;
    clocked.endpoint = EndpointId::ClockedDemo;
    clocked.base_generation = 0;
    clocked.event_id = event_id('a');
    clocked.outcome_verified = false;
    clocked.active_heads = {7, 7, 8};

    CHECK(fold.observe(clocked) == EndpointIngestResult::Accepted);
    CHECK(fold.observe(clocked) == EndpointIngestResult::Duplicate);
    CHECK_EQ(fold.stats(EndpointId::ClockedDemo).observations, 1u);
    CHECK_EQ(fold.stats(EndpointId::ClockedDemo).evidence_only, 1u);
    CHECK_EQ(fold.feedback()[7], 0);
    CHECK_EQ(fold.feedback()[8], 0);

    EndpointObservation android;
    android.endpoint = EndpointId::MyAndroid;
    android.base_generation = 0;
    android.event_id = event_id('b');
    android.active_heads = {7, 7, 9};
    android.outcome_verified = true;
    android.correct = true;
    CHECK(fold.observe(android) == EndpointIngestResult::Accepted);
    CHECK_EQ(fold.stats(EndpointId::MyAndroid).correct, 1u);
    CHECK_EQ(fold.feedback()[7], 0);

    for (char id : {'c', 'd', 'e', 'f', '0', '1', '2'}) {
        android.event_id = event_id(id);
        CHECK(fold.observe(android) == EndpointIngestResult::Accepted);
    }
    CHECK_EQ(fold.feedback()[7], 1);

    EndpointObservation stale = android;
    stale.event_id = event_id('3');
    stale.base_generation = 1;
    CHECK(fold.observe(stale) == EndpointIngestResult::StaleGeneration);
    CHECK(!fold.advance_generation(2));
    CHECK(fold.advance_generation(1));
    stale.base_generation = 1;
    CHECK(fold.observe(stale) == EndpointIngestResult::Accepted);
    CHECK_EQ(fold.stats(EndpointId::MyAndroid).correct, 9u);

    EndpointObservation bad;
    bad.endpoint = EndpointId::ClockedDemo;
    bad.base_generation = 1;
    bad.event_id = "not-a-digest";
    CHECK(fold.observe(bad) == EndpointIngestResult::Invalid);

    CHECK_EQ(fold.unique_events(), 10u);

    EndpointEvidenceFold equivalent;
    CHECK(equivalent.observe(clocked) == EndpointIngestResult::Accepted);
    android.base_generation = 0;
    android.event_id = event_id('b');
    CHECK(equivalent.observe(android) == EndpointIngestResult::Accepted);
    for (char id : {'c', 'd', 'e', 'f', '0', '1', '2'}) {
        android.event_id = event_id(id);
        CHECK(equivalent.observe(android) == EndpointIngestResult::Accepted);
    }
    stale.base_generation = 0;
    CHECK(equivalent.observe(stale) == EndpointIngestResult::Accepted);
    CHECK(equivalent.advance_generation(1));
    CHECK(fold.digest() == equivalent.digest());
    CHECK(!fold.advance_generation(std::numeric_limits<std::uint64_t>::max()));

    return test_done("overbootstrap endpoint evidence fold");
}
