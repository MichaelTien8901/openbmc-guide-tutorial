# Example meson.build for OpenBMC unit tests
# This file demonstrates test configuration patterns

project(
    'openbmc-testing-example',
    'cpp',
    version: '1.0',
    default_options: [
        'cpp_std=c++20',
        'warning_level=3',
    ],
)

# =============================================================================
# Dependencies
# =============================================================================

# GTest and GMock (required for unit tests)
gtest_dep = dependency('gtest', main: false, required: true)
gmock_dep = dependency('gmock', required: true)

# Optional: sdbusplus for D-Bus mocking (when testing D-Bus services)
# sdbusplus_dep = dependency('sdbusplus', required: true)

# =============================================================================
# Test Executable
# =============================================================================

# Define test sources
test_sources = [
    'sensor_test.cpp',
]

# Build test executable
test_exe = executable(
    'sensor-tests',
    test_sources,
    dependencies: [
        gtest_dep,
        gmock_dep,
    ],
    # Include source headers
    # include_directories: include_directories('../src'),
)

# Register with Meson's test framework
test('sensor-unit-tests', test_exe)

# =============================================================================
# Code Coverage (Optional)
# =============================================================================

# To enable coverage, add to meson_options.txt:
#   option('coverage', type: 'boolean', value: false)
#
# Then configure build with:
#   meson setup builddir -Dcoverage=true
#
# Generate report with:
#   meson test -C builddir
#   lcov --capture --directory builddir --output-file coverage.info
#   genhtml coverage.info --output-directory coverage-report

if get_option('b_coverage')
    message('Code coverage enabled')
endif
