#!/usr/bin/python3
import glob
import os.path
from packaging import version

# custom functions
from parse_functions import *

# Constant
SEP = ':'
ROOT_PATH = '/home/pichard/ansible/aix_output'
REPORT_PATH = '/home/pichard/ansible/aix_report'
   

# Read trace file and parse result of lspp -lc command 
for f in glob.glob(f'{ROOT_PATH}/**/update_preview*txt', recursive=True):
    # Get lpar name from file
    lpar_name_tmp = f.split(ROOT_PATH)[1]
    lpar_name = lpar_name_tmp.split('/')[1]

    # Look for FAILED pre-installation wihin file
    with open(f, 'r') as infile:
        if 'FAILED pre-installation' in infile.read():
            # Open report file 
            with open( os.path.join(REPORT_PATH, f'{lpar_name}_update_preview_report.txt'), 'w') as report_file:
                print(f'{lpar_name} ==> update preview has failed look for {f} \n')
                report_file.write(f'{lpar_name} ==> update preview has failed look for {f} \n') 
        
print(f'See result in {REPORT_PATH} if problem were detected !')
    
                
