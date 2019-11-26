#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
UTILS_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$UTILS_DIR")"

# Disable lldb on macOS by default
if [ "$(uname -s)" = "Darwin" ]; then
    enable_projects="clang;clang-tools-extra;lld;llvm"
else
    enable_projects="clang;clang-tools-extra;lld;lldb;llvm"
fi

flavor="RelWithDebInfo"
targets="X86"
enable_runtimes="compiler-rt;libcxx;libcxxabi;libunwind"
enable_bindings="OFF"
enable_docs="OFF"
enable_examples="OFF"
enable_tests="OFF"
enable_benchmarks="OFF"
enable_dylib="OFF"
enable_assertions="OFF"
build_prefix=""
install_prefix=""
skip_install=""
enable_ccache="OFF"
enable_optimized_tablegen="ON"
configure_flags=""


function usage() {
    echo "usage: $(basename "$0") -install-prefix=/usr/local [OPTIONS]"
    echo ""
    echo " -flavor                 The type of build (Release, RelWithDebInfo, Debug)"
    echo " -targets TARGET         A semicolon-separated list of targets to support"
    echo " -configure-flags FLAGS  A string containing flags to be passed to CMake"
    echo " -build-prefix DIR       The directory to perform the build in"
    echo " -install-prefix DIR     The installation prefix directory"
    echo " -skip-install           Do not perform install step at end of build"
    echo " -with-assertions        Enable debug assertions"
    echo " -with-dylib             Build LLVM as a dynamic library"
    echo " -with-docs              Build documentation"
    echo " -no-docs                Do not build documentation"
    echo " -with-examples          Build examples"
    echo " -no-examples            Do not build examples"
    echo " -with-tests             Build tests"
    echo " -no-tests               Do not build tests"
    echo " -with-benchmarks        Build benchmarks"
    echo " -no-benchmarks          Do not build benchmarks"
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
        -flavor | --flavor)
            flavor="$rhs"
            has_value="true"
            ;;
        -targets | --targets)
            targets="$rhs"
            has_value="true"
            ;;
        -configure-flags | --configure-flags)
            configure_flags="$rhs"
            has_value="true"
            ;;
        -install-prefix | --install-prefix)
            install_prefix="$rhs"
            has_value="true"
            ;;
        -build-prefix | --build-prefix)
            build_prefix="$rhs"
            has_value="true"
            ;;
        -skip-install | --skip-install)
            skip_install="true"
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
        -with-dylib | --with-dylib)
            enable_dylib="ON"
            ;;
        -with-assertions | --with-assertions)
            enable_assertions="ON"
            ;;
        -help | --help)
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

if [ -z "$install_prefix" ]; then
    echo "error: no install prefix specified"
    exit 2
fi
if [ -z "$build_prefix" ]; then
    echo "error: no build prefix specified"
    exit 2
fi
if [ -n "$flavor" ]; then
    case $flavor in
        Release | RelWithDebInfo | Debug)
            ;;
        *)
            echo "error: invalid flavor, expected Release, RelWithDebInfo or Debug"
            exit 2
            ;;
    esac
fi

if ! type -p ninja >/dev/null; then
    echo "Could not find ninja executable!"
    exit 2
fi

if type -p ccache >/dev/null; then
    echo "Found ccache, enabling for build"
    enable_ccache="ON"
fi

if [ ! -d "${ROOT_DIR}/llvm/projects/mlir" ]; then
    echo "MLIR repo missing, fetching current version.."
    if ! git clone https://github.com/lumen/mlir "${ROOT_DIR}/llvm/projects/mlir"; then
        echo "Unable to fetch MLIR!"
        exit 2
    fi
fi

mkdir -p "${build_prefix}"
cd "${build_prefix}"

echo "Configuring.."
echo ""
# shellcheck disable=2086
# TODO: When mlir moves to root:
#  -DLLVM_EXTERNAL_PROJECTS="mlir" \
#  -DLLVM_EXTERNAL_MLIR_SOURCE_DIR="${ROOT_DIR}/mlir/" \
if ! cmake \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=$flavor \
        -DCMAKE_INSTALL_PREFIX="${install_prefix}" \
        -DLLVM_TARGETS_TO_BUILD="$targets" \
        -DLLVM_CCACHE_BUILD=$enable_ccache \
        -DLLVM_OPTIMIZED_TABLEGEN=$enable_optimized_tablegen \
        -DLLVM_BUILD_LLVM_DYLIB=$enable_dylib \
        -DLLVM_LINK_LLVM_DYLIB=$enable_dylib \
        -DLLVM_INSTALL_TOOLCHAIN_ONLY=OFF \
        -DLLVM_ENABLE_ASSERTIONS=$enable_assertions \
        -DLLVM_ENABLE_BINDINGS=$enable_bindings \
        -DLLVM_INCLUDE_EXAMPLES=$enable_examples \
        -DLLVM_INCLUDE_BENCHMARKS=$enable_benchmarks \
        -DLLVM_BUILD_DOCS=$enable_docs \
        -DLLVM_ENABLE_DOXYGEN=$enable_docs \
        -DLLVM_ENABLE_SPHINX=$enable_docs \
        -DLLVM_INCLUDE_DOCS=$enable_docs \
        -DLLVM_INCLUDE_OCAMLDOC=OFF \
        -DLLVM_INCLUDE_TESTS=$enable_tests \
        -DLLVM_INCLUDE_GO_TESTS=OFF \
        -DLLVM_ENABLE_PROJECTS="$enable_projects" \
        -DLLVM_ENABLE_RUNTIMES="$enable_runtimes" \
        ${configure_flags} \
        "${ROOT_DIR}/llvm"; then
    echo ""
    echo "Configuration failed, unable to proceed."
    exit 1
fi

echo "Building.."
echo ""

if ! ninja mlir-tblgen; then
    echo "Build precondition 'mlir-tblgen' failed!"
    exit 1
fi
if ! ninja; then
    echo "Build failed!"
    exit 1
fi

echo "Build succesful!"
echo ""

if [ "$skip_install" != "true" ]; then
    echo "Installing.."
    echo ""
    if ! ninja install; then
        echo "Installation failed!"
        exit 1
    fi

    echo "Installation successful!"
    echo "Run ${install_prefix}/bin/llvm-config --version to test"
else
    echo "Skipping install, as --skip-install was given"
    exit 0
fi


exit 0
