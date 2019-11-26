.PHONY: help llvm llvm-with-docs dist docker enable-docs disable-docs

IMAGE_NAME ?= llvm
XDG_DATA_HOME ?= ~/.local/share
BUILD_DOCS ?= OFF
RELEASE ?= 10.0.0
CWD = `pwd`

help:
	@echo "$(IMAGE_NAME) (docs=$(BUILD_DOCS))"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

clean: ## Clean up generated artifacts
	@rm -rf build

llvm: llvm-without-docs ## Build LLVM (alias for llvm-without-docs)

check-mlir:
	cd build/host && ninja check-mlir

llvm-with-docs: enable-docs ## Build LLVM w/documentation
	lumen/utils/build-llvm.sh \
		--flavor="RelWithDebInfo" \
		--targets="X86;AArch64;ARM;WebAssembly" \
		--with-docs \
		--no-examples \
		--no-tests \
		--no-benchmarks \
		--with-dylib \
		--with-assertions \
		--build-prefix=$(CWD)/build/host \
		--install-prefix=$(XDG_DATA_HOME)/llvm/lumen \
		--skip-install


llvm-without-docs: disable-docs ## Build LLVM w/o documentation
	lumen/utils/build-llvm.sh \
		--flavor="RelWithDebInfo" \
		--targets="X86;AArch64;ARM;WebAssembly" \
		--no-docs \
		--no-examples \
		--no-tests \
		--no-benchmarks \
		--with-dylib \
		--with-assertions \
		--build-prefix=$(CWD)/build/host \
		--install-prefix=$(XDG_DATA_HOME)/llvm/lumen \

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
