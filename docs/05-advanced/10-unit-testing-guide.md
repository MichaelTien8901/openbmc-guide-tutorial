---
layout: default
title: Unit Testing Guide
parent: Advanced Topics
nav_order: 10
difficulty: advanced
prerequisites:
  - dbus-guide
  - development-workflow
---

# Unit Testing Guide
{: .no_toc }

Write and run unit tests for OpenBMC services using GTest/GMock.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Unit testing is essential for OpenBMC development. All code submitted upstream must include unit tests. OpenBMC uses:

- **GTest** - Google Test framework for C++ unit tests
- **GMock** - Google Mock for creating mock objects
- **Meson** - Build system with native test support

This guide covers writing tests, mocking D-Bus interfaces, and running tests in OpenBMC.

### Why Unit Test?

| Benefit | Description |
|---------|-------------|
| **Upstream Requirement** | Code without tests is rejected |
| **Catch Regressions** | Automated testing prevents bugs |
| **Document Behavior** | Tests show expected usage |
| **Enable Refactoring** | Safe code changes with test coverage |

---

## GTest/GMock Setup with Meson

### Meson Configuration

Add test configuration to your service's `meson.build`:

```meson
# Enable testing
gtest_dep = dependency('gtest', main: true, required: true)
gmock_dep = dependency('gmock', required: true)

# Define test executable
test_src = [
    'test/main_test.cpp',
    'test/service_test.cpp',
]

test_exe = executable(
    'test-myservice',
    test_src,
    dependencies: [
        gtest_dep,
        gmock_dep,
        sdbusplus_dep,
        phosphor_logging_dep,
    ],
    include_directories: include_directories('src'),
)

# Register test with Meson
test('myservice-tests', test_exe)
```

### Project Structure

Organize test files alongside source:

```
my-service/
├── meson.build
├── src/
│   ├── main.cpp
│   └── service.cpp
└── test/
    ├── main_test.cpp      # GTest main entry
    ├── service_test.cpp   # Service unit tests
    └── mocks/
        └── mock_dbus.hpp  # D-Bus mocks
```

### Test Main Entry Point

Create `test/main_test.cpp`:

```cpp
#include <gtest/gtest.h>

int main(int argc, char** argv)
{
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
```

---

## Writing GTest Tests

### Basic Test Structure

```cpp
#include <gtest/gtest.h>
#include "service.hpp"

// Simple test case
TEST(ServiceTest, InitializesCorrectly)
{
    Service svc;
    EXPECT_TRUE(svc.isInitialized());
}

// Test with expected value
TEST(ServiceTest, ReturnsDefaultValue)
{
    Service svc;
    EXPECT_EQ(svc.getValue(), 0);
}
```

### Test Fixtures (TEST_F)

Use fixtures for common setup/teardown:

```cpp
#include <gtest/gtest.h>
#include "sensor_manager.hpp"

class SensorManagerTest : public ::testing::Test
{
  protected:
    void SetUp() override
    {
        // Runs before each test
        manager = std::make_unique<SensorManager>();
    }

    void TearDown() override
    {
        // Runs after each test
        manager.reset();
    }

    std::unique_ptr<SensorManager> manager;
};

TEST_F(SensorManagerTest, AddsSensorSuccessfully)
{
    EXPECT_TRUE(manager->addSensor("CPU_Temp", 50.0));
    EXPECT_EQ(manager->getSensorCount(), 1);
}

TEST_F(SensorManagerTest, RejectsDuplicateSensor)
{
    manager->addSensor("CPU_Temp", 50.0);
    EXPECT_FALSE(manager->addSensor("CPU_Temp", 60.0));
}
```

### Common Assertions

| Assertion | Description |
|-----------|-------------|
| `EXPECT_TRUE(cond)` | Condition is true |
| `EXPECT_FALSE(cond)` | Condition is false |
| `EXPECT_EQ(a, b)` | Values are equal |
| `EXPECT_NE(a, b)` | Values are not equal |
| `EXPECT_LT(a, b)` | a < b |
| `EXPECT_GT(a, b)` | a > b |
| `EXPECT_THROW(expr, type)` | Expression throws exception |
| `EXPECT_NO_THROW(expr)` | Expression doesn't throw |
| `ASSERT_*` | Same as EXPECT but stops test on failure |

---

## GMock Basics

### Creating Mock Classes

```cpp
#include <gmock/gmock.h>

// Interface to mock
class SensorInterface
{
  public:
    virtual ~SensorInterface() = default;
    virtual double getValue() = 0;
    virtual void setValue(double value) = 0;
    virtual bool isValid() const = 0;
};

// Mock implementation
class MockSensor : public SensorInterface
{
  public:
    MOCK_METHOD(double, getValue, (), (override));
    MOCK_METHOD(void, setValue, (double value), (override));
    MOCK_METHOD(bool, isValid, (), (const, override));
};
```

### Using Mock Objects

```cpp
#include <gmock/gmock.h>
#include <gtest/gtest.h>

using ::testing::Return;
using ::testing::_;

TEST(ControllerTest, ReadsFromSensor)
{
    MockSensor mockSensor;

    // Set up expectations
    EXPECT_CALL(mockSensor, getValue())
        .WillOnce(Return(45.5));

    Controller ctrl(&mockSensor);
    EXPECT_EQ(ctrl.readTemperature(), 45.5);
}

TEST(ControllerTest, HandlesSensorFailure)
{
    MockSensor mockSensor;

    EXPECT_CALL(mockSensor, isValid())
        .WillOnce(Return(false));

    Controller ctrl(&mockSensor);
    EXPECT_THROW(ctrl.readTemperature(), std::runtime_error);
}
```

### Common GMock Matchers

| Matcher | Description |
|---------|-------------|
| `Return(value)` | Return specified value |
| `_` | Match any argument |
| `Eq(value)` | Argument equals value |
| `Gt(value)` | Argument greater than value |
| `WillOnce(action)` | Perform action once |
| `WillRepeatedly(action)` | Perform action every time |
| `Times(n)` | Expect exactly n calls |

---

## D-Bus Mocking with sdbus++

### Why Mock D-Bus?

Unit tests should be isolated. Mocking D-Bus:
- Avoids requiring running D-Bus daemon
- Controls responses for testing edge cases
- Enables testing without real hardware

### sdbus++ Mock Utilities

OpenBMC's sdbus++ provides mock helpers. Include the mock headers:

```cpp
#include <sdbusplus/test/sdbus_mock.hpp>
```

### Example: Mocking D-Bus Method Calls

```cpp
#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <sdbusplus/test/sdbus_mock.hpp>

using ::testing::_;
using ::testing::Return;

class DBusServiceTest : public ::testing::Test
{
  protected:
    sdbusplus::SdBusMock sdbusMock;

    void SetUp() override
    {
        // Set up mock bus
    }
};

TEST_F(DBusServiceTest, CallsRemoteMethod)
{
    // Expect D-Bus method call
    EXPECT_CALL(sdbusMock,
        sd_bus_call_method(_, _, _, _, _, _, _))
        .WillOnce(Return(0));

    auto bus = sdbusplus::get_mocked_new(&sdbusMock);
    MyService svc(bus);

    EXPECT_NO_THROW(svc.callRemoteMethod());
}
```

### Mocking Property Gets/Sets

```cpp
TEST_F(DBusServiceTest, GetsPropertyValue)
{
    // Mock property read
    EXPECT_CALL(sdbusMock,
        sd_bus_get_property(_, _, _, _, _, _, _))
        .WillOnce([](sd_bus*, const char*, const char*,
                     const char*, sd_bus_error*, sd_bus_message**,
                     const char*) {
            // Return mocked property value
            return 0;
        });

    auto bus = sdbusplus::get_mocked_new(&sdbusMock);
    MyService svc(bus);

    EXPECT_EQ(svc.getRemoteProperty(), expectedValue);
}
```

### Verifying D-Bus Interactions

```cpp
TEST_F(DBusServiceTest, EmitsSignalOnChange)
{
    EXPECT_CALL(sdbusMock,
        sd_bus_emit_signal(_, _, _, _, _))
        .Times(1);

    auto bus = sdbusplus::get_mocked_new(&sdbusMock);
    MyService svc(bus);

    svc.updateValue(newValue);  // Should emit signal
}
```

---

## Running Tests

### Via Meson (Local Build)

```bash
# Configure build with tests enabled
meson setup builddir -Dtests=enabled

# Build and run tests
meson test -C builddir

# Run with verbose output
meson test -C builddir -v

# Run specific test
meson test -C builddir myservice-tests
```

### Via Bitbake

```bash
# Run tests for a specific recipe
bitbake phosphor-logging -c test

# Run tests and keep build directory
bitbake phosphor-logging -c test -f

# Check test results
cat tmp/work/*/phosphor-logging/*/temp/log.do_test
```

### With SDK (Local Development)

```bash
# Source SDK environment
source /opt/openbmc-phosphor/*/environment-setup-*

# Build and test locally
meson setup builddir --cross-file=cross.txt
meson test -C builddir
```

### Interpreting Test Output

```
[==========] Running 5 tests from 2 test suites.
[----------] 3 tests from ServiceTest
[ RUN      ] ServiceTest.InitializesCorrectly
[       OK ] ServiceTest.InitializesCorrectly (0 ms)
[ RUN      ] ServiceTest.ReturnsDefaultValue
[       OK ] ServiceTest.ReturnsDefaultValue (0 ms)
[ RUN      ] ServiceTest.HandlesError
[  FAILED  ] ServiceTest.HandlesError (1 ms)
[----------] 2 tests from ControllerTest
...
[==========] 5 tests from 2 test suites ran. (10 ms total)
[  PASSED  ] 4 tests.
[  FAILED  ] 1 test.
```

---

## Test Coverage

### Enabling Coverage in Meson

Add to `meson.build`:

```meson
if get_option('coverage')
    add_project_arguments('-fprofile-arcs', '-ftest-coverage',
                          language: 'cpp')
    add_project_link_arguments('-lgcov', language: 'cpp')
endif
```

Add to `meson_options.txt`:

```meson
option('coverage', type: 'boolean', value: false,
       description: 'Enable code coverage')
```

### Generating Coverage Reports

```bash
# Build with coverage enabled
meson setup builddir -Dcoverage=true
meson compile -C builddir

# Run tests
meson test -C builddir

# Generate coverage report with lcov
lcov --capture --directory builddir \
     --output-file coverage.info

# Generate HTML report
genhtml coverage.info --output-directory coverage-report

# View report
xdg-open coverage-report/index.html
```

### Coverage Report Interpretation

| Metric | Target | Description |
|--------|--------|-------------|
| Line Coverage | >80% | Lines executed by tests |
| Function Coverage | >90% | Functions called by tests |
| Branch Coverage | >70% | Decision branches taken |

---

## Practical Example: phosphor-logging

The `phosphor-logging` repository demonstrates OpenBMC testing patterns.

### Test Structure

```
phosphor-logging/
├── test/
│   ├── meson.build
│   ├── log_manager_test.cpp
│   ├── elog_test.cpp
│   └── remote_logging_test.cpp
```

### Example Test from phosphor-logging

```cpp
#include <gtest/gtest.h>
#include "log_manager.hpp"

class LogManagerTest : public ::testing::Test
{
  protected:
    void SetUp() override
    {
        // Create temporary log directory
        tempDir = std::filesystem::temp_directory_path() / "test-logs";
        std::filesystem::create_directories(tempDir);
    }

    void TearDown() override
    {
        std::filesystem::remove_all(tempDir);
    }

    std::filesystem::path tempDir;
};

TEST_F(LogManagerTest, CreatesLogEntry)
{
    LogManager manager(tempDir);

    auto id = manager.createEntry(
        "Test message",
        Entry::Level::Informational);

    EXPECT_GT(id, 0);
    EXPECT_TRUE(manager.hasEntry(id));
}

TEST_F(LogManagerTest, DeletesLogEntry)
{
    LogManager manager(tempDir);
    auto id = manager.createEntry("Test", Entry::Level::Error);

    EXPECT_TRUE(manager.deleteEntry(id));
    EXPECT_FALSE(manager.hasEntry(id));
}
```

### Running phosphor-logging Tests

```bash
# Clone and build
git clone https://github.com/openbmc/phosphor-logging
cd phosphor-logging

# Build with tests
meson setup builddir -Dtests=enabled
meson compile -C builddir

# Run tests
meson test -C builddir -v
```

---

## Try It Yourself

### Standalone Examples (No OpenBMC Required)

Build and run the example tests from this tutorial:

```bash
# Clone the tutorial repository
git clone https://github.com/MichaelTien8901/openbmc-guide-tutorial.git
cd openbmc-guide-tutorial/docs/examples/testing

# Option 1: CMake (auto-downloads GTest)
mkdir build && cd build
cmake ..
make
ctest --output-on-failure

# Option 2: Make (requires GTest installed)
# sudo apt install libgtest-dev libgmock-dev
make
make test
```

Expected output:
```
[==========] Running 7 tests from 2 test suites.
[----------] 2 tests from SensorManagerBasicTest
[ RUN      ] SensorManagerBasicTest.InitiallyEmpty
[       OK ] SensorManagerBasicTest.InitiallyEmpty (0 ms)
...
[  PASSED  ] 7 tests.
```

### Real OpenBMC Test Suites

After learning the basics, try running tests from actual OpenBMC repositories:

#### phosphor-logging (Event Logging)

```bash
git clone https://github.com/openbmc/phosphor-logging
cd phosphor-logging

# Install dependencies (on Ubuntu)
sudo apt install meson ninja-build pkg-config \
    libsdbusplus-dev libphosphor-dbus-interfaces-dev \
    libcereal-dev nlohmann-json3-dev

# Build with tests
meson setup builddir -Dtests=enabled
meson compile -C builddir

# Run tests
meson test -C builddir -v
```

#### dbus-sensors (Sensor Daemons)

```bash
git clone https://github.com/openbmc/dbus-sensors
cd dbus-sensors
meson setup builddir -Dtests=enabled
meson compile -C builddir
meson test -C builddir -v
```

#### bmcweb (Redfish Server)

```bash
git clone https://github.com/openbmc/bmcweb
cd bmcweb
meson setup builddir -Dtests=enabled
meson compile -C builddir
meson test -C builddir -v
```

{: .tip }
If dependency installation is complex, use the OpenBMC SDK which includes all required libraries pre-installed.

---

## Best Practices

### Test Organization

- One test file per source file (`service.cpp` → `service_test.cpp`)
- Group related tests in test fixtures
- Use descriptive test names: `TEST(Component, WhatItDoes)`

### Test Independence

- Each test should be independent
- Don't rely on test execution order
- Clean up resources in TearDown

### Mock Appropriately

- Mock external dependencies (D-Bus, filesystem, network)
- Don't mock the code under test
- Verify mock expectations

### Coverage Goals

- Aim for >80% line coverage
- Test error paths, not just happy paths
- Cover boundary conditions

---

## Next Steps

- [Robot Framework Guide]({% link docs/05-advanced/11-robot-framework-guide.md %}) - Integration testing
- [Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %}) - devtool for rapid iteration

---

## References

- [Google Test Documentation](https://google.github.io/googletest/)
- [Google Mock Documentation](https://google.github.io/googletest/gmock_cook_book.html)
- [phosphor-logging Tests](https://github.com/openbmc/phosphor-logging/tree/master/test)
- [sdbusplus Test Utilities](https://github.com/openbmc/sdbusplus/tree/master/test)

---

{: .note }
**Tested on**: OpenBMC master branch with Meson build system
