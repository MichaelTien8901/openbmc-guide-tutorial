project(
    'myoem-ipmi',
    'cpp',
    version: '1.0.0',
    default_options: [
        'cpp_std=c++20',
        'warning_level=3',
        'werror=true',
    ],
    meson_version: '>=0.58.0',
)

# Dependencies
sdbusplus_dep = dependency('sdbusplus')
phosphor_logging_dep = dependency('phosphor-logging')
ipmid_dep = dependency('libipmid')

# Build the shared library
myoemhandler_lib = shared_library(
    'myoemhandler',
    'oem_handler.cpp',
    dependencies: [
        sdbusplus_dep,
        phosphor_logging_dep,
        ipmid_dep,
    ],
    install: true,
    install_dir: get_option('libdir') / 'ipmid-providers',
)
