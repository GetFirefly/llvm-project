# Building libclang-cpp.so fails if LLVM_ENABLE_PIC=Off
if (NOT LLVM_ENABLE_PIC)
  return()
endif()

if (NOT LLVM_BUILD_CPP_DYLIB)
  return()
endif()

get_property(llvm_libs GLOBAL PROPERTY LLVM_LIBS)
list(REMOVE_DUPLICATES llvm_libs)
# Exclude libLLVMTableGen for the following reasons:
#  - it is only used by internal *-tblgen utilities;
#  - it pollutes the global options space.
list(REMOVE_ITEM llvm_libs "LLVMTableGen")

# Remove executables
foreach(lib IN LISTS llvm_libs)
    get_property(exclude_lib TARGET ${lib} PROPERTY EXCLUDE_FROM_ALL)
    get_property(lib_type TARGET ${lib} PROPERTY TYPE)
    if(exclude_lib)
      list(REMOVE_ITEM llvm_libs "${lib}")
    elseif(lib_type STREQUAL "EXECUTABLE")
      list(REMOVE_ITEM llvm_libs "${lib}")
    elseif(lib_type STREQUAL "SHARED_LIBRARY")
      list(REMOVE_ITEM llvm_libs "${lib}")
    endif()
endforeach()

foreach (lib ${llvm_libs})
  if(XCODE)
    # Xcode doesn't support object libraries, so we have to trick it into
    # linking the static libraries instead.
    list(APPEND _DEPS "-force_load" ${lib})
  else()
    list(APPEND _OBJECTS $<TARGET_OBJECTS:${lib}>)
  endif()
  #list(APPEND _DEPS $<TARGET_PROPERTY:${lib},INTERFACE_LINK_LIBRARIES>)
  list(APPEND _DEPS $<TARGET_PROPERTY:${lib},LINK_LIBRARIES>)
endforeach ()

if (LLVM_LINK_LLVM_DYLIB)
  set(INSTALL_WITH_TOOLCHAIN INSTALL_WITH_TOOLCHAIN)
endif()

add_llvm_library(LLVMcpp
                 SHARED
                 DISABLE_LLVM_LINK_LLVM_DYLIB
                 SONAME
                 ${INSTALL_WITH_TOOLCHAIN}

                 llvm-cpp-shlib.cpp
                 ${_OBJECTS}

                 LINK_LIBS
                 ${_DEPS})
