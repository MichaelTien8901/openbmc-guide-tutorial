project('openbmc-sensor-examples', 'cpp',
  version: '1.0.0',
  default_options: [
    'cpp_std=c++23',
    'warning_level=3',
  ],
)

sdbusplus_dep = dependency('sdbusplus')
boost_dep = dependency('boost')

executable('sensor_reader',
  'sensor_reader.cpp',
  dependencies: [sdbusplus_dep],
)

executable('virtual_sensor',
  'virtual-sensor/virtual_sensor.cpp',
  dependencies: [sdbusplus_dep, boost_dep],
)
