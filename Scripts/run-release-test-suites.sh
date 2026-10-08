#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"

simulator_suites=(
    FamiliarAppleNativeToolTests
    FamiliarBluetoothLifecycleTests
    FamiliarAssistantTurnPersistenceTests
    FamiliarBaselineTests
    FamiliarBeautifulUIRuntimeTests
    FamiliarBenchmarkTests
    FamiliarEventKitPolicyTests
    FamiliarHarnessTests
    FamiliarLazyToolTests
    FamiliarCommitBoundaryTests
    FamiliarSendPreflightTests
    FamiliarWebRetentionTests
    FamiliarAuthorizationBoundaryTests
    FamiliarModelSelectionTests
    FamiliarSubmissionBoundaryTests
    FamiliarDesignSystemTests
    FamiliarStreamingObservationTests
    FamiliarStreamingPresentationTests
    FamiliarMarkdownWebKitTests
    FamiliarTimelinePerformanceTests
    FamiliarChatScrollTests
    FamiliarChatTestProviderTests
    FamiliarImportContractsTests
    FamiliarFunctionalFilesTests
    FamiliarFilePathBoundaryTests
    FamiliarGroupBoundaryTests
    FamiliarMemoryTests
    FamiliarFollowUpTests
    FamiliarNativeFirstArchitectureTests
    FamiliarNativeOutputToolTests
    FamiliarPersistenceReleaseTests
    FamiliarPinServiceTests
    FamiliarPlanCompletionTests
    FamiliarProjectTests
    FamiliarProjectWorkspaceTests
    FamiliarReleaseComplianceTests
    FamiliarReleaseToolTests
    FamiliarRuntimeTests
    FamiliarRuntimePresentationTests
    FamiliarSearchProviderTests
    FamiliarSelectionPresentationTests
    FamiliarSkillsTests
    FamiliarSurfaceTests
    FamiliarToolContractTests
    FamiliarUIFeedbackTests
    FamiliarWP1Tests
    FamiliarWP4Tests
    FamiliarWP5Tests
    FamiliarWP6WP7Tests
    FamiliarWebTests
    FamiliarWebEvidenceTests
    FamiliarWorkspaceShellTests
)


# These require a prebuilt signed device host. Simulator skips are not acceptance.
device_suites=(
    FamiliarDeviceRuntimeTests
    FamiliarSignedSubmissionTests
    FamiliarNativeDeviceTests
)

live_service_suites=(
    FamiliarWebLiveTests
    FamiliarISHSimulatorRuntimeTests
)

check_suite_list() {
    python3 - "$repository_root" "$0" <<'PYLIST'
import re, sys
from pathlib import Path
root=Path(sys.argv[1])
source=set()
for path in (root/'FamiliarTests').glob('*.swift'):
    text=path.read_text()
    source.update(re.findall(r'@Suite\b[\s\S]*?\b(?:struct|class)\s+(\w+)',text))
    source.update(re.findall(r'class\s+(\w+)\s*:\s*XCTestCase',text))
script=Path(sys.argv[2]).read_text()
sim=re.findall(r'^    (\w+)\s*$',re.search(r'simulator_suites=\(([\s\S]*?)\n\)',script).group(1),re.M)
device=re.findall(r'^    (\w+)\s*$',re.search(r'device_suites=\(([\s\S]*?)\n\)',script).group(1),re.M)
live=re.findall(r'^    (\w+)\s*$',re.search(r'live_service_suites=\(([\s\S]*?)\n\)',script).group(1),re.M)
listed=sim+device+live
missing=source-set(listed)
obsolete=set(listed)-source
if missing or obsolete or len(listed)!=len(set(listed)):
    raise SystemExit(f'Test list mismatch: missing={sorted(missing)}, obsolete={sorted(obsolete)}, duplicates={len(listed)-len(set(listed))}')
print(f'Test inventory: {len(sim)} Simulator suites, {len(device)} signed-device suites, {len(live)} explicit live-service suites, plus the complete FamiliarUITests target.')
PYLIST
}

if [[ "${1:-}" == "--check-list" ]]; then
    check_suite_list
    exit 0
fi

platform="iOS Simulator"
signing="NO"
selected_suites=("${simulator_suites[@]}")
if [[ "${1:-}" == "--device" ]]; then
    shift
    platform="iOS"
    signing="YES"
    selected_suites=("${device_suites[@]}")
fi
if [[ "${1:-}" == "--live" ]]; then
    shift
    selected_suites=("${live_service_suites[@]}")
    live_mode="YES"
fi
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 [--device|--live] <destination-udid> <prebuilt-derived-data-path> | --check-list" >&2
    exit 64
fi
check_suite_list
destination_id="$1"
derived_data="$2"
results_directory="$derived_data/ReleaseTestResults/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$results_directory"

run_test_identifiers() {
    local result_name="$1"
    shift
    local selections=()
    local identifier
    for identifier in "$@"; do selections+=("-only-testing:$identifier"); done
    local execution_status=0
    local bundle="$results_directory/${result_name}.xcresult"
    echo "Running ${result_name} on ${platform}"
    xcodebuild -quiet \
        -project "$repository_root/familiar.xcodeproj" \
        -scheme Familiar \
        -configuration Debug \
        -destination "platform=${platform},id=${destination_id}" \
        -derivedDataPath "$derived_data" \
        -disableAutomaticPackageResolution \
        CODE_SIGNING_ALLOWED="$signing" \
        COMPILER_INDEX_STORE_ENABLE=NO \
        -parallel-testing-enabled NO \
        -resultBundlePath "$bundle" \
        "${selections[@]}" \
        test-without-building || execution_status=$?
    xcrun xcresulttool get test-results summary --path "$bundle" > "$bundle.summary.json"
    python3 - "$bundle.summary.json" <<'PYRESULT'
import json, sys
from pathlib import Path
summary=json.loads(Path(sys.argv[1]).read_text())
keys=('totalTestCount','passedTests','failedTests','skippedTests','expectedFailures')
if any(type(summary.get(key)) is not int for key in keys):
    raise SystemExit('Test result counts unavailable; completion is unverified.')
total,passed,failed,skipped,expected=(summary[key] for key in keys)
print(f'Tests: total={total}, passed={passed}, failed={failed}, skipped={skipped}, expectedFailures={expected}')
if total<=0 or passed!=total or failed or skipped or expected or summary.get('result')!='Passed':
    raise SystemExit('Selected suite did not fully pass; zero tests, skips and expected failures are not acceptance.')
PYRESULT
    if [[ $execution_status -ne 0 ]]; then return "$execution_status"; fi
}

identifiers=()
for suite in "${selected_suites[@]}"; do identifiers+=("FamiliarTests/$suite"); done
run_test_identifiers "all-selected-suites" "${identifiers[@]}"
if [[ "${live_mode:-NO}" == "YES" ]]; then
    echo "Live-service results are separate from deterministic and device acceptance. Results: $results_directory"
elif [[ "$platform" == "iOS Simulator" ]]; then
    run_test_identifiers "ui" "FamiliarUITests"
    echo "Selected Simulator suites passed. Signed-device/guest acceptance is separate. Results: $results_directory"
else
    echo "Selected signed-device suites passed. This does not complete real-provider or UI acceptance. Results: $results_directory"
fi
