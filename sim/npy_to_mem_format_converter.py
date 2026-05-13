import numpy as np
import tflite
import os
import math

# ============================================================
# Hardware SRAM packing parameters
# ============================================================

SPAD_DATA_WIDTH = 32
SPAD_N = SPAD_DATA_WIDTH // 8  # bytes per SRAM line


# ============================================================
# Convert tensor data into packed .mem hex format
# ============================================================

def sram_hex_to_mem_format(data, filename):
    flat_data = data.flatten().view(np.int8)

    with open(filename, 'w') as f:
        for i in range(0, len(flat_data), SPAD_N):

            # Group bytes into SRAM-width chunks
            group = flat_data[i:i + SPAD_N]

            # Zero-pad final line if needed
            if len(group) < SPAD_N:
                group = np.pad(group, (0, SPAD_N - len(group)), mode='constant')

            # Reverse for little-endian packing
            hex_string = ''.join(f"{int(x) & 0xff:02x}" for x in reversed(group))

            f.write(hex_string + '\n')


# ============================================================
# Extract quantization parameters from tensor
# ============================================================

def get_quantization_params(tensor):
    quant = tensor.Quantization()

    if quant is None:
        return None, None

    scales = [quant.Scale(i) for i in range(quant.ScaleLength())]
    zero_points = [quant.ZeroPoint(i) for i in range(quant.ZeroPointLength())]

    return scales, zero_points


# ============================================================
# Convert floating-point scale into fixed-point
# multiplier + shift pair for requantization
# ============================================================

def quantize_multiplier(real_multiplier, precision=16):

    if real_multiplier == 0.0:
        return 0, 0

    # real_multiplier = significand * 2^exponent
    significand, exponent = math.frexp(real_multiplier)

    # Convert significand into fixed-point integer
    q = int(round(significand * (1 << precision)))

    # Handle edge-case overflow
    if q == (1 << precision):
        q //= 2
        exponent += 1

    # Return integer multiplier and right shift
    return q, -exponent


# ============================================================
# Load TFLite model
# ============================================================

model_path = r"C:\Users\Aaron\Documents\EEE196\person_detect.tflite"
destination_path = r"C:\Users\Aaron\Documents\EEE196\ps-cnn-accelerator\person_tflite_extracted"

with open(model_path, 'rb') as f:
    buf = f.read()

model = tflite.Model.GetRootAsModel(buf, 0)
subgraph = model.Subgraphs(0)

os.makedirs(destination_path, exist_ok=True)


# ============================================================
# Build tensor lookup table
# ============================================================

tensor_map = {}

for i in range(subgraph.TensorsLength()):
    tensor_map[i] = subgraph.Tensors(i)


# ============================================================
# Iterate through operators in execution order
# ============================================================

layer_index = 0

from tflite.BuiltinOperator import BuiltinOperator

for op_idx in range(subgraph.OperatorsLength()):

    op = subgraph.Operators(op_idx)

    opcode_idx = op.OpcodeIndex()
    opcode = model.OperatorCodes(opcode_idx)
    builtin_code = opcode.BuiltinCode()

    # Only process conv/depthwise layers
    op_name = {
        BuiltinOperator.CONV_2D: "conv",
        BuiltinOperator.DEPTHWISE_CONV_2D: "dw",
    }.get(builtin_code, None)

    if op_name is None:
        continue


    # ========================================================
    # Extract input/output tensors
    # ========================================================

    in_tensor_idx = op.Inputs(0)
    out_tensor_idx = op.Outputs(0)

    in_tensor = tensor_map[in_tensor_idx]
    out_tensor = tensor_map[out_tensor_idx]

    in_scales, in_zero_points = get_quantization_params(in_tensor)
    out_scales, _ = get_quantization_params(out_tensor)

    # TFLite activations are usually per-tensor quantized
    in_scale = in_scales[0] if in_scales else 1.0
    out_scale = out_scales[0] if out_scales else 1.0

    # Input activation zero-point
    input_zero_point = in_zero_points[0] if in_zero_points else 0


    # ========================================================
    # Extract weight tensor
    # ========================================================

    weight_tensor_idx = op.Inputs(1)
    weight_tensor = tensor_map[weight_tensor_idx]

    weight_shape = [
        weight_tensor.Shape(i)
        for i in range(weight_tensor.ShapeLength())
    ]

    # Detect pointwise conv (1x1 Conv2D)
    if op_name == "conv" and len(weight_shape) == 4 and weight_shape[1] == 1 and weight_shape[2] == 1:
        op_name = "pw"

    # TFLite int8 weights are usually per-channel quantized
    w_scales, _ = get_quantization_params(weight_tensor)


    # ========================================================
    # Compute requantization multipliers/shifts
    #
    # effective_scale = (S_in * S_w) / S_out
    # ========================================================

    if w_scales:

        multipliers = []
        shifts = []

        for w_scale in w_scales:

            effective_scale = (in_scale * w_scale) / out_scale

            m, s = quantize_multiplier(
                effective_scale,
                precision=16
            )

            multipliers.append(m)
            shifts.append(s)

        mult_array = np.array(multipliers, dtype=np.uint16)
        shift_array = np.array(shifts, dtype=np.uint8)

        m_filename = f"layer{layer_index}_{op_name}_multipliers.mem"
        s_filename = f"layer{layer_index}_{op_name}_shifts.mem"

        sram_hex_to_mem_format(
            mult_array,
            os.path.join(destination_path, m_filename)
        )

        sram_hex_to_mem_format(
            shift_array,
            os.path.join(destination_path, s_filename)
        )

        print(f"Extracted multipliers/shifts for {op_name}")


    # ========================================================
    # Extract weights
    # ========================================================

    w_buffer = model.Buffers(weight_tensor.Buffer())

    weights = None

    if w_buffer.DataLength() > 0:

        raw_weights = w_buffer.DataAsNumpy()

        w_filename = f"layer{layer_index}_{op_name}_weights.mem"

        sram_hex_to_mem_format(
            raw_weights,
            os.path.join(destination_path, w_filename)
        )

        print(f"Extracted: {w_filename} | Shape: {weight_shape}")

        # Reshape into tensor format
        weights = raw_weights.view(np.int8).reshape(weight_shape)


    # ========================================================
    # Extract and correct bias
    #
    # Hardware computes:
    #   sum(x*w)
    #
    # True quantized conv is:
    #   sum((x-zx)*w)
    #
    # Expands to:
    #   sum(x*w) - zx*sum(w)
    #
    # So fold correction into bias:
    #
    #   b_corrected = b - zx*sum(w)
    # ========================================================

    if op.InputsLength() > 2:

        bias_tensor_idx = op.Inputs(2)

        if bias_tensor_idx >= 0:

            bias_tensor = tensor_map[bias_tensor_idx]
            b_buffer = model.Buffers(bias_tensor.Buffer())

            if b_buffer.DataLength() > 0:

                raw_bias = b_buffer.DataAsNumpy().view(np.int32)

                if weights is not None:

                    # Standard Conv / Pointwise Conv
                    #
                    # Weight layout:
                    # [OutC, H, W, InC]
                    #
                    # Sum over H,W,InC
                    if op_name in ["conv", "pw"]:

                        weight_sums = (
                            weights
                            .astype(np.int32)
                            .sum(axis=(1, 2, 3))
                        )

                    # Depthwise Conv
                    #
                    # Weight layout:
                    # [1, H, W, OutC]
                    #
                    # Sum over H,W,input-group
                    elif op_name == "dw":

                        weight_sums = (
                            weights
                            .astype(np.int32)
                            .sum(axis=(0, 1, 2))
                        )

                    else:
                        weight_sums = np.zeros_like(raw_bias)

                else:
                    weight_sums = np.zeros_like(raw_bias)

                # Apply zero-point correction
                corrected_bias = raw_bias - input_zero_point * weight_sums

                b_filename = f"layer{layer_index}_{op_name}_bias.mem"

                sram_hex_to_mem_format(
                    corrected_bias.astype(np.int32),
                    os.path.join(destination_path, b_filename)
                )

                print(f"Extracted corrected bias: {b_filename}")


    # ========================================================
    # Advance layer index
    # ========================================================

    layer_index += 1

print("\nDone.")