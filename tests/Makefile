# MIAFX 离线单元测试（宿主 clang，不需要 iOS SDK / Theos）
#
#   make -C tests          # 编译并运行
#   make -C tests clean
#
# 目的：在没有 iPhone SDK 的机器上也能验证纯 C 链路（FFT / 频段 / 环形缓冲 /
# IPC 打包 / 插值重采样）的数值正确性、边界与空指针防御。
# Objective-C / Logos 部分仍需 Theos + iOS 17.1 SDK 真机编译。

CC      ?= cc
CFLAGS  ?= -std=c11 -O1 -g -Wall -Wextra -Wno-unused-parameter -D_DEFAULT_SOURCE
LDFLAGS ?= -lm

ROOT    := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
SHARED  := $(ROOT)/Shared
AUDIO   := $(ROOT)/MIAFXAudio

INCLUDES := -I$(SHARED) -I$(AUDIO)

SOURCES := \
	$(ROOT)/tests/MIAFXUnitTests.c \
	$(AUDIO)/MIAFXFFT.c \
	$(AUDIO)/MIAFXBands.c \
	$(AUDIO)/MIAFXRing.c \
	$(SHARED)/MIAFXIPC.c \
	$(SHARED)/MIAFXSpectrumResample.c

TARGET := logeisland-tests

all: $(TARGET)
	./$(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $(INCLUDES) -o $(TARGET) $(SOURCES) $(LDFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: all clean
