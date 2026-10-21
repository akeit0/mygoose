cmake_minimum_required(VERSION 3.20)
project(mygoose_package LANGUAGES C)

# The Goose package lives here; native sources stay shared with repository builds.
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/.." "${CMAKE_CURRENT_BINARY_DIR}/mygoose-native")
