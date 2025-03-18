# Get input size, stride, precision, and how data is generated (random or sequential)
# Determine the output size
# Generate input array either randomly or sequentially (based on user input)
# Generate kernel array either randomly or sequentially (based on user input)
# Generate output array based on input array and stride
# Output the input, kernel, and output arrays to a file
# Run VCS or Icarus Verilog simulation
# Output the results to a file


import argparse
import subprocess
import random
import numpy as np

def generate_sequential_array(input_size, precision):
    max_value = 1 << precision
    total_elements = input_size * input_size
    array_1d = [i % max_value for i in range(total_elements)]
    
    array_2d = []
    for row_index in range(input_size):
        start = row_index * input_size
        end = start + input_size
        array_2d.append(array_1d[start:end])
    
    return array_2d

def generate_random_2d_array(input_size, precision):
    max_value = (1 << precision) - 1
    array_2d = []

    for _ in range(input_size):
        row = [random.randint(0, max_value) for _ in range(input_size)]
        array_2d.append(row)
    
    return array_2d

def generate_random_3d_array(input_size, channels, precision):
    max_value = (1 << precision) - 1
    array_3d = []

    for _ in range(channels):
        channel = []
        for _ in range(input_size):
            row = [random.randint(0, max_value) for _ in range(input_size)]
            channel.append(row)
        array_3d.append(channel)
    
    return array_3d

def convolve_2d(input_matrix, kernel, stride=1):
    input_rows = len(input_matrix)
    input_cols = len(input_matrix[0])
    kernel_size = len(kernel)
    
    output_rows = (input_rows - kernel_size) // stride + 1
    output_cols = (input_cols - kernel_size) // stride + 1

    output = [[0 for _ in range(output_cols)] for _ in range(output_rows)]
    
    for i in range(0, output_rows * stride, stride):
        for j in range(0, output_cols * stride, stride):
            sum_value = 0
            for ki in range(kernel_size):
                for kj in range(kernel_size):
                    sum_value += input_matrix[i + ki][j + kj] * kernel[ki][kj]
            output[i // stride][j // stride] = sum_value
    

    hex_output = [[format(val, 'x') for val in row] for row in output]
    
    return (hex_output, output_rows)

# Helper Functions
def flatten_2d_array(a):
    return [i for r in a for i in r]

def flatten_3d_array(arr):
    return [item for row in arr for col in row for item in col]

# n is how many bytes the theoretical SPAD can hold
def array_to_file(array, n, filename):
    if n <= 0:
        print("Group size must be greater than 0.")
        return
    
    try:
        with open(filename, 'w') as file:
            for i in range(0, len(array), n):
                group = array[i:i + n]
                hex_string = ''.join(f"{x:02x}" for x in reversed(group))
                file.write(hex_string + '\n')
        
        print(f"Data successfully written to {filename}")
    except IOError as e:
        print(f"An error occurred while writing to the file: {e}")

def output_to_file(array, n, filename):
    if n <= 0:
        print("Group size must be greater than 0.")
        return
    
    try:
        with open(filename, 'w') as file:
            for i in range(0, len(array), n):
                group = array[i:i + n]
                file.write(group[0] + '\n')
        
        print(f"Data successfully written to {filename}")
    except IOError as e:
        print(f"An error occurred while writing to the file: {e}")

def to_precision(number, bits):
    n = f"{(number & ((1<<bits)-1)):0{bits}b}"
    n = n[0]*(32-bits)+n
    num = int(n, 2)
    if num >= 2**(bits-1):
        num -= 2**32
    return num

def format_output(array):
    flattened_array = []
    
    for i in range(0, len(array), 2):
        first_part = array[i][-2:]
        
        if i + 1 < len(array):
            second_part = array[i+1][-2:]
        else:
            second_part = "00"
        
        combined_value = first_part + second_part
        flattened_array.append(combined_value)
    
    return flattened_array

def convert_nchw_to_nhwc(nchw_array):
    channels = len(nchw_array)
    height = len(nchw_array[0])
    width = len(nchw_array[0][0])

    # Initialize NHWC array with shape (height, width, channels)
    nhwc_array = [[[nchw_array[c][h][w] for c in range(channels)] 
                   for w in range(width)] 
                   for h in range(height)]
    
    return nhwc_array

def main():
    parser = argparse.ArgumentParser(description="Process input parameters.")
    parser.add_argument("input_size", type=int, help="Size of input")
    parser.add_argument("channels", type=int, help="Number of channels")
    parser.add_argument("stride", type=int, help="Stride value")
    parser.add_argument("precision", type=int, help="Precision value")

    args = parser.parse_args()

    input_size = args.input_size
    channels = args.channels
    stride = args.stride
    precision = args.precision

    C_in = channels
    C_out = channels

    output_size = input_size

    input_array = []
    for _ in range(channels):
        input_array.append(generate_sequential_array(input_size, precision))

    #print(input_array)

    kernel = generate_sequential_array(channels, precision)

    # for _ in range(C_out):
    #     kernel.append([j for j in range(C_in)])
    nhwc_array = convert_nchw_to_nhwc(input_array)

    array_to_file(flatten_3d_array(nhwc_array), 8, "ifmap.txt")
    array_to_file(flatten_2d_array(kernel), 8, "kernel.txt")
    # output, output_size = convolve_2d(input_array[0], kernel, stride)

    

    print(f'Input Size: {input_size}\nNumber of Channels: {channels}\nOutput Size: {output_size}\nStride: {stride}\nPrecision: {precision}')
    if (input_size <= 10):
        print("---------------------------------------------------------------")
        print("Input:")
        for ia in input_array:
            print(np.matrix(ia))

        print("\nKernel:")
        print(np.matrix(kernel))
        # print("Output:")
        # print(output)

    # # Write input, kernel, and output arrays to files

    # output_to_file(format_output(flatten_2d_array(output)), 1, "golden_output.txt")

    # defaults to 8-bit precision
    p_mode = 0
    if precision == 4:
        p_mode = 1
    elif precision == 2:
        p_mode = 2

    header = f"""`define INPUT_SIZE {input_size}
    `define CHANNEL_SIZE {channels}
    `define OUTPUT_CHANNEL {channels}
    `define CHANNEL {0}
    `define OUTPUT_SIZE {output_size}
    `define STRIDE {stride}
    `define PRECISION {p_mode}"""

    with open("tb_top.svh", "w") as file:
        file.write(header)
    
    print("tb_top.svh file has been generated.")

    vcs_cmd = "vcs tb_top.sv ../mapped/top_mapped.v /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/verilog/GF22FDX_SC7P5T_116CPP_BASE_CSC20L.v /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/verilog/prim.v -sverilog -full64 -debug_pp +neg_tchk -R -l vcs.log"
    # To add specific which channel to convolve
    

    result = subprocess.run(vcs_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    print(result.stdout)
    # # Check if the difference of output and golden_output
    # sim_command = "diff output.txt golden_output.txt"
    # result = subprocess.run(sim_command, shell=True, capture_output=True, text=True)
    # print('\nOutput vs Golden Comparison:')
    # if result.stdout:
    #     print("Differences found :(")
    #     #print(result.stdout)
    # else:
    #     print("No differences found :)")

if __name__ == "__main__":
    main()
