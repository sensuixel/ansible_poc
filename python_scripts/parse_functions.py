#!/usr/bin/python3

# Function to get block of data
def get_block(file_name, begin_string):
    data_list = []
    keep_current_block  = False
    # Read file
    for line in open(file_name):        
        # Begin of block
        if line.startswith(begin_string):
            # Set flag On
            keep_current_block = True
        # Keep Current Data
        if keep_current_block:
            data_list.append(line.strip('\n'))

        # End of block = Empty line
        if keep_current_block and line.startswith('END_OF_BLOCK'):
            # Set flag On
            keep_current_block = False
            
           
    #
    return [ x for x in data_list[1:-1] if x ]
