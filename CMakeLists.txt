cmake_minimum_required(VERSION 3.16)
project(uwpatch LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release)
endif()

# The patch's bytes are in src/uwpatch_perspective.h, generated from
# patch/perspective.asm by patch/build.sh (nasm) and checked in, so this
# needs nothing but a C compiler.
add_executable(uwpatch src/uwpatch.c)
target_include_directories(uwpatch PRIVATE src)
if(NOT MSVC)
  target_compile_options(uwpatch PRIVATE -Wall -Wextra)
endif()
if(MINGW)
  target_link_options(uwpatch PRIVATE -static-libgcc)
endif()
install(TARGETS uwpatch RUNTIME DESTINATION bin)
