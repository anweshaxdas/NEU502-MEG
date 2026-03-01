# BIDS formatting config (template)
# Copy to <CONFIG_DIR>/<EXPERIMENT>/bids/sub-<SUBJECT>_config-bids.py and edit.


import os

# Subject (int) and session label
ids = 1                 # subject numeric ID
session = '01'          # session label

# Task label for BIDS output (e.g., 'TSX')
task = 'oddball'

# Directories (read from environment)
raw_dir = os.getenv('RAW_DIR', '')
bids_dir = os.getenv('BIDS_DIR', '')

# Optional: trigger and response description mappings
rename_annot = True
trigger_desc = {
    # integer codes from Trigger Combined -> event labels. Encodes each trigger line as a power of 2 (bitwise)
    128: 'noise_onset',
}
response_desc = {
#    'Response/R1': 'button_1',
}

# Recording info
line_freq = 60.0
bads = []

# Optional cropping (seconds)
crop = 0