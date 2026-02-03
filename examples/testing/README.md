# Unit Testing Examples

Standalone GTest/GMock examples for learning OpenBMC testing patterns.

**No OpenBMC SDK required** - these examples build and run on any Linux system.

## Quick Start

### Option 1: CMake (Recommended - Auto-downloads GTest)

```bash
cd examples/testing
mkdir build && cd build
cmake ..
make
ctest --output-on-failure
```

### Option 2: Make (Requires GTest installed)

```bash
# Install GTest first
sudo apt install libgtest-dev libgmock-dev  # Ubuntu/Debian
sudo dnf install gtest-devel gmock-devel     # Fedora

# Build and run
cd examples/testing
make
make test
```

## Expected Output

```
[==========] Running 7 tests from 2 test suites.
[----------] 2 tests from SensorManagerBasicTest
[ RUN      ] SensorManagerBasicTest.InitiallyEmpty
[       OK ] SensorManagerBasicTest.InitiallyEmpty (0 ms)
[ RUN      ] SensorManagerBasicTest.AverageOfEmptyIsZero
[       OK ] SensorManagerBasicTest.AverageOfEmptyIsZero (0 ms)
[----------] 5 tests from SensorManagerTest
[ RUN      ] SensorManagerTest.AddsSensorSuccessfully
[       OK ] SensorManagerTest.AddsSensorSuccessfully (0 ms)
[ RUN      ] SensorManagerTest.CalculatesAverageOfValidSensors
[       OK ] SensorManagerTest.CalculatesAverageOfValidSensors (0 ms)
[ RUN      ] SensorManagerTest.SkipsInvalidSensorsInAverage
[       OK ] SensorManagerTest.SkipsInvalidSensorsInAverage (0 ms)
[ RUN      ] SensorManagerTest.ReportsInvalidSensors
[       OK ] SensorManagerTest.ReportsInvalidSensors (0 ms)
[ RUN      ] SensorManagerTest.AllSensorsInvalidReturnsZeroAverage
[       OK ] SensorManagerTest.AllSensorsInvalidReturnsZeroAverage (0 ms)
[==========] 7 tests from 2 test suites ran. (1 ms total)
[  PASSED  ] 7 tests.
```

## Files

| File | Description |
|------|-------------|
| `sensor_test.cpp` | Complete example with TEST, TEST_F, and GMock patterns |
| `CMakeLists.txt` | CMake build (auto-downloads GTest) |
| `Makefile` | Simple make build (requires GTest installed) |
| `meson.build` | Meson build (for OpenBMC-style projects) |

## What You'll Learn

### 1. Basic Tests (TEST macro)

```cpp
TEST(SuiteName, TestName)
{
    MyClass obj;
    EXPECT_EQ(obj.getValue(), expected);
}
```

### 2. Test Fixtures (TEST_F macro)

```cpp
class MyTest : public ::testing::Test
{
  protected:
    void SetUp() override { /* runs before each test */ }
    void TearDown() override { /* runs after each test */ }

    std::unique_ptr<MyClass> obj;
};

TEST_F(MyTest, TestName)
{
    // Access fixture members
    obj->doSomething();
    EXPECT_TRUE(obj->isValid());
}
```

### 3. Mock Objects (GMock)

```cpp
class MockInterface : public Interface
{
  public:
    MOCK_METHOD(ReturnType, MethodName, (Args), (Modifiers));
};

TEST(Test, UsesMock)
{
    MockInterface mock;
    EXPECT_CALL(mock, MethodName(_))
        .WillOnce(Return(value));

    // Use mock in test
    MyClass obj(&mock);
    EXPECT_EQ(obj.compute(), expectedValue);
}
```

## Real OpenBMC Test Suites

After learning with these examples, try running tests from real OpenBMC repositories:

### phosphor-logging

```bash
git clone https://github.com/openbmc/phosphor-logging
cd phosphor-logging
meson setup builddir -Dtests=enabled
meson compile -C builddir
meson test -C builddir -v
```

### dbus-sensors

```bash
git clone https://github.com/openbmc/dbus-sensors
cd dbus-sensors
meson setup builddir -Dtests=enabled
meson compile -C builddir
meson test -C builddir -v
```

### phosphor-fan-presence

```bash
git clone https://github.com/openbmc/phosphor-fan-presence
cd phosphor-fan-presence
meson setup builddir -Dtests=enabled
meson compile -C builddir
meson test -C builddir -v
```

## Related Documentation

- [Unit Testing Guide](/docs/05-advanced/10-unit-testing-guide.html)
- [Robot Framework Guide](/docs/05-advanced/11-robot-framework-guide.html)
- [Google Test Documentation](https://google.github.io/googletest/)
