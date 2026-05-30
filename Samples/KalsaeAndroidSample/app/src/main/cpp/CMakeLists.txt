cmake_minimum_required(VERSION 3.22.1)
project(kalsae_callbacks)

add_library(kalsae_callbacks SHARED
    kalsae_callbacks.cpp
)

find_library(log-lib log)

target_link_libraries(kalsae_callbacks
    ${log-lib}
)
