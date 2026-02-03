# Unit Testing Examples

Example GTest/GMock unit tests for OpenBMC development.

## Files

| File | Description |
|------|-------------|
| `sensor_test.cpp` | Complete example demonstrating TEST, TEST_F, and GMock |
| `meson.build` | Meson build configuration for tests |

## Building and Running

```bash
# Build with Meson
meson setup builddir
meson compile -C builddir

# Run tests
meson test -C builddir

# Run with verbose output
meson test -C builddir -v
```

## Key Patterns Demonstrated

### 1. Basic Tests (TEST macro)

```cpp
TEST(SuiteName, TestName)
{
    EXPECT_EQ(actual, expected);
}
```

### 2. Test Fixtures (TEST_F macro)

```cpp
class MyTest : public ::testing::Test
{
  protected:
    void SetUp() override { /* runs before each test */ }
    void TearDown() override { /* runs after each test */ }
};

TEST_F(MyTest, TestName)
{
    // Access fixture members directly
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
}
```

## Related Documentation

- [Unit Testing Guide](/docs/05-advanced/10-unit-testing-guide.html)
- [Robot Framework Guide](/docs/05-advanced/11-robot-framework-guide.html)
