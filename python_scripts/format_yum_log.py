#!/usr/bin/python3
import glob
import os.path

for f in glob.glob('/home/pichard/ansible/aix_output/**/yum_update*txt', recursive=True):
    # test if file is already a fmt file
    if '_fmt' not in f:
        # process each file
        print("Processing file {}".format(f))
        with open(f, 'r') as file:
            # Get path, file name with no extension
            fmt_file_name = os.path.splitext(f)[0] + "_fmt.txt"
        
            # Get all line of file
            data = file.read()
        
            # Open new file name for output
            with open(fmt_file_name, 'w') as out_file:
                # Remove garbage
                out_file.write('\n'.join(data.replace('\\r','').split('\\n')))