cmake_minimum_required(VERSION 3.20)
project(gcn_disc_mods_test LANGUAGES C CXX)

if(WIN32 AND MINGW)
  enable_language(RC)
endif()

enable_testing()
add_executable(desktop_input_test desktop_input_test.cpp)
target_compile_features(desktop_input_test PRIVATE cxx_std_20)
add_test(NAME desktop_input_test COMMAND desktop_input_test)
add_executable(display_options_test display_options_test.cpp)
target_compile_features(display_options_test PRIVATE cxx_std_20)
add_test(NAME display_options_test COMMAND display_options_test)
add_executable(render_math_test render_math_test.cpp)
target_compile_features(render_math_test PRIVATE cxx_std_20)
add_test(NAME render_math_test COMMAND render_math_test)
add_executable(audio_gain_test audio_gain_test.cpp)
target_compile_features(audio_gain_test PRIVATE cxx_std_20)
add_test(NAME audio_gain_test COMMAND audio_gain_test)
add_executable(disc_mods_test disc_mods_test.cpp ../runtime/disc_mods.cpp)
target_compile_features(disc_mods_test PRIVATE cxx_std_20)
add_test(NAME disc_mods_test COMMAND disc_mods_test)

add_executable(texcoord_test texcoord_test.cpp)
target_compile_features(texcoord_test PRIVATE cxx_std_20)
add_test(NAME texcoord_test COMMAND texcoord_test)

add_executable(rel_rebinding_test rel_rebinding_test.cpp ../runtime/rels.cpp)
target_include_directories(rel_rebinding_test PRIVATE ../runtime)
target_compile_features(rel_rebinding_test PRIVATE cxx_std_20)
add_test(NAME rel_rebinding_test COMMAND rel_rebinding_test)

add_executable(thread_watch_filter_test thread_watch_filter_test.c)
target_compile_features(thread_watch_filter_test PRIVATE c_std_11)
add_test(NAME thread_watch_filter_test COMMAND thread_watch_filter_test)

add_executable(pointer_sanity_test pointer_sanity_test.cpp)
target_compile_features(pointer_sanity_test PRIVATE cxx_std_20)
add_test(NAME pointer_sanity_test COMMAND pointer_sanity_test)

add_executable(pad_curve_test pad_curve_test.cpp)
target_compile_features(pad_curve_test PRIVATE cxx_std_20)
add_test(NAME pad_curve_test COMMAND pad_curve_test)

add_executable(disc_image_test disc_image_test.cpp ../runtime/disc_image.cpp)
target_include_directories(disc_image_test PRIVATE ../runtime)
target_compile_features(disc_image_test PRIVATE cxx_std_20)
add_test(NAME disc_image_test COMMAND disc_image_test)

# The two capture helpers: non-finite transformed positions (a draw that vanishes) and the
# guest's own call chain (which game code was live when a watched word changed).
add_executable(vertex_sanity_test vertex_sanity_test.cpp)
target_compile_features(vertex_sanity_test PRIVATE cxx_std_20)
add_test(NAME vertex_sanity_test COMMAND vertex_sanity_test)

add_executable(guest_stack_test guest_stack_test.cpp)
target_compile_features(guest_stack_test PRIVATE cxx_std_20)
add_test(NAME guest_stack_test COMMAND guest_stack_test)

if(WIN32)
  add_executable(utf8_path_test utf8_path_test.cpp)
  target_compile_features(utf8_path_test PRIVATE cxx_std_20)
  if(MSVC)
    target_link_options(utf8_path_test PRIVATE "/MANIFESTINPUT:${CMAKE_CURRENT_SOURCE_DIR}/../runtime/assault.manifest")
  elseif(MINGW)
    target_link_options(utf8_path_test PRIVATE -static -static-libgcc -static-libstdc++)
    set(_utf8_test_rc "${CMAKE_CURRENT_BINARY_DIR}/utf8-path-test.rc")
    file(WRITE "${_utf8_test_rc}" "1 24 \"${CMAKE_CURRENT_SOURCE_DIR}/../runtime/assault.manifest\"\n")
    target_sources(utf8_path_test PRIVATE "${_utf8_test_rc}")
  endif()
  add_test(NAME utf8_path_test COMMAND utf8_path_test)
endif()

# Test binaries built with llvm-mingw use the shared libc++ runtime. Keep the
# runtime beside each executable so CTest and manual test runs both work when
# the compiler directory is not on the user's PATH.
if(MINGW AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  get_filename_component(GCN_TEST_COMPILER_BIN "${CMAKE_CXX_COMPILER}" DIRECTORY)
  get_property(_gcn_test_targets DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
  foreach(_runtime_dll libc++.dll libunwind.dll)
    set(_runtime_path "${GCN_TEST_COMPILER_BIN}/${_runtime_dll}")
    if(EXISTS "${_runtime_path}")
      foreach(_test_target IN LISTS _gcn_test_targets)
        get_target_property(_target_type "${_test_target}" TYPE)
        if(_target_type STREQUAL "EXECUTABLE")
          add_custom_command(TARGET ${_test_target} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
              "${_runtime_path}" "$<TARGET_FILE_DIR:${_test_target}>"
            VERBATIM)
        endif()
      endforeach()
    endif()
  endforeach()
endif()
