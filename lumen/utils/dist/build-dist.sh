#!/usr/bin/env bash

release=""
release_no_dot=""
flavor="Release"
stage=""
triple="$(gcc -dumpmachine)"
use_gzip="no"
do_debug="no"
do_asserts="no"
extra_configure_flags=""
src_dir=""
build_dir="$(pwd)"
install_dir=""
dist_dir=""

function usage() {
    echo "usage: `basename $0` -release X.Y.Z [OPTIONS]"
    echo ""
    echo " -release X.Y.Z          The release version to use"
    echo " -triple TRIPLE          The target triple we're targeting [default: $triple]"
    echo " -stage STAGE            The stage to build"
    echo " -j NUM                  The number of compile jobs to run. [default: 3]"
    echo " -src-dir DIR            Directory containing project sources (e.g. the llvm-project directory)"
    echo " -build-dir DIR          Directory to build in [default: pwd]"
    echo " -install-dir DIR        Directory to install release to"
    echo " -dist-dir DIR           Directory to place distribution packages in"
    echo " -debug                  Build a debug release"
    echo " -enable-asserts         Build with assertions enabled"
    echo " -configure-flags FLAGS  Extra flags to pass to the configure step"
}

while [ $# -gt 0 ]; do
    case $1 in
        -release | --release )
            shift
            release="$1"
            release_no_dot="`echo $1 | sed -e 's,\.,,g'`"
            ;;
        -stage)
            shift
            stage="$1"
            ;;
        -triple )
            shift
            triple="$1"
            ;;
        -j* )
            num_jobs="`echo $1 | sed -e 's,-j\([0-9]*\),\1,g'`"
            if [ -z "$num_jobs" ]; then
                shift
                num_jobs="$1"
            fi
            ;;
        -src-dir | --src-dir )
            shift
            src_dir="$1"
            ;;
        -build-dir | --build-dir )
            shift
            build_dir="$1"
            ;;
        -install-dir | --install-dir )
            shift
            install_dir="$1"
            ;;
        -dist-dir | --dist-dir )
            shift
            dist_dir="$1"
            ;;
        -debug )
            flavor="Debug"
            do_debug="yes"
            ;;
        -enable-asserts )
            if [ "Release" = "$flavor" ]; then
                flavor="Release+Asserts"
            fi
            do_asserts="yes"
            ;;
        -configure-flags | --configure-flags )
            shift
            extra_configure_flags="$1"
            ;;
        -help | --help | -h )
            usage
            exit 2
            ;;
        * )
            echo "unknown option: $1"
            usage
            exit 2
            ;;
    esac
    shift
done

if [ -z "$release" ]; then
    echo "error: no release specified"
    exit 2
fi
if [ -z "$stage" ]; then
    echo "error: no stage specified"
    exit 2
fi
if [ -z "$src_dir" ]; then
    echo "error: no source directory specified"
    exit 2
fi
if [ -z "$install_dir" ]; then
    echo "error: no install directory specified"
    exit 2
fi
if [ -z "$dist_dir" ]; then
    echo "error: no distribution directory specified"
    exit 2
fi
if [ -z "$num_jobs" ]; then
    num_jobs=`sysctl -n hw.activecpu 2>/dev/null || true`
fi
if [ -z "$num_jobs" ]; then
    num_jobs=`sysctl -n hw.ncpu 2>/dev/null || true`
fi
if [ -z "$num_jobs" ]; then
    num_jobs=`grep -c processor /proc/cpuinfo 2>/dev/null || true`
fi
if [ -z "$num_jobs" ]; then
    num_jobs=3
fi

log_dir="$build_dir/logs"
mkdir -p "$build_dir"
mkdir -p "$log_dir"
cd "$build_dir"

package=clang+llvm-$release-$triple

echo -n > "$log_dir/deferred_errors.log"

function deferred_error() {
    local stage="$1"
    local current_flavor="$2"
    local msg="$3"
    echo "[${current_flavor} stage-${stage}] ${msg}" | tee -a "$log_dir/deferred_errors.log"
}

function check_program_exists() {
    local program="$1"
    if ! type -P $program >/dev/null 2>&1; then
        echo "program '$program' not found!"
        exit 1
    fi
}

check_program_exists 'file'
check_program_exists 'objdump'
check_program_exists 'ninja'

function configure_core() {
    local current_stage="$1"
    local current_flavor="$2"
    local obj_dir="$3"

    local targets=""
    local use_dylib=""
    local install_toolchain_only=""
    local stage_projects=""
    local stage_runtimes=""
    if [ "1" = "$current_stage" ]; then
        targets="X86"
        use_dylib="OFF"
        install_toolchain_only="ON"
        stage_projects="clang;clang-tools-extra;lld"
        stage_runtimes="compiler-rt;libcxx;libcxxabi"
    elif [ "2" = "$current_stage" ]; then
        targets="X86;AArch64;ARM;WebAssembly"
        use_dylib="ON"
        install_toolchain_only="ON"
        stage_projects="clang;clang-tools-extra;lld;lldb;llvm"
        stage_runtimes="compiler-rt;libcxx;libcxxabi;libunwind"
    fi

    case $flavor in
        Release)
            build_type="Release"
            assertions="OFF"
            extra_configure_flags="-DLLVM_OPTIMIZED_TABLEGEN=ON $extra_configure_flags"
            ;;
        Release+Asserts)
            build_type="Release"
            assertions="ON"
            extra_configure_flags="-DLLVM_OPTIMIZED_TABLEGEN=ON $extra_configure_flags"
            ;;
        Debug)
            build_type="Debug"
            assertions="ON"
            ;;
        *)
            echo "# Invalid flavor '$current_flavor'"
            echo ""
            return
            ;;
    esac

    echo "# Using C Compiler:   $c_compiler"
    echo "# Using C++ Compiler: $cxx_compiler"

    cd "$obj_dir"
    echo "# Configuring LLVM $release $flavor"

    echo "#" env CC="$c_compiler" CXX="$cxx_compiler" \
        cmake \
            -GNinja \
            -DCMAKE_BUILD_TYPE=$build_type \
            -DLLVM_ENABLE_ASSERTIONS=$assertions \
            -DLLVM_ENABLE_DOXYGEN=OFF \
            -DLLVM_ENABLE_SPHINX=OFF \
            -DLLVM_ENABLE_BINDINGS=OFF \
            -DLLVM_INCLUDE_EXAMPLES=OFF \
            -DLLVM_INCLUDE_TESTS=OFF \
            -DLLVM_INCLUDE_GO_TESTS=OFF \
            -DLLVM_INCLUDE_BENCHMARKS=OFF \
            -DLLVM_INCLUDE_DOCS=OFF \
            -DLLVM_INCLUDE_OCAMLDOC=OFF \
            -DLLVM_ENABLE_PROJECTS="$stage_projects" \
            -DLLVM_ENABLE_RUNTIMES="$stage_runtimes" \
            -DLLVM_DYLIB_COMPONENTS="all" \
            -DLLVM_BUILD_LLVM_DYLIB="$use_dylib" \
            -DLLVM_LINK_LLVM_DYLIB="$use_dylib" \
            -DLLVM_INSTALL_TOOLCHAIN_ONLY="$install_toolchain_only" \
            $extra_configure_flags \
            "$src_dir/llvm" \
            2>&1 | tee "$log_dir/llvm.configure-stage${stage}-${flavor}.log"
    env CC="$c_compiler" CXX="$cxx_compiler" \
        cmake \
            -GNinja \
            -DCMAKE_BUILD_TYPE=$build_type \
            -DLLVM_ENABLE_ASSERTIONS=$assertions \
            -DLLVM_ENABLE_DOXYGEN=OFF \
            -DLLVM_ENABLE_SPHINX=OFF \
            -DLLVM_ENABLE_BINDINGS=OFF \
            -DLLVM_INCLUDE_EXAMPLES=OFF \
            -DLLVM_INCLUDE_TESTS=OFF \
            -DLLVM_INCLUDE_GO_TESTS=OFF \
            -DLLVM_INCLUDE_BENCHMARKS=OFF \
            -DLLVM_INCLUDE_DOCS=OFF \
            -DLLVM_INCLUDE_OCAMLDOC=OFF \
            -DLLVM_ENABLE_PROJECTS="$stage_projects" \
            -DLLVM_ENABLE_RUNTIMES="$stage_runtimes" \
            -DLLVM_DYLIB_COMPONENTS="all" \
            -DLLVM_BUILD_LLVM_DYLIB="$use_dylib" \
            -DLLVM_LINK_LLVM_DYLIB="$use_dylib" \
            -DLLVM_INSTALL_TOOLCHAIN_ONLY="$install_toolchain_only" \
            $extra_configure_flags \
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

    ninja llvm-config -j $num_jobs -v \
        2>&1 | tee "$log_dir/llvm.make-stage${current_stage}-${current_flavor}.log"

    echo "# Installing LLVM $release $current_flavor"
    echo "# ninja install"
    DESTDIR="${dest_dir}" ninja install \
        2>&1 | tee "$log_dir/llvm.install-stage${current_stage}-${current_flavor}.log"

    cd "$build_dir"
}

function clean_RPATH() {
    local install_path="$1"
    for candidate in `find "${install_path}"/{bin,lib} -type f`; do
        if file "${candidate}" | grep ELF | egrep 'executable|shared object' > /dev/null 2>&1; then
            if rpath=`objdump -x "${candidate}" | grep 'RPATH'`; then
                rpath=`echo $rpath | sed -e's/^ *RPATH *//'`
                if [ -n "$rpath" ]; then
                    newrpath=`echo $rpath | sed -e's/.*\(\$ORIGIN[^:]*\).*/\1/'`
                    chrpath -r $newrpath "${candidate}" >/dev/null 2>&1
                fi
            fi
        fi
    done
}

function install_release() {
    local cwd=`pwd`
    cd "$build_dir/stage2/$flavor"
    mkdir -p "$install_dir"
    cp -R stage2-$release.install/usr/local/* "$install_dir"/
    cd "$cwd"
}

function package_release() {
    local cwd=`pwd`
    cd "$build_dir/stage2/$flavor"
    mv stage2-$release.install/usr/local "$package"
    tar -czf "$dist_dir/$package.tar.gz" "$package"
    mv "$package" stage2-$release.install/usr/local/
    cd "$cwd"
}

set -e
set -o pipefail

echo ""
echo "*************************************"
echo "  Release: $release"
echo "  Build:   $flavor"
echo "  System Info:"
echo "    `uname -a`"
echo "*************************************"
echo ""

stage1_objdir="$build_dir/stage1/$flavor/stage1-$release.obj"
stage1_destdir="$build_dir/stage1/$flavor/stage1-$release.install"

case $stage in
    1)
        echo "# Stage 1: Preparing Build Enviornment"
        c_compiler="$CC"
        cxx_compiler="$CXX"
        rm -rf "$stage1_objdir"
        rm -rf "$stage1_destdir"
        mkdir -p "$stage1_objdir"
        mkdir -p "$stage1_destdir"

        echo "# Stage 1: Building LLVM"
        configure_core 1 $flavor "$stage1_objdir"
        build_core 1 $flavor "$stage1_objdir" "$stage1_destdir"
        clean_RPATH "${stage1_destdir}/usr/local"
        ;;
    2)
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
        stage2_objdir="$build_dir/stage2/$flavor/stage2-$release.obj"
        stage2_destdir="$build_dir/stage2/$flavor/stage2-$release.install"
        rm -rf "$stage2_objdir"
        rm -rf "$stage2_destdir"
        mkdir -p "$stage2_objdir"
        mkdir -p "$stage2_destdir"
        rm -rf "$install_dir"/*

        echo "# Stage 2: Building LLVM"
        configure_core 2 $flavor "$stage2_objdir"
        build_core 2 $flavor "$stage2_objdir" "$stage2_destdir"
        clean_RPATH "${stage2_destdir}/usr/local"

        echo "# Installing the release to ${install_dir}"
        install_release

        echo "# Packaging the release as $package.tar.gz"
        package_release
        ;;
    *)
        echo "Invalid stage '$stage', must be a number 1-2"
        exit 2
        ;;
esac

set +e

echo "### Logs: $log_dir"
echo "### Errors:"
if [ -s "$log_dir/deferred_errors.log" ]; then
    cat "$log_dir/deferred_errors.log"
    exit 1
else
    echo "None"
fi

exit 0
