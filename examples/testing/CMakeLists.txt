# CMakeLists.txt - Standalone GTest example for OpenBMC learning
#
# This builds the example tests without requiring OpenBMC SDK
#
# Usage:
#   mkdir build && cd build
#   cmake ..
#   make
#   ./sensor_tests

cmake_minimum_required(VERSION 3.14)
project(openbmc_gtest_examples VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Option to download GTest if not found
option(DOWNLOAD_GTEST "Download GoogleTest if not found" ON)

# Find or download GoogleTest
include(FetchContent)

if(DOWNLOAD_GTEST)
    message(STATUS "Downloading GoogleTest...")
    FetchContent_Declare(
        googletest
        GIT_REPOSITORY https://github.com/google/googletest.git
        GIT_TAG v1.14.0
    )
    # For Windows: Prevent overriding the parent project's compiler/linker settings
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(googletest)
else()
    find_package(GTest REQUIRED)
endif()

# Enable testing
enable_testing()

# Build the sensor test executable
add_executable(sensor_tests
    sensor_test.cpp
)

target_link_libraries(sensor_tests
    GTest::gtest
    GTest::gtest_main
    GTest::gmock
)

# Register with CTest
include(GoogleTest)
gtest_discover_tests(sensor_tests)

# Print build instructions
message(STATUS "")
message(STATUS "=== OpenBMC GTest Examples ===")
message(STATUS "Build with: cmake --build .")
message(STATUS "Run tests:  ctest --output-on-failure")
message(STATUS "Or run:     ./sensor_tests")
message(STATUS "")
