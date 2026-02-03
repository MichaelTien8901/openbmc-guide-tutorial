/**
 * @file sensor_test.cpp
 * @brief Example GTest/GMock tests for OpenBMC sensor management
 *
 * This example demonstrates:
 * - Basic GTest test cases (TEST macro)
 * - Test fixtures for shared setup (TEST_F macro)
 * - GMock mock classes and expectations
 * - Common assertion patterns
 */

#include <gtest/gtest.h>
#include <gmock/gmock.h>
#include <memory>
#include <string>
#include <vector>

using ::testing::Return;
using ::testing::_;
using ::testing::AtLeast;

// ============================================================================
// Example: Sensor Interface and Mock
// ============================================================================

/**
 * @brief Interface for sensor reading
 *
 * In real OpenBMC code, this would wrap D-Bus calls to dbus-sensors
 */
class SensorInterface
{
  public:
    virtual ~SensorInterface() = default;
    virtual double getValue() = 0;
    virtual void setValue(double value) = 0;
    virtual bool isValid() const = 0;
    virtual std::string getName() const = 0;
};

/**
 * @brief Mock implementation for testing
 *
 * MOCK_METHOD generates mock methods that can be configured with EXPECT_CALL
 */
class MockSensor : public SensorInterface
{
  public:
    MOCK_METHOD(double, getValue, (), (override));
    MOCK_METHOD(void, setValue, (double value), (override));
    MOCK_METHOD(bool, isValid, (), (const, override));
    MOCK_METHOD(std::string, getName, (), (const, override));
};

// ============================================================================
// Example: Simple Class Under Test
// ============================================================================

/**
 * @brief Sensor manager that aggregates multiple sensors
 */
class SensorManager
{
  public:
    void addSensor(std::shared_ptr<SensorInterface> sensor)
    {
        sensors.push_back(sensor);
    }

    size_t getSensorCount() const
    {
        return sensors.size();
    }

    double getAverageValue()
    {
        if (sensors.empty())
        {
            return 0.0;
        }

        double sum = 0.0;
        int validCount = 0;

        for (auto& sensor : sensors)
        {
            if (sensor->isValid())
            {
                sum += sensor->getValue();
                validCount++;
            }
        }

        return validCount > 0 ? sum / validCount : 0.0;
    }

    std::vector<std::string> getInvalidSensors()
    {
        std::vector<std::string> invalid;
        for (auto& sensor : sensors)
        {
            if (!sensor->isValid())
            {
                invalid.push_back(sensor->getName());
            }
        }
        return invalid;
    }

  private:
    std::vector<std::shared_ptr<SensorInterface>> sensors;
};

// ============================================================================
// Basic Tests (TEST macro)
// ============================================================================

/**
 * @brief Basic test without fixture
 *
 * Use TEST(TestSuiteName, TestName) for simple tests
 */
TEST(SensorManagerBasicTest, InitiallyEmpty)
{
    SensorManager manager;
    EXPECT_EQ(manager.getSensorCount(), 0);
}

TEST(SensorManagerBasicTest, AverageOfEmptyIsZero)
{
    SensorManager manager;
    EXPECT_DOUBLE_EQ(manager.getAverageValue(), 0.0);
}

// ============================================================================
// Test Fixture (TEST_F macro)
// ============================================================================

/**
 * @brief Fixture for SensorManager tests
 *
 * SetUp() runs before each test, TearDown() after each test
 */
class SensorManagerTest : public ::testing::Test
{
  protected:
    void SetUp() override
    {
        manager = std::make_unique<SensorManager>();
        mockSensor1 = std::make_shared<MockSensor>();
        mockSensor2 = std::make_shared<MockSensor>();
    }

    void TearDown() override
    {
        // Cleanup if needed
    }

    std::unique_ptr<SensorManager> manager;
    std::shared_ptr<MockSensor> mockSensor1;
    std::shared_ptr<MockSensor> mockSensor2;
};

TEST_F(SensorManagerTest, AddsSensorSuccessfully)
{
    manager->addSensor(mockSensor1);
    EXPECT_EQ(manager->getSensorCount(), 1);

    manager->addSensor(mockSensor2);
    EXPECT_EQ(manager->getSensorCount(), 2);
}

TEST_F(SensorManagerTest, CalculatesAverageOfValidSensors)
{
    // Configure mock expectations
    EXPECT_CALL(*mockSensor1, isValid())
        .WillOnce(Return(true));
    EXPECT_CALL(*mockSensor1, getValue())
        .WillOnce(Return(50.0));

    EXPECT_CALL(*mockSensor2, isValid())
        .WillOnce(Return(true));
    EXPECT_CALL(*mockSensor2, getValue())
        .WillOnce(Return(70.0));

    manager->addSensor(mockSensor1);
    manager->addSensor(mockSensor2);

    // (50 + 70) / 2 = 60
    EXPECT_DOUBLE_EQ(manager->getAverageValue(), 60.0);
}

TEST_F(SensorManagerTest, SkipsInvalidSensorsInAverage)
{
    // Sensor 1 is valid
    EXPECT_CALL(*mockSensor1, isValid())
        .WillOnce(Return(true));
    EXPECT_CALL(*mockSensor1, getValue())
        .WillOnce(Return(50.0));

    // Sensor 2 is invalid - getValue should not be called
    EXPECT_CALL(*mockSensor2, isValid())
        .WillOnce(Return(false));
    EXPECT_CALL(*mockSensor2, getValue())
        .Times(0);

    manager->addSensor(mockSensor1);
    manager->addSensor(mockSensor2);

    // Only sensor1's value counts
    EXPECT_DOUBLE_EQ(manager->getAverageValue(), 50.0);
}

TEST_F(SensorManagerTest, ReportsInvalidSensors)
{
    EXPECT_CALL(*mockSensor1, isValid())
        .WillOnce(Return(true));

    EXPECT_CALL(*mockSensor2, isValid())
        .WillOnce(Return(false));
    EXPECT_CALL(*mockSensor2, getName())
        .WillOnce(Return("CPU_Temp"));

    manager->addSensor(mockSensor1);
    manager->addSensor(mockSensor2);

    auto invalid = manager->getInvalidSensors();
    ASSERT_EQ(invalid.size(), 1);
    EXPECT_EQ(invalid[0], "CPU_Temp");
}

// ============================================================================
// Edge Case Tests
// ============================================================================

TEST_F(SensorManagerTest, AllSensorsInvalidReturnsZeroAverage)
{
    EXPECT_CALL(*mockSensor1, isValid())
        .WillOnce(Return(false));
    EXPECT_CALL(*mockSensor2, isValid())
        .WillOnce(Return(false));

    manager->addSensor(mockSensor1);
    manager->addSensor(mockSensor2);

    EXPECT_DOUBLE_EQ(manager->getAverageValue(), 0.0);
}

// ============================================================================
// Main Entry Point
// ============================================================================

int main(int argc, char** argv)
{
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
