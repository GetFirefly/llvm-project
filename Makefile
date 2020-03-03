.PHONY: help llvm llvm-with-docs dist docker enable-docs disable-docs

IMAGE_NAME ?= llvm
XDG_DATA_HOME ?= ~/.local/share
BUILD_DOCS ?= OFF
RELEASE ?= 10.0.0
CWD = `pwd`

help:
	@echo "$(IMAGE_NAME):$(RELEASE) (docs=$(BUILD_DOCS))"
	@echo ""
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

clean: ## Clean up generated artifacts
	@rm -rf build/host

llvm: llvm-without-docs ## Build LLVM (alias for llvm-without-docs)

llvm-shared: disable-docs ## Build LLVM with BUILD_SHARED_LIBS=ON
	CC=$(CC) CXX=$(CXX) lumen/utils/dist/build-dist.sh \
		--release="$(RELEASE)" \
		--flavor="RelWithDebInfo" \
		--targets="X86;AArch64;ARM;WebAssembly" \
		--build-shared \
		--with-assertions \
		--build-dir=$(CWD)/build/host \
		--install-dir=$(XDG_DATA_HOME)/llvm/lumen \
		--skip-dist

check-mlir:
	cd build/host && ninja check-mlir

llvm-with-docs: enable-docs ## Build LLVM w/documentation
	CC=$(CC) CXX=$(CXX) lumen/utils/dist/build-dist.sh \
		--release="$(RELEASE)" \
		--flavor="RelWithDebInfo" \
		--targets="X86;AArch64;ARM;WebAssembly" \
		--with-docs \
		--with-assertions \
		--build-dir=$(CWD)/build/host \
		--skip-install \
		--skip-dist


llvm-without-docs: disable-docs ## Build LLVM w/o documentation
	CC=$(CC) CXX=$(CXX) lumen/utils/dist/build-dist.sh \
		--release="$(RELEASE)" \
		--flavor="RelWithDebInfo" \
		--targets="X86;AArch64;ARM;WebAssembly" \
		--with-assertions \
		--build-dir=$(CWD)/build/host \
		--install-dir=$(XDG_DATA_HOME)/llvm/lumen \
		--skip-dist

enable-docs:
	@echo "Configuring Doxygen.."
	@sed -E \
		-e 's/^(GENERATE_DOCSET[ ]+= )NO/\1YES/' \
		-e 's/^(DISABLE_INDEX[ ]+= )NO/\1YES/' \
		-e 's/^(SEARCHENGINE[ ]+= )@enable_searchengine@/\1NO/' \
		-e 's/^(GENERATE_TAGFILE[ ]+=)[ ]*/\1 llvm.tags/' \
		-i '' \
		llvm/docs/doxygen.cfg.in

disable-docs:
	@echo "Disabling Doxygen.."
	@git checkout --quiet llvm/docs/doxygen.cfg.in

dist-macos: ## Build an LLVM release distribution for x86_64-apple-darwin
	@mkdir -p build/packages/ && \
	CC=$(CC) CXX=$(CXX) lumen/utils/dist/build-dist.sh \
		--release="$(RELEASE)" \
		--flavor="Release" \
		--targets="X86;AArch64;ARM;WebAssembly" \
		--with-assertions \
		--build-dir=$(CWD)/build/release \
		--install-dir=$(CWD)/build/x86_64-apple-darwin \
		--dist-dir=$(CWD)/build/packages

dist-linux: ## Build an LLVM release distribution for x86_64-unknown-linux
	@mkdir -p build/packages/ && \
	cd lumen/ && \
	docker build \
		-t llvm-project:dist \
		--target=dist \
		--build-arg buildscript_args="-release=$(RELEASE)" . && \
		lumen/utils/dist/extract-release.sh -release $(RELEASE)

docker: ## Build a Docker image containing an LLVM distribution
	cd lumen/ && \
	docker build \
		-t lumen/llvm:latest \
		--target=release \
		--build-arg buildscript_args="" .
