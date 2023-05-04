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
VRMF_REF = {
    "GSK" : "8.0.50.88",
    "idsldap" : "6.4.0.20",
    }
    

# Read trace file and parse result of lspp -lc command 
for f in glob.glob(f'{ROOT_PATH}/**/trace_initial_*txt', recursive=True):
    # Get lpar name from file
    lpar_name_tmp = f.split(ROOT_PATH)[1]
    lpar_name = lpar_name_tmp.split('/')[1]

    # test if file is already a fmt file
    if '_fmt' not in f:
        # process each file
        #print("Processing file {}".format(f))
        
        # Parse lpp data
        lpp_data = get_block(f, "lslpp -lc")
        #print(lpp_data)
        # Get dict
        # 1. k = lpp / { k = VRMF , k = Status }
        # 2. k = lpp / v = Status
        lpp_dict = { x.split(SEP)[1]:{ "VRMF":x.split(SEP)[2],"STATUS": x.split(SEP)[4] } for x in lpp_data if x }
        
        # Parse emgr -l data
        emgr_data = get_block(f, "emgr -l")
        
        # Parse rpm -qa
        rpm_data = get_block(f, "rpm -qa") 
        
        # parse yum check
        yum_data = get_block(f, "yum check")
        
        # Parse lsvg -l rootvg
        rootvg_data = get_block(f, "lsvg -l rootvg")
        
        # Parse df -tg $(lsvgfs rootvg)
        rootvg_space = get_block(f, "df -tg $(lsvgfs rootvg)")
        mount_list = [ '/usr', '/var', '/opt', '/home', '/tmp' ] # Mount point to check
        size_treshold = float(0.25)                              # 250 MB
        # List mount point with freespace below size_threshold
        sz_dict = { x.split()[5]:float(x.split()[3]) for x in rootvg_space[1:] if x.split()[5] in mount_list and float(x.split()[3]) <= size_treshold }
        
        
        # Check if rootvg is mirrored
        rootvg_mirrored = False
        for x in rootvg_data[1:]:
            if x:
                lp_count = x.split()[2]
                pp_count = x.split()[3]
                # Compare value
                try:
                    if int(pp_count) == 2 * int(lp_count):
                        rootvg_mirrored = True
                except ValueError:
                        continue
                        
        # Print report
        with open( os.path.join(REPORT_PATH, f'{lpar_name}_report.txt'), 'w') as report_file:
            # Check VMRF_REF to detect outdated lpp
            for lpp_wild, lpp_vrmf in VRMF_REF.items():
                # Find lpp with VRMF below VRMF_REF value
                outdated_lpp = { x:y['VRMF'] for x,y in lpp_dict.items() if lpp_wild in x and version.parse(y['VRMF']) < version.parse(lpp_vrmf) }
            
                # Print only if outdated lpp found
                if outdated_lpp:
                    for lpp, lpp_vrmf in outdated_lpp.items():
                        report_file.write(f'\n{lpar_name} ==> \t {lpp} \t {lpp_vrmf} is outdated \n\n') 
                        
            # Check if httpd lpp is present
            if "httpd" in VRMF_REF.keys():
                report_file.write(f'\n{lpar_name} ==> \t a lpp httpd is present \n\n')
                
            # Checi if httpd rpm is present
            if "httpd" in rpm_data:
                report_file.write(f'\n{lpar_name} ==> \t a rpm httpd is present \n\n')
                                    
            # Print instfix if any
            if not any(' There is no efix data on this system.' in x for x in emgr_data):
                report_file.write(f'\n{lpar_name} ==> a iFix is installed \n\n')
                report_file.write('\n'.join(emgr_data) )
                
            # Print if rootvg is mirrored
            if rootvg_mirrored:
                report_file.write(f'\n{lpar_name} ==> rootvg is mirrored \n\n')
                
            # Print if yum check failed
            if not any('check all' in x for x in yum_data):
                report_file.write(f'\n{lpar_name} ==> yum checked failed => {yum_data} \n\n')
                
            # Check is there is place on rootvg
            if sz_dict:
                report_file.write(f'\n{lpar_name} ==> check space on the following mount point of rootvg  => \n {sz_dict} \n\n')
            
                
# Remove empty files within REPORT_PATH
for f in glob.glob( os.path.join(REPORT_PATH, '*.txt')):
    if os.stat(f).st_size == 0:
        os.remove(f) 
        
print(f'See result in {REPORT_PATH} if problem were detected !')
    
                
