cmake_minimum_required(VERSION 3.20)
project(StarFoxAssaultRecomp LANGUAGES C CXX)

add_subdirectory(runtime)

# Keep analysis metadata in the source tree. Clean builds must not depend on the
# ignored analysis directory left over from the initial reverse-engineering session.
set(ASSAULT_REL_MODULES
  md0 md1 md2 m0 m009 m1 m10 m2 m3 m4 m5 m6 m7 m8 m9
  mb01a mb01b mb02 mb05 mb10a mbg0 mbg1 mbg2)
set(ASSAULT_REL_SYMBOLS "${CMAKE_CURRENT_BINARY_DIR}/assault-rel-symbols")
file(MAKE_DIRECTORY "${ASSAULT_REL_SYMBOLS}")
set(ASSAULT_REL_FILES)
foreach(module IN LISTS ASSAULT_REL_MODULES)
  configure_file("${CMAKE_SOURCE_DIR}/decomp/config/GF7E01/${module}/symbols.txt"
                 "${ASSAULT_REL_SYMBOLS}/${module}.txt" COPYONLY)
  configure_file("${CMAKE_SOURCE_DIR}/decomp/config/GF7E01/${module}/splits.txt"
                 "${ASSAULT_REL_SYMBOLS}/${module}.splits.txt" COPYONLY)
  list(APPEND ASSAULT_REL_FILES "${module}.rel")
endforeach()

gcn_add_game(
  NAME assault
  TITLE "Star Fox Assault"
  LABEL "Star Fox Assault Recomp"
  DISC_ID GF7E01
  DOL_SHA1 ae7201e7acd5a29acc807d7668a856392fd37ff9
  SYMBOLS "${CMAKE_SOURCE_DIR}/decomp/config/GF7E01/symbols.txt"
  TABLES "${CMAKE_SOURCE_DIR}/recomp"
  FPS 60
  IMAGE_DIR "${CMAKE_SOURCE_DIR}/decomp/orig/GF7E01"
  RELS ${ASSAULT_REL_FILES}
  REL_SYMBOLS "${ASSAULT_REL_SYMBOLS}"
)

# MSBuild's /m parallelizes projects; /MP also parallelizes the generated C files.
# MSVC builds only; the launcher's Ninja build picks its job count from CPU and memory.
if(MSVC)
  target_compile_options(game_recomp PRIVATE /MP8)
endif()
