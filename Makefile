# UnbiasedStrata build.  Needs CMake 3.24+, a C++20 compiler and the CUDA toolkit.  Nothing is downloaded.
BUILD_DIR  ?= build
# RTX 30 (86), RTX 40 (89) and RTX 50 (120) in one binary.  sm_120 needs CUDA 12.8+, and upstream recommends 13.0+.
CUDA_ARCHS ?= 86;89;120
# Volta (sm_70) / Pascal (sm_60): upstream's experimental build, community-tested only.  It needs a
# CUDA 12.x toolkit -- CUDA 13 dropped those architectures and nvcc fails CMake's compiler test on
# "compute_70".  The CUDA 12 build covers sm_60..sm_89 plus PTX, so one binary serves a V100 and an
# L40S/RTX 40 together:
#   CUDA_ARCHS='70;89' EXPERIMENTAL_SM60=1 NVCC=/usr/local/cuda-12.8/bin/nvcc make build
EXPERIMENTAL_SM60 ?= 0
SM60_FLAG  := $(if $(filter 1 ON on true,$(EXPERIMENTAL_SM60)),ON,OFF)
# Pick a specific toolkit (e.g. a 12.x one beside a 13.x default).
NVCC       ?=
NVCC_FLAG  := $(if $(NVCC),-DCMAKE_CUDA_COMPILER=$(NVCC),)
# capped: inside a container nproc reports the host's CPUs, not the container's quota
JOBS       ?= $(shell n=$$(nproc 2>/dev/null || echo 4); [ $$n -gt 16 ] && n=16; echo $$n)

.PHONY: build clean

build:
	@test -f third_party/llama.cpp/ggml/CMakeLists.txt || \
	  { echo "third_party/llama.cpp is empty: run 'git submodule update --init' first"; exit 1; }
	cmake -S . -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_CUDA=ON -DSTRATA_NATIVE_EXPERTS=ON \
	      -DSTRATA_PORTABLE=ON -DSTRATA_BUILD_TESTS=OFF "-DCMAKE_CUDA_ARCHITECTURES=$(CUDA_ARCHS)" \
	      -DSTRATA_EXPERIMENTAL_SM60=$(SM60_FLAG) $(NVCC_FLAG)
	cmake --build $(BUILD_DIR) -j $(JOBS) --target unbiased-strata
	@echo "built: $(BUILD_DIR)/unbiased-strata"

clean:
	rm -rf $(BUILD_DIR)
