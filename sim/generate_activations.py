import numpy as np

def twos_complement_hex(num):
    if not -128 <= num <= 127:
        raise ValueError("Input must be in the 8-bit signed range (-128 to 127)")

    if num >= 0:
        twos_complement = num
    else:
        twos_complement = (1 << 8) + num  # Equivalent to 256 + num

    return f"{twos_complement:02X}"


def sram_hex_to_txt(array, n, filename):
    if n <= 0:
        print("Group size must be greater than 0.")
        return
    
    try:
        with open(filename, 'w') as file:
            # Iterate through the array in steps of n
            for i in range(0, len(array), n):
                # Slice the array to get the group
                group = array[i:i + n]
                # Reverse the group, convert each element to hex, and join as a single string
                hex_string = ''.join(f"{twos_complement_hex(x)}" for x in reversed(group))
                file.write(hex_string + '\n')
        
        print(f"Data successfully written to {filename}")
    except IOError as e:
        print(f"An error occurred while writing to the file: {e}")

# SPAD parameters
data_width = 64

# Input dimensions
i_h = 6
i_w = 6
i_c = 64
# identifier 12
# Co, H, W, Ci
weights = np.load('model_conv2d_6_Conv2D.npy')


# Reshape into NHWC by flattening
nhwc_weights = weights.flatten()

# Input activations are gaussian
nhwc_inputs = np.random.normal(loc=0, scale=128//3, size=i_h*i_w*i_c).astype(int).clip(-128, 127)

# Write to txt file
sram_hex_to_txt(nhwc_weights, data_width//8, "weights.txt")
sram_hex_to_txt(nhwc_inputs, data_width//8, "inputs.txt")
