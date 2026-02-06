project('openbmc-dbus-examples', 'cpp',
  version: '1.0.0',
  default_options: [
    'cpp_std=c++23',
    'warning_level=3',
  ],
)

sdbusplus_dep = dependency('sdbusplus')
boost_dep = dependency('boost')

executable('dbus_client',
  'client/dbus_client.cpp',
  dependencies: [sdbusplus_dep],
)

executable('dbus_server',
  'server/dbus_server.cpp',
  dependencies: [sdbusplus_dep, boost_dep],
)
