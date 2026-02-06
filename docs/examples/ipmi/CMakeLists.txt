cmake_minimum_required(VERSION 3.5)
project(myoem-ipmi CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required packages
find_package(PkgConfig REQUIRED)
pkg_check_modules(IPMI REQUIRED libipmid)
pkg_check_modules(SDBUSPLUS REQUIRED sdbusplus)
pkg_check_modules(PHOSPHOR_LOGGING REQUIRED phosphor-logging)

# Create the shared library
add_library(myoemhandler SHARED
    oem_handler.cpp
)

# Include directories
target_include_directories(myoemhandler PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${IPMI_INCLUDE_DIRS}
    ${SDBUSPLUS_INCLUDE_DIRS}
    ${PHOSPHOR_LOGGING_INCLUDE_DIRS}
)

# Link libraries
target_link_libraries(myoemhandler
    ${IPMI_LIBRARIES}
    ${SDBUSPLUS_LIBRARIES}
    ${PHOSPHOR_LOGGING_LIBRARIES}
)

# Compiler flags
target_compile_options(myoemhandler PRIVATE
    -Wall
    -Wextra
    -Werror
)

# Install to ipmid-providers directory
install(TARGETS myoemhandler
    LIBRARY DESTINATION lib/ipmid-providers
)
