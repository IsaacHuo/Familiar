#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <simulator-udid> <derived-data-path>" >&2
    exit 64
fi

simulator_id="$1"
derived_data="$2"
repository_root="$(cd "$(dirname "$0")/.." && pwd)"
results_directory="$derived_data/ReleaseTestResults/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$results_directory"

suites=(
    FamiliarAssistantTurnPersistenceTests
    FamiliarBaselineTests
    FamiliarBeautifulUIRuntimeTests
    FamiliarBenchmarkTests
    FamiliarEventKitPolicyTests
    FamiliarNativeFirstArchitectureTests
    FamiliarPersistenceReleaseTests
    FamiliarPinServiceTests
    FamiliarPlanCompletionTests
    FamiliarProjectTests
    FamiliarProjectWorkspaceTests
    FamiliarReleaseComplianceTests
    FamiliarReleaseToolTests
    FamiliarRuntimeTests
    FamiliarSearchProviderTests
    FamiliarSelectionPresentationTests
    FamiliarSkillsTests
    FamiliarSurfaceTests
    FamiliarToolContractTests
    FamiliarWP1Tests
    FamiliarWP4Tests
    FamiliarWP5Tests
    FamiliarWP6WP7Tests
    FamiliarWebTests
)

run_test_identifier() {
    local identifier="$1"
    local result_name="${identifier//\//-}"
    echo "Running ${identifier}"
    xcodebuild -quiet \
        -project "$repository_root/familiar.xcodeproj" \
        -scheme Familiar \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=${simulator_id}" \
        -derivedDataPath "$derived_data" \
        -disableAutomaticPackageResolution \
        CODE_SIGNING_ALLOWED=NO \
        COMPILER_INDEX_STORE_ENABLE=NO \
        -parallel-testing-enabled NO \
        -resultBundlePath "$results_directory/${result_name}.xcresult" \
        -only-testing:"$identifier" \
        test-without-building
}

for suite in "${suites[@]}"; do
    run_test_identifier "FamiliarTests/${suite}"
done

run_test_identifier "FamiliarUITests"

echo "All release test suites passed. Results: $results_directory"
