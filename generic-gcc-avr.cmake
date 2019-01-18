##########################################################################
# "THE ANY BEVERAGE-WARE LICENSE" (Revision 42 - based on beer-ware
# license):
# <dev@layer128.net> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and
# you think this stuff is worth it, you can buy me a be(ve)er(age) in
# return. (I don't like beer much.)
#
# Matthias Kleemann
##########################################################################

##########################################################################
# The toolchain requires some variables set.
#
# AVR_MCU (default: atmega8)
#     the type of AVR the application is built for
# AVR_L_FUSE (NO DEFAULT)
#     the LOW fuse value for the MCU used
# AVR_H_FUSE (NO DEFAULT)
#     the HIGH fuse value for the MCU used
# AVR_UPLOADTOOL (default: avrdude)
#     the application used to upload to the MCU
#     NOTE: The toolchain is currently quite specific about
#           the commands used, so it needs tweaking.
# AVR_UPLOADTOOL_PORT (default: usb)
#     the port used for the upload tool, e.g. usb
# AVR_PROGRAMMER (default: avrispmkII)
#     the programmer hardware used, e.g. avrispmkII
##########################################################################
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_C_STANDARD 11)

##########################################################################
# options
##########################################################################
option(WITH_MCU "Add the mcu type to the target file name." ON)

##########################################################################
# find cross-compile ROOT_PATH
##########################################################################
foreach(dir
    $ENV{AVR_FIND_ROOT_PATH}
    "/opt/local/avr"
    "/usr/avr"
    "/usr/lib/avr"
)
  if (EXISTS ${dir})
    set(CMAKE_FIND_ROOT_PATH ${dir})
    break()
  endif()
endforeach(dir)
message(STATUS "Set CMAKE_FIND_ROOT_PATH to ${CMAKE_FIND_ROOT_PATH}")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

##########################################################################
# find executables
##########################################################################
find_program(AVR_CC NAMES avr-gcc gcc)
find_program(AVR_CXX NAMES avr-g++ g++)
find_program(AVR_OBJCOPY NAMES avr-objcopy objcopy)
find_program(AVR_SIZE_TOOL NAMES avr-size)
find_program(AVR_OBJDUMP NAMES avr-objdump objdump)

##########################################################################
# toolchain starts with defining mandatory variables
##########################################################################
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR avr)
set(CMAKE_C_COMPILER ${AVR_CC})
set(CMAKE_CXX_COMPILER ${AVR_CXX})

##########################################################################
# some necessary tools and variables for AVR builds, which may not
# defined yet
# - AVR_UPLOADTOOL
# - AVR_UPLOADTOOL_PORT
# - AVR_PROGRAMMER
# - AVR_MCU
# - AVR_SIZE_ARGS
##########################################################################

find_program(AVR_UPLOADTOOL avrdude)
set(AVR_UPLOADTOOL_PORT "" CACHE STRING "Set default upload tool port: usb")
set(AVR_PROGRAMMER avrispmkII CACHE STRING "Set default programmer hardware model: avrispmkII")

set(AVR_MCU atmega8 CACHE STRING "Set default MCU: atmega8 (see 'avr-gcc --target-help' for valid values)")
set(MCU_SPEED 1000000UL CACHE STRING "MCU clock rate")

if(APPLE)
  set(AVR_SIZE_ARGS -B)
else(APPLE)
  set(AVR_SIZE_ARGS -C;--mcu=${AVR_MCU})
endif(APPLE)

##########################################################################
# check build types:
# - Debug
# - Release
# - RelWithDebInfo
#
# Release is chosen, because of some optimized functions in the
# AVR toolchain, e.g. _delay_ms().
##########################################################################
if(NOT ((CMAKE_BUILD_TYPE MATCHES Release) OR
        (CMAKE_BUILD_TYPE MATCHES RelWithDebInfo) OR
        (CMAKE_BUILD_TYPE MATCHES Debug) OR
        (CMAKE_BUILD_TYPE MATCHES MinSizeRel)))
   set(
      CMAKE_BUILD_TYPE Release
      CACHE STRING "Choose cmake build type: Debug Release RelWithDebInfo MinSizeRel"
      FORCE
   )
endif()

##########################################################################

##########################################################################
# target file name add-on
##########################################################################
if(WITH_MCU)
   set(MCU_TYPE_FOR_FILENAME "-${AVR_MCU}")
else(WITH_MCU)
   set(MCU_TYPE_FOR_FILENAME "")
endif(WITH_MCU)

add_compile_options(-mmcu=${AVR_MCU} -fpack-struct -fshort-enums)
add_definitions(-DF_CPU=${MCU_SPEED})

##########################################################################
# add_avr_executable
# - IN_VAR: EXECUTABLE_NAME
#
# Creates targets and dependencies for AVR toolchain, building an
# executable. Calls add_executable with ELF file as target name, so
# any link dependencies need to be using that target, e.g. for
# target_link_libraries(<EXECUTABLE_NAME>-${AVR_MCU}.elf ...).
##########################################################################
function(add_avr_executable EXECUTABLE_NAME)
   if(NOT ARGN)
      message(FATAL_ERROR "No source files given for ${EXECUTABLE_NAME}.")
   endif(NOT ARGN)

   if(AVR_UPLOADTOOL_PORT)
     set(AVR_UPLOADTOOL_PORT_ARGS "-P ${AVR_UPLOADTOOL_PORT}")
   endif()
   
   # set file names
   set(elf_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.elf)
   set(hex_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.hex)
   set(map_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.map)
   set(eeprom_image ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}-eeprom.hex)

   # elf file
   add_executable(${EXECUTABLE_NAME} ${ARGN})

   set_target_properties(${EXECUTABLE_NAME}
      PROPERTIES
      OUTPUT_NAME ${elf_file}
      LINK_FLAGS "-mmcu=${AVR_MCU} -Wl,--gc-sections -mrelax -Wl,-Map,${map_file}"
   )

   add_custom_command(
      OUTPUT ${hex_file}
      COMMAND
         ${AVR_OBJCOPY} -j .text -j .data -O ihex ${elf_file} ${hex_file}
      COMMAND
         ${AVR_SIZE_TOOL} ${AVR_SIZE_ARGS} ${elf_file}
      DEPENDS ${EXECUTABLE_NAME}
   )

   # eeprom
   add_custom_command(
      OUTPUT ${eeprom_image}
      COMMAND
         ${AVR_OBJCOPY} -j .eeprom --set-section-flags=.eeprom=alloc,load
            --change-section-lma .eeprom=0 --no-change-warnings
            -O ihex ${elf_file} ${eeprom_image}
      DEPENDS ${EXECUTABLE_NAME}
   )

   # clean
   get_directory_property(clean_files ADDITIONAL_MAKE_CLEAN_FILES)
   set_directory_properties(
      PROPERTIES
         ADDITIONAL_MAKE_CLEAN_FILES "${map_file}"
   )

   # upload - with avrdude
   add_custom_target(
      upload_${EXECUTABLE_NAME}
      ${AVR_UPLOADTOOL} -p ${AVR_MCU} -c ${AVR_PROGRAMMER} ${AVR_UPLOADTOOL_OPTIONS}
         -U flash:w:${hex_file}
         ${AVR_UPLOADTOOL_PORT_ARGS}
      DEPENDS ${hex_file}
      COMMENT "Uploading ${hex_file} to ${AVR_MCU} using ${AVR_PROGRAMMER}"
   )

   # upload eeprom only - with avrdude
   # see also bug http://savannah.nongnu.org/bugs/?40142
   add_custom_target(
      upload_eeprom
      ${AVR_UPLOADTOOL} -p ${AVR_MCU} -c ${AVR_PROGRAMMER} ${AVR_UPLOADTOOL_OPTIONS}
         -U eeprom:w:${eeprom_image}
         ${AVR_UPLOADTOOL_PORT_ARGS}
      DEPENDS ${eeprom_image}
      COMMENT "Uploading ${eeprom_image} to ${AVR_MCU} using ${AVR_PROGRAMMER}"
   )

   # get status
   add_custom_target(
      get_status
      ${AVR_UPLOADTOOL} -p ${AVR_MCU} -c ${AVR_PROGRAMMER} ${AVR_UPLOADTOOL_PORT_ARGS} -n -v
      COMMENT "Get status from ${AVR_MCU}"
   )

   # get fuses
   add_custom_target(
      get_fuses
      ${AVR_UPLOADTOOL} -p ${AVR_MCU} -c ${AVR_PROGRAMMER} ${AVR_UPLOADTOOL_PORT_ARGS} -n
         -U lfuse:r:-:b
         -U hfuse:r:-:b
      COMMENT "Get fuses from ${AVR_MCU}"
   )

   # set fuses
if(AVR_E_FUSE OR AVR_H_FUSE OR AVR_L_FUSE)
   add_custom_target(
      set_fuses
      ${AVR_UPLOADTOOL} -p ${AVR_MCU} -c ${AVR_PROGRAMMER} ${AVR_UPLOADTOOL_PORT_ARGS}
         -U lfuse:w:${AVR_L_FUSE}:m
         -U hfuse:w:${AVR_H_FUSE}:m
         COMMENT "Setup: High Fuse: ${AVR_H_FUSE} Low Fuse: ${AVR_L_FUSE}"
   )
else()
   set(fuses_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.fuses.hex)
   set(lfuse_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.lfuse.hex)
   set(hfuse_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.hfuse.hex)
   set(efuse_file ${EXECUTABLE_NAME}${MCU_TYPE_FOR_FILENAME}.efuse.hex)
   add_custom_target(
      set_fuses
      COMMAND avr-objcopy -j .fuse -O ihex ${elf_file} ${fuses_file} --change-section-lma .fuse=0
      COMMAND srec_cat ${fuses_file} -Intel -crop 0x00 0x01 -offset  0x00 -O ${lfuse_file} -Intel
      COMMAND srec_cat ${fuses_file} -Intel -crop 0x01 0x02 -offset -0x01 -O ${hfuse_file} -Intel
      COMMAND srec_cat ${fuses_file} -Intel -crop 0x02 0x03 -offset -0x02 -O ${efuse_file} -Intel
      COMMAND ${AVR_UPLOADTOOL} -p ${AVR_MCU} -c ${AVR_PROGRAMMER} ${AVR_UPLOADTOOL_PORT_ARGS}
         -U lfuse:w:${lfuse_file}:i
         -U hfuse:w:${hfuse_file}:i
         -U efuse:w:${efuse_file}:i
      DEPENDS ${EXECUTABLE_NAME}
      COMMENT "Setup FUSES"
   )
endif()

   # get oscillator calibration
   add_custom_target(
      get_calibration
         ${AVR_UPLOADTOOL} -p ${AVR_MCU} -c ${AVR_PROGRAMMER} ${AVR_UPLOADTOOL_PORT_ARGS}
         -U calibration:r:${AVR_MCU}_calib.tmp:r
         COMMENT "Write calibration status of internal oscillator to ${AVR_MCU}_calib.tmp."
   )

   # set oscillator calibration
   add_custom_target(
      set_calibration
      ${AVR_UPLOADTOOL} -p ${AVR_MCU} -c ${AVR_PROGRAMMER} ${AVR_UPLOADTOOL_PORT_ARGS}
         -U calibration:w:${AVR_MCU}_calib.hex
         COMMENT "Program calibration status of internal oscillator from ${AVR_MCU}_calib.hex."
   )

   # disassemble
   add_custom_target(
      disassemble_${EXECUTABLE_NAME}
      ${AVR_OBJDUMP} -h -S ${elf_file} > ${EXECUTABLE_NAME}.lst
      DEPENDS ${EXECUTABLE_NAME}
   )

endfunction(add_avr_executable)

##########################################################################
# add_avr_library
# - IN_VAR: LIBRARY_NAME
#
# Calls add_library with an optionally concatenated name
# <LIBRARY_NAME>${MCU_TYPE_FOR_FILENAME}.
# This needs to be used for linking against the library, e.g. calling
# target_link_libraries(...).
##########################################################################
function(add_avr_library LIBRARY_NAME)
   if(NOT ARGN)
      message(FATAL_ERROR "No source files given for ${LIBRARY_NAME}.")
   endif(NOT ARGN)

   add_library(${LIBRARY_NAME} STATIC ${ARGN})

   set_target_properties(${LIBRARY_NAME}
      PROPERTIES OUTPUT_NAME ${LIBRARY_NAME}${MCU_TYPE_FOR_FILENAME}
   )
endfunction(add_avr_library)

set(ARDUINO_DIR /opt/arduino/hardware/arduino/avr)
function(add_arduino_library LIBRARY_NAME)
   file(GLOB_RECURSE SOURCES ${ARDUINO_DIR}/libraries/${LIBRARY_NAME}/src/*.c*)

   add_library(${LIBRARY_NAME} STATIC ${SOURCES})
   set_target_properties(${LIBRARY_NAME}
      PROPERTIES OUTPUT_NAME ${LIBRARY_NAME}${MCU_TYPE_FOR_FILENAME}
   )
   target_include_directories(${LIBRARY_NAME}
       PRIVATE ${ARDUINO_DIR}/cores/arduino ${ARDUINO_DIR}/variants/standard
       PUBLIC ${ARDUINO_DIR}/libraries/${LIBRARY_NAME}/src
   )
endfunction(add_arduino_library)

include_directories(SYSTEM "${CMAKE_CURRENT_LIST_DIR}")
