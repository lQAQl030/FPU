# Makefile for Verilator FPU Simulation

# --- Tool Configuration ---
ifeq ($(VERILATOR_ROOT),)
VERILATOR_ROOT = /usr/local/share/verilator
endif

# --- Project Configuration ---
TOP_MODULE = FPU_Top
TB_CPP = tb_fpu.cpp
SIM_EXE = V$(TOP_MODULE)

# --- Verilog Source Files ---
VERILOG_SOURCES = \
    FP_Encoder.sv \
    FP_Decoder.sv \
    FP_Adder_Subtractor.sv \
    FP_Multiplier.sv \
    FP_Divider.sv \
    FP_Sqrt.sv \
    FP_Compare.sv \
    FP_Convert.sv \
    FPU_Top.sv

# --- Verilator Flags ---
VERILATOR_FLAGS = --cc --exe --trace -Wall -Wno-fatal -Wno-WIDTH -Wno-SELRANGE -Wno-PINCONNECTEMPTY

# --- C++ Compiler Flags ---
# ** FIX: Use C++14 standard **
CXX_FLAGS = -std=c++14

# --- 目標 ---
all: $(SIM_EXE)

$(SIM_EXE): obj_dir/V$(TOP_MODULE).mk
	@echo "Linking C++ model..."
	@make -C obj_dir -f V$(TOP_MODULE).mk

obj_dir/V$(TOP_MODULE).mk: $(VERILOG_SOURCES) $(TB_CPP)
	@echo "Verilating $(TOP_MODULE)..."
	@verilator $(VERILATOR_FLAGS) $(VERILOG_SOURCES) --top-module $(TOP_MODULE) --exe $(TB_CPP) -CFLAGS "$(CXX_FLAGS)"

run: $(SIM_EXE)
	@echo "Running simulation..."
	@./obj_dir/$(SIM_EXE)

wave:
	@echo "Opening waveform..."
	@gtkwave waveform.vcd

clean:
	@echo "Cleaning up..."
	@rm -rf obj_dir
	@rm -f waveform.vcd
	@rm -f $(SIM_EXE)

.PHONY: all run wave clean
