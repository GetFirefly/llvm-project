.PHONY: help llvm llvm-with-docs dist docker enable-docs disable-docs

IMAGE_NAME ?= llvm
XDG_DATA_HOME ?= $(HOME)/.local/share
BUILD_DOCS ?= OFF
RELEASE ?= 15.0.0
FLAVOR ?= RelWithDebInfo
SHA ?= `git rev-parse --short HEAD`
CWD = `pwd`
ARCH = `uname -m`
TARGET_SUPPORT ?= X86;AArch64;WebAssembly
ifeq ($(ARCH),arm64)
	ARCH=aarch64
endif

help:
	@echo "$(IMAGE_NAME):$(RELEASE)-$(SHA) (docs=$(BUILD_DOCS))"
	@echo ""
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

clean: ## Clean up generated artifacts
	@rm -rf build/host

llvm: llvm-without-docs ## Build LLVM (alias for llvm-without-docs)

llvm-shared: disable-docs ## Build LLVM with BUILD_SHARED_LIBS=ON
	CC=$(CC) CXX=$(CXX) firefly/utils/dist/build-dist.sh \
		--release="$(RELEASE)" \
		--flavor="$(FLAVOR)" \
		--targets="$(TARGET_SUPPORT)" \
		--with-dylib \
		--link-dylib \
		--with-assertions \
		--build-dir=$(CWD)/build/host_shared \
		--install-dir=$(XDG_DATA_HOME)/llvm/firefly \
		--skip-dist

check-mlir:
	cd build/host/stage2/RelWithDebInfo/stage2-$(RELEASE).obj && ninja check-mlir

llvm-with-docs: enable-docs ## Build LLVM w/documentation
	CC=$(CC) CXX=$(CXX) firefly/utils/dist/build-dist.sh \
		--release="$(RELEASE)" \
		--flavor="$(FLAVOR)" \
		--targets="$(TARGET_SUPPORT)" \
		--with-docs \
		--with-assertions \
		--build-dir=$(CWD)/build/host \
		--skip-install \
		--skip-dist


llvm-without-docs: disable-docs ## Build LLVM w/o documentation
	CC=$(CC) CXX=$(CXX) firefly/utils/dist/build-dist.sh \
		--release="$(RELEASE)" \
		--flavor="$(FLAVOR)" \
		--targets="$(TARGET_SUPPORT)" \
		--with-assertions \
		--build-dir=$(CWD)/build/host \
		--install-dir=$(XDG_DATA_HOME)/llvm/firefly \
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
	@mkdir -p build/packages/dist && \
	CC=$(CC) CXX=$(CXX) firefly/utils/dist/build-dist.sh \
		--release="$(RELEASE)" \
		--flavor="$(FLAVOR)" \
		--targets="$(TARGET_SUPPORT)" \
		--with-assertions \
		--with-dylib \
		--link-dylib \
		--build-dir=$(CWD)/build/release \
		--install-dir=$(CWD)/build/$(ARCH)-apple-darwin \
		--dist-dir=$(CWD)/build/packages/dist \
		--clean-obj

dist-linux: dist-linux-stage1 dist-linux-stage2 ## Build an LLVM release distribution for x86_64-apple-darwin

dist-linux-stage2:
	CC=$(CC) CXX=$(CXX) firefly/utils/dist/build-dist.sh \
	   	--stage=2 \
		--release="$(RELEASE)" \
		--flavor="$(FLAVOR)" \
		--targets="$(TARGET_SUPPORT)" \
		--with-assertions \
		--with-static-libc++ \
		--with-dylib \
		--link-dylib \
		--build-dir=$(CWD)/build/release \
		--install-dir=$(CWD)/build/$(ARCH)-linux-unknown-gnu \
		--dist-dir=$(CWD)/build/packages/dist

dist-linux-stage1:
	@mkdir -p build/packages/dist && \
	CC=$(CC) CXX=$(CXX) firefly/utils/dist/build-dist.sh \
		--stage=1 \
		--release="$(RELEASE)" \
		--flavor=Release \
		--build-dir=$(CWD)/build/release \
		--install-dir=$(CWD)/build/$(ARCH)-linux-unknown-gnu \
		--dist-dir=$(CWD)/build/packages/dist
	

dist-linux-docker: ## Build an LLVM release distribution for x86_64-unknown-linux
	@mkdir -p build/packages/ && \
	cd firefly/ && \
	docker build \
		-t llvm-project:dist-$(RELEASE)-$(SHA) \
		--target=dist \
		--build-arg buildscript_args="-release=$(RELEASE) -with-dylib -link-dylib -flavor=$(FLAVOR) -clean-obj -j=2" . && \
		utils/dist/extract-release.sh -release $(RELEASE) -sha $(SHA)

docker: ## Build a Docker image containing an LLVM distribution
	cd firefly/ && \
	docker build \
		-t firefly/llvm:latest \
		--target=release \
		--build-arg buildscript_args="-release=$(RELEASE) -with-dylib -link-dylib -flavor=$(FLAVOR) -clean-obj -j=2" .
