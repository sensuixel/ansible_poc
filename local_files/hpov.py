#!/usr/lpp/produit/ISV/bin/python
import argparse
from datetime import datetime
import urllib.request
import ssl
from HPOV_Context import *

# Constant
USER_AD="pichard"
ROOTPATH = "/usr/lpp/ag2r/hpov"
CAFILE = ROOTPATH + "/cert/ca-bundle.crt"

# Parse cli argument
parser = argparse.ArgumentParser()

# Add argument
parser.add_argument("-action", "--action", help="on activate supervision hpov / off desactivate hpov", required=True)
parser.add_argument("-text", "--text", help="Justification", required=True)
parser.add_argument("-userid", "--userid", help="user_id", required=True)


# Parse argument
args = parser.parse_args()
lpar = getLparName()
status = args.action
label = args.text
userid = args.userid

# All parm to lower case
lpar = lpar.lower()
status = status.lower()
label = label.lower()

# Control argument
hpovStatut, hpovText = getStatut(status)
if not isServerValid(lpar):
    print("Invalid server")
    print("Valid Server are : \n{}".format("\n- ".join(lparList)))
    exit(4)
	
# Format URL
url = 'https://telerupteur/api/supervision.php?serveur={}&statut={}&user={}&justification={}'.format(lpar, hpovStatut, USER_AD, label)

# Create ssl context
ctx = ssl.create_default_context()
ctx.check_hostname = True
ctx.verify_mode = ssl.CERT_REQUIRED
ctx.load_verify_locations(cafile = CAFILE)

# Submit and get output
req = urllib.request.urlopen(url, context=ctx)
charset=req.info().get_content_charset()
res = req.read().decode(charset)

# Control result 
msg = checkUrlResult(res, hpovText)
sendWTO(msg)

# Log action
now = datetime.now()
print('{} => {} reason = {} at {} by {}'.format(lpar, hpovText, label, now, userid))
