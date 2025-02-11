#!/usr/bin/env bash

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
DIST_DIR="$(cd "$SCRIPT_DIR"/../ && pwd -P)"
ROOT_DIR="$(cd "$DIST_DIR"/../../ && pwd -P)"

system=`uname -s`
if [ "$system" = "FreeBSD" ]; then
    MAKE=gmake
else
    MAKE=make
fi

release=""
flavor="Release"
enable_bindings="OFF"
enable_docs="OFF"
enable_examples="OFF"
enable_tests="OFF"
enable_benchmarks="OFF"
enable_assertions="OFF"
enable_build_dylib="OFF"
enable_link_dylib="OFF"
enable_static_libcpp=""
enable_build_shared="OFF"
skip_build=""
clean_obj=""
skip_install=""
skip_dist=""
enable_ccache="OFF"
enable_optimized_tablegen="ON"
verbose=""
num_jobs=""
build_staged=""
stage=""
triple="$(gcc -dumpmachine)"
targets="X86;AArch64;ARM;WebAssembly"
extra_configure_flags=""
src_dir=""
build_dir=""
install_dir=""
dist_dir=""
install_toolchain_only="OFF"
c_compiler="$CC"
cxx_compiler="$CXX"

llvm_dylib_components="all"

enable_runtimes=""
enable_projects="clang;llvm;mlir;lld;lldb"

# Disable lldb on macOS
if [[ "$enable_projects" =~ "lldb" ]] && [ "$(uname -s)" = "Darwin" ]; then
    enable_projects="clang;llvm;mlir;lld"
fi

num_jobs=""
if [ -z "$num_jobs" ]; then
    num_jobs="$(sysctl -n hw.activecpu 2>/dev/null || true)"
fi
if [ -z "$num_jobs" ]; then
    num_jobs="$(sysctl -n hw.ncpu 2>/dev/null || true)"
fi
if [ -z "$num_jobs" ]; then
    num_jobs="$(grep -c processor /proc/cpuinfo 2>/dev/null || true)"
fi
if [ -z "$num_jobs" ]; then
    num_jobs=3
fi

function usage() {
    echo "usage: $(basename "$0") -release X.Y.Z [OPTIONS]"
    echo ""
    echo " -release X.Y.Z          The release version to use"
    echo " -flavor                 The type of build (Release, RelWithDebInfo, Debug) [default: Release]"
    echo " -targets TARGET         A semicolon-separated list of targets to support [default: $targets]"
    echo " -triple TRIPLE          The target triple we're targeting [default: $triple]"
    echo " -stage STAGE            The stage to build"
    echo " -src-dir DIR            Directory containing project sources (e.g. the llvm-project directory)"
    echo " -build-dir DIR          Directory to build in [default: $(pwd)]"
    echo " -install-dir DIR        Directory to install release to"
    echo " -dist-dir DIR           Directory to place distribution packages in"
    echo " -debug                  Build a debug release"
    echo " -with-assertions        Enable debug assertions"
    echo " -configure-flags FLAGS  Extra flags to pass to the configure step"
    echo " -with-dylib             Build LLVM dylib"
    echo " -build-shared           Build shared libraries for all LLVM components"
    echo " -link-dylib             Link LLVM tools against LLVM dylib"
    echo " -with-static-libc++     Statically link the C++ standard library"
    echo " -skip-build             Skip building and go straight to install"
    echo " -skip-install           Do not perform install step at end of build"
    echo " -skip-dist              Do build a distribution package"
    echo " -clean-obj              Remove obj directory after build is complete"
    echo " -with-docs              Build documentation"
    echo " -no-docs                Do not build documentation"
    echo " -with-examples          Build examples"
    echo " -no-examples            Do not build examples"
    echo " -with-benchmarks        Build benchmarks"
    echo " -no-benchmarks          Do not build benchmarks"
    echo " -with-tests             Build tests"
    echo " -no-tests               Do not build tests"
    echo " -verbose                Produce more verbose output"
    echo " -j NUM                  The number of compile jobs to run. [default: $num_jobs]"
}

while [ $# -gt 0 ]; do
    lhs="${1%=*}"
    rhs="${1#*=}"
    # Shift once for the flag name if true
    shift_key="false"
    # Shift once for the flag value if true
    shift_value="false"
    # Shift for the flag value if true, and shift_value=true
    has_value="false"
    if [ "$lhs" = "$1" ]; then
        # No '=' to split on, so grab the next arg
        shift
        rhs="$1"
        # We already shifted for the name, but not for the value
        shift_value="true"
    else
        # We only need one shift for both key and value
        shift_key="true"
    fi
    case $lhs in
        -release | --release )
            release="$rhs"
            has_value="true"
            ;;
        -flavor | --flavor)
            flavor="$rhs"
            has_value="true"
            ;;
        -targets | --targets)
            targets="$rhs"
            has_value="true"
            ;;
        -triple | --triple)
            triple="$rhs"
            has_value="true"
            ;;
        -stage | --stage)
            stage="$rhs"
            build_staged="true"
            has_value="true"
            ;;
        -src-dir | --src-dir )
            src_dir="$rhs"
            has_value="true"
            ;;
        -build-dir | --build-dir )
            build_dir="$rhs"
            has_value="true"
            ;;
        -install-dir | --install-dir )
            install_dir="$rhs"
            has_value="true"
            ;;
        -dist-dir | --dist-dir )
            dist_dir="$rhs"
            has_value="true"
            ;;
        -debug | --debug)
            flavor="Debug"
            enable_assertions="ON"
            ;;
        -with-assertions | --with-assertions)
            enable_assertions="ON"
            ;;
        -configure-flags | --configure-flags )
            extra_configure_flags="$rhs"
            has_value="true"
            ;;
        -build-shared | --build-shared)
            enable_build_shared="ON"
            ;;
        -with-dylib | --with-dylib)
            enable_build_dylib="ON"
            ;;
        -link-dylib | --link-dylib)
            enable_build_dylib="ON"
            enable_link_dylib="ON"
            ;;
        -with-static-libc++ | --with-static-libc++)
            enable_static_libcpp="ON"
            ;;
        -skip-build | --skip-build)
            skip_build="true"
            ;;
        -skip-install | --skip-install)
            skip_install="true"
            ;;
        -skip-dist | --skip-dist)
            skip_dist="true"
            ;;
        -clean-obj | --clean-obj)
            clean_obj="true"
            ;;
        -with-docs | --with-docs)
            enable_docs="ON"
            ;;
        -no-docs | --no-docs)
            enable_docs="OFF"
            ;;
        -with-examples | --with-examples)
            enable_examples="ON"
            ;;
        -no-examples | --no-examples)
            enable_examples="OFF"
            ;;
        -with-benchmarks | --with-benchmarks)
            enable_benchmarks="ON"
            ;;
        -no-benchmarks | --no-benchmarks)
            enable_benchmarks="OFF"
            ;;
        -with-tests | --with-tests)
            enable_tests="ON"
            ;;
        -no-tests | --no-tests)
            enable_tests="OFF"
            ;;
        -verbose | --verbose)
            verbose="ON"
            ;;
        -j*)
            # shellcheck disable=SC2001
            num_jobs="$(echo "$lhs" | sed -e 's,-j\([0-9]*\),\1,g')"
            if [ -z "$num_jobs" ]; then
                num_jobs="$rhs"
                has_value="true"
            fi
            ;;
        -help | --help | -h)
            usage
            exit 2
            ;;
        *)
            echo "unknown option: $1"
            usage
            exit 2
            ;;
    esac

    if [ "$shift_key" = "true" ]; then
        shift
    fi
    if [ "$has_value" = "true" ] && [ "$shift_value" = "true" ]; then
        shift
    fi
done

echo "Running script from $SCRIPT_DIR"
echo "Default distribution directory: $DIST_DIR"
echo "Default project root directory: $ROOT_DIR"
echo "SYSTEM: $system"
echo "MAKE: $MAKE"

if [ -z "$release" ]; then
    echo "error: no release specified"
    exit 2
fi
if [ -n "$flavor" ]; then
    case $flavor in
        Release | RelWithDebInfo)
            enable_static_libcpp="ON"
            ;;
        Debug)
            enable_assertions="ON"
            ;;
        *)
            echo "error: invalid flavor [Release, RelWithDebInfo, Debug]"
            exit 2
            ;;
    esac
fi
if [ -z "$src_dir" ]; then
    src_dir="${ROOT_DIR}"
    if [ -z "$build_dir" ]; then
        build_dir="${ROOT_DIR}/build/$triple"
    fi
fi
if [ -z "$build_dir" ]; then
    build_dir="$(pwd)"
fi
if [ ! -d "$src_dir" ]; then
    echo "error: source directory is not a directory ($src_dir)"
    exit 2
fi
if [ -z "$install_dir" ] && [ -z "$skip_install" ]; then
    echo "error: no install directory specified"
    exit 2
elif [ -z "$install_dir" ]; then
    install_dir="${build_dir}/usr/local"
fi
if [ -z "$dist_dir" ] && [ -z "$skip_dist" ]; then
    echo "error: no distribution directory specified"
    exit 2
fi
if [ -n "$verbose" ]; then
    extra_configure_flags="-DCMAKE_INSTALL_MESSAGE=Lazy $extra_configure_flags"
fi
if [ -z "$num_jobs" ]; then
    num_jobs="$(sysctl -n hw.activecpu 2>/dev/null || true)"
fi
if [ -z "$num_jobs" ]; then
    num_jobs="$(sysctl -n hw.ncpu 2>/dev/null || true)"
fi
if [ -z "$num_jobs" ]; then
    num_jobs="$(grep -c processor /proc/cpuinfo 2>/dev/null || true)"
fi
if [ -z "$num_jobs" ]; then
    num_jobs=3
fi

enable_ccache=""
if type -p ccache >/dev/null; then
    echo "CCACHE: ON"
    enable_ccache="ON"
else
    echo "CCACHE: OFF"
    enable_ccache="OFF"
fi

log_dir="$build_dir/logs"
mkdir -p "$build_dir"
mkdir -p "$log_dir"
cd "$build_dir"

echo "Changing directory to $build_dir"

package=clang+llvm-$release-$triple

echo -n > "$log_dir/deferred_errors.log"

function deferred_error() {
    local stage="$1"
    local current_flavor="$2"
    local msg="$3"
    echo "[${current_flavor} stage-${stage}] ${msg}" | tee -a "$log_dir/deferred_errors.log"
}

missing_programs=""
function check_program_exists() {
    local program="$1"
    if ! type -P "${program}" >/dev/null 2>&1; then
        echo "CHECK '$program': NO"
        missing_programs="true"
    else
        echo "CHECK '$program': YES"
    fi
}

if [ "$system" != "Darwin" -a "$system" != "SunOS" ]; then
    check_program_exists 'chrpath'
fi

if [ "$system" != "Darwin" ]; then
    check_program_exists 'file'
    check_program_exists 'objdump'
fi

check_program_exists 'ninja'

if [ -n "$missing_programs" ]; then
    echo "Required utility programs are missing! Cannot proceed."
    exit 1
fi

function configure_core() {
    local current_stage="$1"
    local current_flavor="$2"
    local obj_dir="$3"

    local stage_targets="$targets"
    local stage_build_dylib="$enable_build_dylib"
    local stage_build_mlir_dylib="$enable_build_dylib"
    local stage_link_dylib="$enable_link_dylib"
    local stage_build_shared="$enable_build_shared"
    local stage_install_toolchain_only="$install_toolchain_only"
    local stage_projects="$enable_projects"
    local stage_runtimes="$enable_runtimes"

    if [ "1" = "$current_stage" ]; then
        stage_targets="Native"
        stage_link_dylib="OFF"
        stage_build_dylib="OFF"
        stage_build_shared="OFF"
        stage_install_toolchain_only="ON"
        stage_projects="clang;clang-tools-extra;lld"
        stage_runtimes="compiler-rt;libcxx;libcxxabi"
        extra_configure_flags="-DBOOTSTRAP_CMAKE_BUILD_TYPE=Release -DCLANG_ENABLE_BOOTSTRAP=ON -DCLANG_BOOTSTRAP_TARGETS=\"install-clang;install-clang-resource-headers\""
    else
        extra_configure_flags="-DLLVM_BUILD_UTILS=ON -DLLVM_INSTALL_UTILS=ON $extra_configure_flags"
        if [[ ! "$triple" =~ apple ]]; then
            extra_configure_flags="-DLLVM_ENABLE_LLD=ON $extra_configure_flags"
        fi
        if [ -n "$enable_static_libcpp" ]; then
            if [[ "$triple" =~ "apple" ]]; then
                extra_configure_flags="-DCMAKE_EXE_LINKER_FLAGS=\"-static-libstdc++\" $extra_configure_flags"
            elif [[ ! "$triple" =~ "msvc" ]]; then
                extra_configure_flags="-DCMAKE_EXE_LINKER_FLAGS=\"-Wl,-Bsymbolic -static-libstdc++\" $extra_configure_flags"
            fi
        fi
    fi
    if [[ "$stage_projects" =~ "lldb" ]]; then
        extra_configure_flags="-DLLDB_CODESIGN_IDENTITY=\"\" $extra_configure_flags"
        extra_configure_flags="-DLLDB_NO_DEBUGSERVER=ON $extra_configure_flags"
        extra_configure_flags="-DLLVM_ENABLE_LIBXML2=ON $extra_configure_flags"
    else
        extra_configure_flags="-DLLVM_ENABLE_LIBXML2=ON $extra_configure_flags"
    fi

    echo "# Using C Compiler:   $c_compiler"
    echo "# Using C++ Compiler: $cxx_compiler"

    cd "$obj_dir"
    echo "# Configuring LLVM $release $flavor"

    echo "#" env CC="$c_compiler" CXX="$cxx_compiler" \
        cmake \
            -GNinja \
            -DCMAKE_BUILD_TYPE="$flavor" \
            -DLLVM_TARGETS_TO_BUILD="$stage_targets" \
            -DLLVM_ENABLE_PROJECTS="$stage_projects" \
            -DLLVM_ENABLE_RUNTIMES="$stage_runtimes" \
            -DLLVM_CCACHE_BUILD="${enable_ccache:OFF}" \
            -DLLVM_OPTIMIZED_TABLEGEN="$enable_optimized_tablegen" \
            -DBUILD_SHARED_LIBS="$stage_build_shared" \
            -DLLVM_DYLIB_COMPONENTS="$llvm_dylib_components" \
            -DLLVM_BUILD_LLVM_DYLIB="$stage_build_dylib" \
            -DMLIR_BUILD_MLIR_C_DYLIB="$stage_build_mlir_dylib" \
            -DLLVM_LINK_LLVM_DYLIB="$stage_link_dylib" \
            -DLLVM_INSTALL_TOOLCHAIN_ONLY="$stage_install_toolchain_only" \
            -DLLVM_ENABLE_ASSERTIONS="${enable_assertions:OFF}" \
            -DLLVM_PARALLEL_COMPILE_JOBS="$num_jobs" \
            -DLLVM_VERSION_SUFFIX="-firefly-$release" \
            -DLLVM_INCLUDE_DOCS="$enable_docs" \
            -DLLVM_BUILD_DOCS="$enable_docs" \
            -DLLVM_ENABLE_DOXYGEN="$enable_docs" \
            -DLLVM_ENABLE_SPHINX="$enable_docs" \
            -DLLVM_ENABLE_BINDINGS="$enable_bindings" \
            -DLLVM_INCLUDE_EXAMPLES="$enable_examples" \
            -DLLVM_INCLUDE_TESTS="$enable_tests" \
            -DLLVM_BUILD_TESTS="$enable_tests" \
            -DLLVM_INCLUDE_GO_TESTS="$enable_tests" \
            -DLLVM_INCLUDE_BENCHMARKS="$enable_benchmarks" \
            -DLLVM_ENABLE_ZLIB=OFF \
            -DLLVM_USE_STATIC_ZSTD=TRUE \
            -DLLVM_ENABLE_TERMINFO=OFF \
            -DLLVM_ENABLE_LIBEDIT=OFF \
            -DLLVM_ENABLE_Z3_SOLVER=OFF \
            "${extra_configure_flags[@]}" \
            "$src_dir/llvm" \
            2>&1 | tee "$log_dir/llvm.configure-stage${stage}-${flavor}.log"
    env CC="$c_compiler" CXX="$cxx_compiler" \
        cmake \
            -GNinja \
            -DCMAKE_BUILD_TYPE=$flavor \
            -DLLVM_TARGETS_TO_BUILD="$stage_targets" \
            -DLLVM_ENABLE_PROJECTS="$stage_projects" \
            -DLLVM_ENABLE_RUNTIMES="$stage_runtimes" \
            -DLLVM_CCACHE_BUILD="${enable_ccache:OFF}" \
            -DLLVM_OPTIMIZED_TABLEGEN="$enable_optimized_tablegen" \
            -DBUILD_SHARED_LIBS="$stage_build_shared" \
            -DLLVM_DYLIB_COMPONENTS="$llvm_dylib_components" \
            -DLLVM_BUILD_LLVM_DYLIB="$stage_build_dylib" \
            -DMLIR_BUILD_MLIR_C_DYLIB="$stage_build_mlir_dylib" \
            -DLLVM_LINK_LLVM_DYLIB="$stage_link_dylib" \
            -DLLVM_INSTALL_TOOLCHAIN_ONLY="$stage_install_toolchain_only" \
            -DLLVM_ENABLE_ASSERTIONS="${enable_assertions:OFF}" \
            -DLLVM_PARALLEL_COMPILE_JOBS="$num_jobs" \
            -DLLVM_VERSION_SUFFIX="-firefly-$release" \
            -DLLVM_INCLUDE_DOCS="$enable_docs" \
            -DLLVM_BUILD_DOCS="$enable_docs" \
            -DLLVM_ENABLE_DOXYGEN="$enable_docs" \
            -DLLVM_ENABLE_SPHINX="$enable_docs" \
            -DLLVM_ENABLE_BINDINGS="$enable_bindings" \
            -DLLVM_INCLUDE_EXAMPLES="$enable_examples" \
            -DLLVM_INCLUDE_TESTS="$enable_tests" \
            -DLLVM_BUILD_TESTS="$enable_tests" \
            -DLLVM_INCLUDE_GO_TESTS="$enable_tests" \
            -DLLVM_INCLUDE_BENCHMARKS="$enable_benchmarks" \
            -DLLVM_ENABLE_ZLIB=OFF \
            -DLLVM_USE_STATIC_ZSTD=TRUE \
            -DLLVM_ENABLE_TERMINFO=OFF \
            -DLLVM_ENABLE_LIBEDIT=OFF \
            -DLLVM_ENABLE_Z3_SOLVER=OFF \
            "${extra_configure_flags[@]}" \
            "$src_dir/llvm" \
            2>&1 | tee "$log_dir/llvm.configure-stage${stage}-${flavor}.log"

    cd "$build_dir"
}

function build_core() {
    local current_stage="$1"
    local current_flavor="$2"
    local obj_dir="$3"
    local dest_dir="$4"

    cd "$obj_dir"
    echo "# Compiling LLVM $release $current_flavor"
    echo "# ninja -j $num_jobs -v"
    ninja -j $num_jobs -v \
        2>&1 | tee "$log_dir/llvm.make-stage${current_stage}-${current_flavor}.log"

    echo "# Installing LLVM $release $current_flavor"

    echo "# ninja install-clang"
    DESTDIR="${dest_dir}" ninja install-clang install-clang-resource-headers \
        2>&1 | tee "$log_dir/llvm.install-stage${current_stage}-${current_flavor}.log"

    echo "# ninja install"
    DESTDIR="${dest_dir}" ninja install \
        2>&1 | tee "$log_dir/llvm.install-stage${current_stage}-${current_flavor}.log"

    echo "# Installing FileCheck"
    echo "# cp -f bin/FileCheck \"${dest_dir}/usr/local/bin/\""
    cp -f bin/FileCheck "${dest_dir}/usr/local/bin/"
    echo "# cp -f bin/not \"${dest_dir}/usr/local/bin/\""
    cp -f bin/not "${dest_dir}/usr/local/bin/"

    cd "$build_dir"
}

function clean_RPATH() {
    if [ "$system" = "Darwin" -o "$system" = "SunOS" ]; then
        return
    fi
    local install_path="$1"
    echo "Cleaning RPATH in $install_path/{bin,lib}"
    # shellcheck disable=SC2044
    for candidate in $(find "${install_path}"/{bin,lib} -type f); do
        echo "  ==> Checking: $candidate"
        if file "${candidate}" | grep ELF | grep -E 'executable|shared object' > /dev/null 2>&1; then
            echo "      Exec/Shared:    YES"
            if rpath="$(objdump -x "${candidate}" | grep 'RPATH')"; then
                echo "      Original RPATH: $rpath"
                rpath="$(echo "$rpath" | sed -e's/^ *RPATH *//')"
                echo "      Trimmed RPATH:  $rpath"
                if [ -n "$rpath" ]; then
                    # shellcheck disable=SC2016
                    newrpath="$(echo "$rpath" | sed -e's/.*\(\$ORIGIN[^:]*\).*/\1/')"
                    echo "      New RPATH:      $rpath"
                    chrpath -r "${newrpath}" "${candidate}" >/dev/null 2>&1
                fi
            fi
        fi
    done
}

function install_release() {
    local cwd=""
    cwd="$(pwd)"
    cd "$build_dir/stage2/$flavor"
    rm -rf "$install_dir"
    mkdir -p "$install_dir"
    cp -R "stage2-$release.install"/usr/local/* "$install_dir"/
    cd "$cwd"
}

function package_release() {
    local cwd=""
    cwd="$(pwd)"
    mkdir -p "$dist_dir"
    cd "$build_dir/stage2/$flavor"
    mv "stage2-$release.install"/usr/local "$package"
    tar -czf "$dist_dir/$package.tar.gz" "$package"
    mv "$package" "stage2-$release.install"/usr/local/
    cd "$cwd"
}

echo ""
echo "*************************************"
echo "  Release: $release"
echo "  Build:   $flavor"
echo "  System Info:"
echo "    $(uname -a)"
echo "*************************************"
echo ""

# Stage 1 is always run as -flavor=Release
stage1_objdir="$build_dir/stage1/Release/stage1-$release.obj"
stage1_destdir="$build_dir/stage1/Release/stage1-$release.install"

if [ -z "$build_staged" ]; then
    echo "Not performing a staged build, skipping to stage 2 build"

    stage2_objdir="$build_dir/stage2/$flavor/stage2-$release.obj"
    stage2_destdir="$build_dir/stage2/$flavor/stage2-$release.install"
    rm -rf "$stage2_destdir"
    mkdir -p "$stage2_objdir"
    mkdir -p "$stage2_destdir"

    if [ -z "$skip_build" ]; then
        echo "# Building LLVM"
        configure_core 2 $flavor "$stage2_objdir"
        build_core 2 $flavor "$stage2_objdir" "$stage2_destdir"
        clean_RPATH "${stage2_destdir}/usr/local"
    else
        if [ ! -d "$stage2_destdir" ]; then
            echo "# Unable to skip build! Previous build doesn't exist"
            exit 2
        else
            echo "# Skipping build"
        fi
    fi

    if [ -z "$skip_install" ]; then
        echo "# Installing the release to ${install_dir}"
        install_release
    else
        echo "# Skipping installation"
    fi

    if [ -z "$skip_install" ] && [ -z "$skip_dist" ]; then
        echo "# Packaging the release as $package.tar.gz"
        package_release
    else
        echo "# Skipping distribution packaging"
    fi
else
    echo "Performing a staged build.."

    case $stage in
        1)
            if [ -n "$skip_build" ]; then
                echo "# Unable to skip stage 1 build! Did you mean stage 2?"
                exit 2
            fi

            echo "# Stage 1: Preparing Build Enviornment"
	    if [ "${clean_obj}" = "true" ]; then
	        rm -rf "$stage1_objdir"
            	rm -rf "$stage1_destdir"
            fi
            mkdir -p "$stage1_objdir"
            mkdir -p "$stage1_destdir"

            echo "# Stage 1: Building LLVM"
            configure_core 1 $flavor "$stage1_objdir"
            build_core 1 $flavor "$stage1_objdir" "$stage1_destdir"
            clean_RPATH "${stage1_destdir}/usr/local"

            if [ "${clean_obj}" = "true" ]; then
                rm -rf "${stage1_objdir}"
            fi
        ;;
        2)
            if [ -z "$skip_build" ]; then
                echo "# Stage 2: Preparing Build Enviornment"
                c_compiler="$stage1_destdir/usr/local/bin/clang"
                cxx_compiler="$stage1_destdir/usr/local/bin/clang++"
                if [ ! -f "$c_compiler" ]; then
                    echo "missing C compiler ($c_compiler), must run stage1 build first!"
                    exit 2
                elif [ ! -f "$cxx_compiler" ]; then
                    echo "missing CXX compiler ($cxx_compiler), must run stage1 build first!"
                    exit 2
                fi
            fi
            stage2_objdir="$build_dir/stage2/$flavor/stage2-$release.obj"
            stage2_destdir="$build_dir/stage2/$flavor/stage2-$release.install"
            if [ -z "$skip_build" ]; then
                if [ "${clean_obj}" = "true" ]; then
                    rm -rf "$stage2_objdir"
                    rm -rf "$stage2_destdir"
		fi
                mkdir -p "$stage2_objdir"
                mkdir -p "$stage2_destdir"
                if [ -z "${install_dir}" ]; then
                    echo "Missing install_dir!"
                    exit 2
                fi
                rm -rf "${install_dir:?}"/*

                echo "# Stage 2: Building LLVM"
                configure_core 2 $flavor "$stage2_objdir"
                build_core 2 $flavor "$stage2_objdir" "$stage2_destdir"
                clean_RPATH "${stage2_destdir}/usr/local"

                if [ "${clean_obj}" = "true" ]; then
                    rm -rf "${stage2_objdir}"
                fi
            else
                if [ ! -d "$stage2_destdir" ]; then
                    echo "# Unable to skip build! Previous stage 2 build doesn't exist"
                    exit 2
                else
                    echo "# Skipping build"
                fi
            fi

            if [ -z "$skip_install" ]; then
                echo "# Installing the release to ${install_dir}"
                install_release
            else
                echo "# Skipping installation"
            fi

            if [ -z "$skip_install" ] && [ -z "$skip_dist" ]; then
                echo "# Packaging the release as $package.tar.gz"
                package_release
            else
                echo "# Skipping distribution packaging"
            fi
            ;;
        *)
            echo "Invalid stage '$stage', must be a number 1-2"
            exit 2
            ;;
    esac
fi

set +e

echo "### Logs: $log_dir"
echo "### Errors:"
if [ -s "$log_dir/deferred_errors.log" ]; then
    cat "$log_dir/deferred_errors.log"
    exit 1
else
    echo "None"
fi

echo "Finished!"

exit 0
