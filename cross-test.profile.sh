# Settings-only profile for the full 53-target cross-test matrix and test step.
# The harness executes targets with runners; others are build-only, not passes.

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4
CROSS_BUILD_TIMEOUT=3600
CROSS_TIMEOUT=1800
