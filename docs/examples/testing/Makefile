# Makefile - Simple standalone build for GTest examples
#
# For systems with GTest already installed (apt install libgtest-dev)
#
# Usage:
#   make
#   ./sensor_tests
#
# Or use CMake for automatic GTest download:
#   mkdir build && cd build && cmake .. && make

CXX = g++
CXXFLAGS = -std=c++20 -Wall -Wextra -g

# Try to find GTest
GTEST_CFLAGS = $(shell pkg-config --cflags gtest gmock 2>/dev/null)
GTEST_LIBS = $(shell pkg-config --libs gtest gmock gtest_main 2>/dev/null)

# Fallback if pkg-config doesn't work
ifeq ($(GTEST_LIBS),)
    GTEST_LIBS = -lgtest -lgtest_main -lgmock -pthread
endif

TARGET = sensor_tests
SRCS = sensor_test.cpp

.PHONY: all clean test help

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CXX) $(CXXFLAGS) $(GTEST_CFLAGS) -o $@ $^ $(GTEST_LIBS)

test: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET)

help:
	@echo "OpenBMC GTest Examples"
	@echo ""
	@echo "Prerequisites:"
	@echo "  Ubuntu/Debian: sudo apt install libgtest-dev libgmock-dev"
	@echo "  Fedora:        sudo dnf install gtest-devel gmock-devel"
	@echo ""
	@echo "Usage:"
	@echo "  make      - Build the test executable"
	@echo "  make test - Build and run tests"
	@echo "  make clean - Remove built files"
	@echo ""
	@echo "Alternative (auto-downloads GTest):"
	@echo "  mkdir build && cd build && cmake .. && make && ctest"
