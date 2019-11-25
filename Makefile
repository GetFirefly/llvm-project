.PHONY: help llvm dist docker

IMAGE_NAME ?= llvm
XDG_DATA_HOME ?= ~/.local/share
BUILD_DOCS ?= OFF
RELEASE ?= 10.0.0

help:
	@echo "$(IMAGE_NAME) (docs=$(BUILD_DOCS))"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

clean: ## Clean up generated artifacts
	@rm -f build

llvm: ## Build LLVM
	@mkdir -p $(XDG_DATA_HOME)/llvm/lumen
	@mkdir -p build/host && \
		cd build/host && \
		cmake \
			-G Ninja \
			-DCMAKE_BUILD_TYPE=RelWithDebInfo \
			-DLLVM_ENABLE_ASSERTIONS=ON \
			-DLLVM_ENABLE_DOXYGEN=$(BUILD_DOCS) \
			-DLLVM_ENABLE_SPHINX=$(BUILD_DOCS) \
			-DLLVM_ENABLE_BINDINGS=OFF \
			-DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra;lld;lldb;llvm;compiler-rt;libcxx;libcxxabi;libunwind" \
			-DLLVM_ENABLE_RUNTIMES="compiler-rt;libcxx;libcxxabi;libunwind" \
			-DLLVM_DISTRIBUTION_COMPONENTS="clang;clang-tools-extra;lld;lldb;llvm;compiler-rt;libcxx;libcxxabi;libunwind" \
			-DLLVM_RUNTIME_DISTRIBUTION_COMPONENTS="compiler-rt;libcxx;libcxxabi;libunwind" \
			-DCMAKE_INSTALL_PREFIX=$(XDG_DATA_HOME)/llvm/lumen \
			-DLLVM_CCACHE_BUILD=ON \
			-DLLVM_OPTIMIZED_TABLEGEN=ON \
			-DLLVM_TARGETS_TO_BUILD="X86;AArch64;ARM;WebAssembly" \
			-DLLVM_INCLUDE_EXAMPLES=OFF \
			-DLLVM_INCLUDE_TESTS=OFF \
			-DLLVM_INCLUDE_GO_TESTS=OFF \
			-DLLVM_INCLUDE_BENCHMARKS=OFF \
			-DLLVM_INCLUDE_DOCS=$(BUILD_DOCS) \
			-DLLVM_INCLUDE_OCAMLDOC=OFF \
			-DLLVM_BUILD_LLVM_DYLIB=ON \
			-DLLVM_LINK_LLVM_DYLIB=ON \
			-DLLVM_INSTALL_TOOLCHAIN_ONLY=OFF \
			-DLLVM_BUILD_DOCS=$(BUILD_DOCS) \
			../../llvm && \
		ninja && \
		ninja install

dist: ## Build an LLVM release distribution
	@mkdir -p lumen/dist/ && \
	cd lumen/ && \
	docker build \
		-t llvm-project:dist \
		--target=dist \
		--build-arg buildscript_args="-release $(RELEASE)" . && \
		lumen/dist/extract-release.sh -release $(RELEASE)

docker: ## Build a Docker image containing an LLVM distribution
	cd lumen/ && \
	docker build \
		-t lumen/llvm:latest \
		--target=release \
		--build-arg buildscript_args="" .
