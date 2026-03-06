#!/bin/bash
# =============================================================================
# OPM MEG Software Setup Script
# =============================================================================
# This script installs the required software for the OPM MEG module of NEU502B.
# Run with: bash setup_opm.sh
#
# WINDOWS USERS: This script requires WSL (Windows Subsystem for Linux).
# If you don't have WSL installed, open PowerShell as Administrator and run:
#     wsl --install -d Ubuntu-22.04
# Then restart your computer, open the Ubuntu 22.04 terminal, and run:
#     bash setup_opm.sh
# NOTE: Ubuntu 22.04 is required for FreeSurfer compatibility. If you already
# have a newer Ubuntu in WSL, you can remove it with:
#     wsl --unregister Ubuntu
# Then install 22.04 using the command above.
# =============================================================================

set -e  # Exit on any error

# --- OS Detection ---
OS_TYPE="$(uname -s)"
ARCH_TYPE="$(uname -m)"
IS_WSL=false

# Check for WSL (Windows Subsystem for Linux)
if [ "$OS_TYPE" = "Linux" ] && grep -qi "microsoft\|WSL" /proc/version 2>/dev/null; then
    IS_WSL=true
fi

# Block Git Bash / MSYS / Cygwin — require WSL instead
case "$OS_TYPE" in
    MINGW*|MSYS*|CYGWIN*)
        echo "ERROR: This script does not support Git Bash, MSYS, or Cygwin."
        echo ""
        echo "Windows users must run this script inside WSL (Windows Subsystem for Linux)."
        echo "To install WSL, open PowerShell as Administrator and run:"
        echo ""
        echo "    wsl --install -d Ubuntu-22.04"
        echo ""
        echo "Then restart your computer, open the Ubuntu 22.04 terminal, and re-run this script."
        exit 1
        ;;
esac

# Helper function to open a URL in the default browser
open_url() {
    local url="$1"
    if [ "$IS_WSL" = true ]; then
        cmd.exe /c start "$url" 2>/dev/null || echo "Could not open browser. Please visit: $url"
    elif [ "$OS_TYPE" = "Darwin" ]; then
        open "$url"
    elif [ "$OS_TYPE" = "Linux" ]; then
        xdg-open "$url" 2>/dev/null || echo "Could not open browser. Please visit: $url"
    else
        echo "Please visit: $url"
    fi
}

echo "============================================="
echo "  OPM MEG Software Setup"
echo "============================================="
echo ""

if [ "$IS_WSL" = true ]; then
    echo "Detected: Windows (WSL)"
elif [ "$OS_TYPE" = "Darwin" ]; then
    echo "Detected: macOS ($ARCH_TYPE)"
elif [ "$OS_TYPE" = "Linux" ]; then
    echo "Detected: Linux ($ARCH_TYPE)"
fi
echo ""

# --- Step 1: Install uv (Python package manager) ---
echo "--- Step 1: Install uv ---"
echo ""

if command -v uv &> /dev/null; then
    echo "✓ uv is already installed: $(uv --version)"
else
    echo "uv is not installed. Installing now..."
    echo ""

    if command -v curl &> /dev/null; then
        echo "Using curl to install uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    elif command -v wget &> /dev/null; then
        echo "Using wget to install uv..."
        wget -qO- https://astral.sh/uv/install.sh | sh
    else
        echo "ERROR: Neither curl nor wget is available."
        echo "Please install curl or wget first, then re-run this script."
        exit 1
    fi

    # The uv installer adds to PATH via shell config, but that won't take
    # effect in this running shell. Source it or add manually.
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi

# Verify uv is working
echo ""
if uv --help &> /dev/null; then
    echo "✓ uv is available and working ($(uv --version))"
else
    echo "ERROR: uv was installed but could not be found on PATH."
    echo "Try opening a new terminal and re-running this script."
    exit 1
fi
echo ""

# --- mne-opm (dev branch) by Harrison Ritz ---
echo "--- Step 2: Install mne-opm (dev branch) ---"
echo ""

# Prompt for install location
DEFAULT_DIR="$HOME/software"
read -rp "Install mne-opm to $DEFAULT_DIR? [Y/n]: " USE_DEFAULT_DIR
if [[ "$USE_DEFAULT_DIR" =~ ^[Nn]$ ]]; then
    read -rp "Enter the install directory: " INSTALL_DIR
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
else
    INSTALL_DIR="$DEFAULT_DIR"
fi

# Create the directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Creating directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi

# Clone and install mne-opm
cd "$INSTALL_DIR"

if [ -d "$INSTALL_DIR/mne-opm" ]; then
    echo ""
    echo "mne-opm directory already exists at $INSTALL_DIR/mne-opm"
    read -rp "Would you like to remove it and re-clone? [y/N]: " RECLONE
    if [[ "$RECLONE" =~ ^[Yy]$ ]]; then
        echo "Removing existing mne-opm directory..."
        rm -rf "$INSTALL_DIR/mne-opm"
    else
        echo "Skipping clone. Attempting install from existing directory..."
    fi
fi

if [ ! -d "$INSTALL_DIR/mne-opm" ]; then
    echo ""
    echo "Cloning mne-opm (dev branch) from GitHub..."
    git clone -b my-working-branch https://github.com/mrribbits/mne-opm.git
fi

echo ""
echo "✓ mne-opm (dev branch) cloned successfully!"
echo "  Location: $INSTALL_DIR/mne-opm"
echo ""

# --- Step 3: Run uv sync ---
echo "--- Step 3: Sync dependencies with uv ---"
echo ""
echo "This creates a virtual environment and builds Harrison's forks of:"
echo "  - mne-bids-pipeline"
echo "  - mne-bids"
echo "  - osl-ephys"
echo "  - mne"
echo ""

cd "$INSTALL_DIR/mne-opm"
echo "Running uv sync in $INSTALL_DIR/mne-opm..."
uv sync

echo ""
echo "Installing mne-opm in editable mode..."
uv pip install -e "$INSTALL_DIR/mne-opm"

echo ""
echo "Patching mne-bids-pipeline (eog_scores ndim fix)..."
ICA_FILE=$(find "$INSTALL_DIR/mne-opm/.venv" -path "*/preprocessing/_06a2_find_ica_artifacts.py" 2>/dev/null)
if [ -n "$ICA_FILE" ]; then
    if grep -q "eog_scores = np.array(eog_scores)" "$ICA_FILE"; then
        echo "✓ Patch already applied."
    else
        python3 -c "
p = '$ICA_FILE'
with open(p) as f: txt = f.read()
txt = txt.replace(
    '    if eog_scores.ndim > 1:',
    '    eog_scores = np.array(eog_scores)  # ensure ndarray, not list\n    if eog_scores.ndim > 1:',
    1)
with open(p, 'w') as f: f.write(txt)
"
        echo "✓ Patch applied."
    fi
else
    echo "⚠ Could not find _06a2_find_ica_artifacts.py — patch skipped."
fi

echo ""
echo "✓ uv sync complete!"
echo ""

# --- Step 4: Verify installation ---
echo "--- Step 4: Verify installation ---"
echo ""
echo "Running mne-opm.sh to check that everything is set up correctly..."
echo "Expecting a 'pipeline not set' error with usage instructions."
echo ""

OUTPUT=$(bash "$INSTALL_DIR/mne-opm/mne-opm.sh" 2>&1) || true
echo "$OUTPUT"
echo ""

if echo "$OUTPUT" | grep -qi "pipeline not set\|usage"; then
    echo "✓ Installation verified! The expected error and usage instructions appeared."
else
    echo "WARNING: Did not see the expected 'pipeline not set' message."
    echo "Please review the output above and check your installation."
fi
echo ""


# --- Step 5: FreeSurfer ---
echo "--- Step 5: Set up FreeSurfer ---"
echo ""

# Search common install locations for FreeSurfer
FOUND_FS=""
FS_SEARCH_DIRS=("/Applications/freesurfer" "$HOME/Applications/freesurfer" "/usr/local/freesurfer" "$HOME/freesurfer")

# Add Windows paths for WSL users
if [ "$IS_WSL" = true ]; then
    FS_SEARCH_DIRS+=("/mnt/c/freesurfer" "/mnt/c/Program Files/freesurfer")
fi

for search_dir in "${FS_SEARCH_DIRS[@]}"; do
    if [ -d "$search_dir" ]; then
        # Look for version subdirectories or direct install
        if [ -f "$search_dir/SetUpFreeSurfer.sh" ]; then
            FOUND_FS="$search_dir"
            break
        fi
        # Check for versioned subdirectories (e.g., 8.1.0)
        for version_dir in "$search_dir"/*/; do
            if [ -f "${version_dir}SetUpFreeSurfer.sh" ]; then
                FOUND_FS="${version_dir%/}"
                break 2
            fi
        done
    fi
done

if [ -n "$FOUND_FS" ]; then
    echo "✓ FreeSurfer found at: $FOUND_FS"
    read -rp "Use this path for FREESURFER_HOME? [Y/n]: " USE_FOUND
    if [[ ! "$USE_FOUND" =~ ^[Nn]$ ]]; then
        FREESURFER_HOME="$FOUND_FS"
    fi
fi

if [ -z "$FREESURFER_HOME" ]; then
    echo "FreeSurfer was not detected on this system."
    echo ""
    echo "FreeSurfer 8.1.0 is required. Let's get it installed."
    echo ""

    # Determine the correct download package
    DOWNLOAD_URL="https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/8.1.0/"
    PACKAGE_NAME=""

    case "$OS_TYPE" in
        Darwin)
            if [ "$ARCH_TYPE" = "arm64" ]; then
                PACKAGE_NAME="freesurfer-macOS-darwin_arm64-8.1.0.pkg"
                echo "Detected: macOS (Apple Silicon)"
            else
                PACKAGE_NAME="freesurfer-macOS-darwin_x86_64-8.1.0.pkg"
                echo "Detected: macOS (Intel)"
            fi
            ;;
        Linux)
            PACKAGE_NAME="freesurfer_ubuntu22-8.1.0_amd64.deb"
            if [ "$IS_WSL" = true ]; then
                echo "Detected: Windows (WSL) — using Linux package"
            else
                echo "Detected: Linux (x86_64)"
            fi
            echo "  Note: If you're not on Ubuntu 22, check the download page"
            echo "  for the correct package for your distro."
            echo ""
            echo "  After downloading, install with:"
            echo "    sudo apt install ./freesurfer_ubuntu22-8.1.0_amd64.deb"
            ;;
        *)
            echo "Detected: $OS_TYPE (unsupported for auto-detection)"
            ;;
    esac

    echo ""

    if [ -n "$PACKAGE_NAME" ]; then
        echo "Recommended package: $PACKAGE_NAME"
        echo "Download URL: ${DOWNLOAD_URL}${PACKAGE_NAME}"
        echo ""
        read -rp "Would you like to open the download page in your browser? [Y/n]: " OPEN_BROWSER
        if [[ ! "$OPEN_BROWSER" =~ ^[Nn]$ ]]; then
            open_url "${DOWNLOAD_URL}"
        fi
    else
        echo "Please download FreeSurfer 8.1.0 from:"
        echo "  ${DOWNLOAD_URL}"
    fi

    echo ""
    echo "============================================="
    echo "  Install FreeSurfer, then return here."
    echo "  Press ENTER when ready to continue..."
    echo "============================================="
    read -r

    # Prompt for the FreeSurfer path
    while true; do
        read -rp "Enter the path to your FreeSurfer installation (example: /Applications/freesurfer/8.1.0): " FREESURFER_HOME
        FREESURFER_HOME="${FREESURFER_HOME/#\~/$HOME}"

        if [ -f "$FREESURFER_HOME/SetUpFreeSurfer.sh" ]; then
            echo "✓ FreeSurfer verified at: $FREESURFER_HOME"
            break
        else
            echo "ERROR: Could not find SetUpFreeSurfer.sh in $FREESURFER_HOME"
            echo "  Please try again."
            echo ""
        fi
    done
fi

echo ""
echo "FREESURFER_HOME=$FREESURFER_HOME"
echo ""

# --- Step 6: Set up project paths for the sample project ---
echo "--- Step 6: Set up project paths for the sample project ---"
echo ""
echo "You need to provide a root projects folder (OPM_DIR) for all opm projects."
echo ""

DEFAULT_ROOT="$HOME/opm-projects"
read -rp "Use $DEFAULT_ROOT? [Y/n]: " USE_DEFAULT
if [[ "$USE_DEFAULT" =~ ^[Nn]$ ]]; then
    read -rp "Enter the root projects folder: " OPM_DIR
    OPM_DIR="${OPM_DIR/#\~/$HOME}"
else
    OPM_DIR="$DEFAULT_ROOT"
fi

if [ ! -d "$OPM_DIR" ]; then
    echo "Creating OPM_DIR: $OPM_DIR"
    mkdir -p "$OPM_DIR"
else
    echo "✓ OPM_DIR already exists: $OPM_DIR"
fi
echo ""

# Project variables
PIPELINE="preproc"
EXPERIMENT="oddball"
ANALYSIS="analysis1"
SUBJECT="001"
SESSION="01"

# Project paths
MNE_OPM_DIR="$INSTALL_DIR/mne-opm"
ROOT_DIR="$OPM_DIR/$EXPERIMENT"
DATA_BASE="$ROOT_DIR/data"
BIDS_DIR="$DATA_BASE/$EXPERIMENT/bids"
CONFIG_BASE="$DATA_BASE/$EXPERIMENT/configs"
SUBJECTS_DIR="$BIDS_DIR/derivatives/freesurfer"

echo "Creating project directory structure in $ROOT_DIR..."
echo ""

# Tree 1: raw/
mkdir -p "$DATA_BASE/$EXPERIMENT/raw/sub_${SUBJECT}/dicom"
mkdir -p "$DATA_BASE/$EXPERIMENT/raw/sub_${SUBJECT}/anat"
mkdir -p "$DATA_BASE/$EXPERIMENT/raw/sub_${SUBJECT}/session1_task"
mkdir -p "$DATA_BASE/$EXPERIMENT/raw/sub_${SUBJECT}/session1_noise"
mkdir -p "$DATA_BASE/$EXPERIMENT/raw/sub_${SUBJECT}/metadata"
mkdir -p "$DATA_BASE/$EXPERIMENT/raw/sub_${SUBJECT}/eyetracking"

# Tree 2: bids/
mkdir -p "$BIDS_DIR/sub-${SUBJECT}/ses-${SESSION}/meg"
mkdir -p "$BIDS_DIR/sub-${SUBJECT}/ses-${SESSION}/anat"
mkdir -p "$BIDS_DIR/derivatives/freesurfer/subjects"
mkdir -p "$BIDS_DIR/derivatives/${ANALYSIS}"

# Tree 3: configs/
mkdir -p "$CONFIG_BASE/bids"

# Analysis directory
mkdir -p "$ROOT_DIR/analysis"

echo "✓ Directory structure created!"
echo ""
echo "Directory layout:"
echo ""
echo "  $ROOT_DIR/"
echo "  ├── analysis/"
echo "  └── data/"
echo "      └── $EXPERIMENT/"
echo "          ├── raw/"
echo "          │   └── sub_${SUBJECT}/"
echo "          │       ├── dicom/"
echo "          │       ├── anat/"
echo "          │       ├── session1_task/"
echo "          │       ├── session1_noise/"
echo "          │       ├── metadata/"
echo "          │       └── eyetracking/"
echo "          ├── bids/"
echo "          │   ├── sub-${SUBJECT}/"
echo "          │   │   └── ses-${SESSION}/"
echo "          │   │       ├── meg/"
echo "          │   │       └── anat/"
echo "          │   └── derivatives/"
echo "          │       ├── freesurfer/"
echo "          │       │   └── subjects/"
echo "          │       └── ${ANALYSIS}/"
echo "          └── configs/"
echo "              └── bids/"
echo ""
echo "Project variables:"
echo "  PIPELINE     = $PIPELINE"
echo "  EXPERIMENT   = $EXPERIMENT"
echo "  ANALYSIS     = $ANALYSIS"
echo "  SUBJECT      = $SUBJECT"
echo "  SESSION      = $SESSION"
echo ""
echo "Project paths:"
echo "  OPM_DIR      = $OPM_DIR"
echo "  MNE_OPM_DIR  = $MNE_OPM_DIR"
echo "  ROOT_DIR     = $ROOT_DIR"
echo "  DATA_BASE    = $DATA_BASE"
echo "  BIDS_DIR     = $BIDS_DIR"
echo "  CONFIG_BASE  = $CONFIG_BASE"
echo "  SUBJECTS_DIR = $SUBJECTS_DIR"
echo ""

# --- Step 7: Download sample data ---
echo "--- Step 7: Download sample data ---"
echo ""
echo "We will now download the sample dataset. You may not need everything"
echo "offered, depending where you'd like to start in the pipeline."
echo "Please ask if you're not sure what you need."
echo ""

# Helper function: download a file from Dropbox using curl or wget
download_file() {
    local url="$1"
    local dest="$2"
    local dl_url="${url/dl=0/dl=1}"

    if command -v curl &> /dev/null; then
        curl -L -o "$dest" "$dl_url"
    else
        wget -q -O "$dest" "$dl_url"
    fi
}

# 1-5: Optional raw data (students do not need these)
echo "============================================="
echo "  Students do not need to download anything"
echo "  from this first section (items 1-5)."
echo "============================================="
echo ""

# 1. MRI DICOM data
read -rp "1. Download MRI dicom data to $ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/dicom? Students do not need this [y/N]: " DL_DICOM
if [[ "$DL_DICOM" =~ ^[Yy]$ ]]; then
    echo "   Downloading MRI dicom data (zip)..."
    DEST_DIR="$ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/dicom"
    if download_file "https://www.dropbox.com/scl/fi/u30g3672lcgt7xxlddd2y/Archive.zip?rlkey=kqq7j6dhxngfxv9l0pce8lob6&dl=0" "$DEST_DIR/Archive.zip"; then
        echo "   Extracting..."
        cd "$DEST_DIR"
        unzip -qo Archive.zip || true
        rm -f Archive.zip
        rm -rf __MACOSX
        echo "   ✓ MRI dicom data downloaded and extracted."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/u30g3672lcgt7xxlddd2y/Archive.zip?rlkey=kqq7j6dhxngfxv9l0pce8lob6&dl=0"
        echo "   Then unzip and place the DICOM files in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# 2. Eyetracking data
read -rp "2. Download the raw eyetracking data to $ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/eyetracking? Students do not need this [y/N]: " DL_EYE
if [[ "$DL_EYE" =~ ^[Yy]$ ]]; then
    echo "   Downloading eyetracking data..."
    DEST_DIR="$ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/eyetracking"
    if download_file "https://www.dropbox.com/scl/fi/k4ow3a3xgh40ofnn5ay8e/recording.asc?rlkey=f19uogxfdggpuwevjdl7yl39l&dl=0" "$DEST_DIR/recording.asc"; then
        echo "   ✓ Eyetracking data downloaded."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/k4ow3a3xgh40ofnn5ay8e/recording.asc?rlkey=f19uogxfdggpuwevjdl7yl39l&dl=0"
        echo "   Then place the file in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# 3. MEG empty room noise recording
read -rp "3. Download the raw MEG empty room noise recording to $ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/session1_noise? Students do not need this [y/N]: " DL_NOISE
if [[ "$DL_NOISE" =~ ^[Yy]$ ]]; then
    echo "   Downloading MEG empty room noise recording..."
    DEST_DIR="$ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/session1_noise"
    if download_file "https://www.dropbox.com/scl/fi/1wlysh1wh6jay78twl05v/20260303_134623_meg.fif?rlkey=jlkgjcyekfwf2bf5mu8ds918a&dl=0" "$DEST_DIR/20260303_134623_meg.fif"; then
        echo "   ✓ MEG noise recording downloaded."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/1wlysh1wh6jay78twl05v/20260303_134623_meg.fif?rlkey=jlkgjcyekfwf2bf5mu8ds918a&dl=0"
        echo "   Then place the file in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# 4. MEG subject recording
read -rp "4. Download the raw MEG subject recording to $ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/session1_task? Students do not need this [y/N]: " DL_TASK
if [[ "$DL_TASK" =~ ^[Yy]$ ]]; then
    echo "   Downloading MEG subject recording..."
    DEST_DIR="$ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/session1_task"
    if download_file "https://www.dropbox.com/scl/fi/0heme6p98cf8q5wsm4gvs/20260303_143625_meg.fif?rlkey=rworio33eala39umni5pxkuv1&dl=0" "$DEST_DIR/20260303_143625_meg.fif"; then
        echo "   ✓ MEG subject recording downloaded."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/0heme6p98cf8q5wsm4gvs/20260303_143625_meg.fif?rlkey=rworio33eala39umni5pxkuv1&dl=0"
        echo "   Then place the file in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# 5. MRI NIfTI files (from "nifti" pipeline)
read -rp "5. Download MRI NIfTI files to $DATA_BASE/$EXPERIMENT/raw/sub_${SUBJECT}/anat? Students do not need this [y/N]: " DL_NIFTI
if [[ "$DL_NIFTI" =~ ^[Yy]$ ]]; then
    echo "   Downloading MRI NIfTI files (zip)..."
    DEST_DIR="$DATA_BASE/$EXPERIMENT/raw/sub_${SUBJECT}/anat"
    if download_file "https://www.dropbox.com/scl/fo/0emvfylc2eyp5fe5xgp5p/AKZ2j923phpNofnAngp4q3s?rlkey=u0j8yylj4tyg98jh5hzymdt2v&dl=0" "$DEST_DIR/anat_download.zip"; then
        echo "   Extracting..."
        cd "$DEST_DIR"
        unzip -qo anat_download.zip || true
        rm -f anat_download.zip
        rm -rf __MACOSX
        echo "   ✓ MRI NIfTI files downloaded and extracted."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fo/0emvfylc2eyp5fe5xgp5p/AKZ2j923phpNofnAngp4q3s?rlkey=u0j8yylj4tyg98jh5hzymdt2v&dl=0"
        echo "   Then unzip and place the files in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# 6-10: Required data (students must download these)
echo "============================================="
echo "  Students must download everything in this"
echo "  next section (items 6-10)."
echo "============================================="
echo ""

# 6. Psychopy event log
read -rp "6. Download Psychopy event log to $ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/metadata? [Y/n]: " DL_PSYCH
if [[ ! "$DL_PSYCH" =~ ^[Nn]$ ]]; then
    echo "   Downloading Psychopy event log..."
    DEST_DIR="$ROOT_DIR/data/$EXPERIMENT/raw/sub_${SUBJECT}/metadata"
    if download_file "https://www.dropbox.com/scl/fi/c60r0237kt57i66ssduki/sub-001_events.csv?rlkey=tlckvan89bptp8vx8e0uwkn2r&dl=0" "$DEST_DIR/sub-001_events.csv"; then
        echo "   ✓ Psychopy event log downloaded."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/c60r0237kt57i66ssduki/sub-001_events.csv?rlkey=tlckvan89bptp8vx8e0uwkn2r&dl=0"
        echo "   Then place the file in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# 7. Main config file
read -rp "7. Download main config file to $CONFIG_BASE? [Y/n]: " DL_CONFIG
if [[ ! "$DL_CONFIG" =~ ^[Nn]$ ]]; then
    echo "   Downloading main config file..."
    DEST_DIR="$CONFIG_BASE"
    if download_file "https://www.dropbox.com/scl/fi/8cejmh6y2g4z975ps5c9f/config-analysis1.py?rlkey=741udeakll3559lug05glju9w&dl=0" "$DEST_DIR/config-analysis1.py"; then
        echo "   ✓ Main config file downloaded."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/8cejmh6y2g4z975ps5c9f/config-analysis1.py?rlkey=741udeakll3559lug05glju9w&dl=0"
        echo "   Then place the file in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# 8. Subject-specific bids config file
read -rp "8. Download subject-specific bids config file to $CONFIG_BASE/bids? [Y/n]: " DL_BIDS_CONFIG
if [[ ! "$DL_BIDS_CONFIG" =~ ^[Nn]$ ]]; then
    echo "   Downloading subject-specific bids config file..."
    DEST_DIR="$CONFIG_BASE/bids"
    if download_file "https://www.dropbox.com/scl/fi/4sy9rt83cbna3kx4jrhpj/sub-001_config-bids.py?rlkey=eofr513kzhfj436q4r9dvetdj&dl=0" "$DEST_DIR/sub-001_config-bids.py"; then
        echo "   ✓ Subject-specific bids config file downloaded."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/4sy9rt83cbna3kx4jrhpj/sub-001_config-bids.py?rlkey=eofr513kzhfj436q4r9dvetdj&dl=0"
        echo "   Then place the file in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# 9. BIDS data (from "bids" pipeline)
read -rp "9. Download BIDS data to $BIDS_DIR? [Y/n]: " DL_BIDS
if [[ ! "$DL_BIDS" =~ ^[Nn]$ ]]; then
    echo "   Downloading BIDS data (zip)..."
    DEST_DIR="$BIDS_DIR"
    if download_file "https://www.dropbox.com/scl/fo/rza1hrvnkcxdygamb33g7/AJ_jagXOp3HDg3lG-6R3ua4?rlkey=35wnypz77ljm1051e0zw65t0e&dl=0" "$DEST_DIR/bids_download.zip"; then
        echo "   Extracting..."
        cd "$DEST_DIR"
        unzip -qo bids_download.zip -d "$DEST_DIR/sub-${SUBJECT}" || true
        rm -f bids_download.zip
        rm -rf __MACOSX
        echo "   ✓ BIDS data downloaded and extracted."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fo/rza1hrvnkcxdygamb33g7/AJ_jagXOp3HDg3lG-6R3ua4?rlkey=35wnypz77ljm1051e0zw65t0e&dl=0"
        echo "   Then unzip and place the files in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# 10. FreeSurfer outputs (from "freesurfer" pipeline)
read -rp "10. Download FreeSurfer outputs to $SUBJECTS_DIR? [Y/n]: " DL_FS
if [[ ! "$DL_FS" =~ ^[Nn]$ ]]; then
    echo "   Downloading FreeSurfer outputs (zip)..."
    DEST_DIR="$SUBJECTS_DIR"
    if download_file "https://www.dropbox.com/scl/fo/2tfd5rz7r647gp7pl61xa/AIOBe29YJr2l-itDu_T8TiI?rlkey=uykmi2656kzn62lyri35y1qg7&dl=0" "$DEST_DIR/freesurfer_download.zip"; then
        echo "   Extracting..."
        cd "$DEST_DIR"
        unzip -qo freesurfer_download.zip || true
        rm -f freesurfer_download.zip
        rm -rf __MACOSX
        echo "   ✓ FreeSurfer outputs downloaded and extracted."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fo/2tfd5rz7r647gp7pl61xa/AIOBe29YJr2l-itDu_T8TiI?rlkey=uykmi2656kzn62lyri35y1qg7&dl=0"
        echo "   Then unzip and place the files in:"
        echo "     $DEST_DIR/"
    fi
fi
echo ""

# --- Step 8: Download and configure runlocal-mne-opm.sh ---
echo "--- Step 8: Download runlocal-mne-opm.sh and update its paths for you ---"
echo ""

read -rp "Download runlocal-mne-opm.sh to $ROOT_DIR/analysis? [Y/n]: " DL_RUNLOCAL
if [[ ! "$DL_RUNLOCAL" =~ ^[Nn]$ ]]; then
    echo "   Downloading runlocal-mne-opm.sh..."
    DEST_DIR="$ROOT_DIR/analysis"
    if download_file "https://www.dropbox.com/scl/fi/gt125gd2o7b4mr7wea6fc/runlocal-mne-opm.sh?rlkey=mp0dbfh4mlejkas1hkrexp70u&dl=0" "$DEST_DIR/runlocal-mne-opm.sh"; then
        chmod +x "$DEST_DIR/runlocal-mne-opm.sh"
        echo "   ✓ runlocal-mne-opm.sh downloaded."
        echo ""

        echo "   Updating parameters and paths in runlocal-mne-opm.sh..."
        RUN_SCRIPT="$DEST_DIR/runlocal-mne-opm.sh"

        sed -i.bak \
            -e "s|^PIPELINE=.*|PIPELINE=\"$PIPELINE\"|" \
            -e "s|^EXPERIMENT=.*|EXPERIMENT=\"$EXPERIMENT\"|" \
            -e "s|^ANALYSIS=.*|ANALYSIS=\"$ANALYSIS\"|" \
            -e "s|^SESSION=.*|SESSION=\"$SESSION\"|" \
            -e "s|^SUBJECT=.*|SUBJECT=\"$SUBJECT\"|" \
            -e "s|^FREESURFER_HOME=.*|FREESURFER_HOME=\"$FREESURFER_HOME\"|" \
            -e "s|^ROOT_DIR=.*|ROOT_DIR=\"$ROOT_DIR\"|" \
            -e "s|^CONFIG_BASE=.*|CONFIG_BASE=\"$CONFIG_BASE\"|" \
            -e "s|^DATA_BASE=.*|DATA_BASE=\"$DATA_BASE\"|" \
            -e "s|^SUBJECTS_DIR=.*|SUBJECTS_DIR=\"$SUBJECTS_DIR\"|" \
            -e "s|^MNE_OPM_DIR=.*|MNE_OPM_DIR=\"$MNE_OPM_DIR\"|" \
            "$RUN_SCRIPT"

        rm -f "${RUN_SCRIPT}.bak"

        echo "   ✓ runlocal-mne-opm.sh configured with the sample project settings."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/gt125gd2o7b4mr7wea6fc/runlocal-mne-opm.sh?rlkey=mp0dbfh4mlejkas1hkrexp70u&dl=0"
        echo "   Then place the file in:"
        echo "     $ROOT_DIR/analysis/"
        echo "   NOTE: You will need to manually update the paths in the file."
    fi
else
    echo "   Skipping runlocal-mne-opm.sh download."
fi
echo ""

echo "============================================="
echo "  Setup complete!"
echo "============================================="
echo ""

echo "---------------------------------------------"
echo "  TIP: To run Python scripts in the mne-opm"
echo "  environment, use:"
echo ""
echo "    uv run --project $MNE_OPM_DIR python <script>.py"
echo ""
echo "---------------------------------------------"
echo ""

echo "How to use mne-opm:"
echo ""
echo "  1. Edit the config file as needed:"
echo "     $CONFIG_BASE/config-analysis1.py"
echo ""
echo "  2. Choose a PIPELINE in runlocal-mne-opm.sh (line 7) and run it:"
echo "     $ROOT_DIR/analysis/runlocal-mne-opm.sh"
echo ""
echo "     Valid PIPELINE options:"
echo "     nifti | bids | freesurfer | coreg | preproc | sensor | source | all | func | anat"
echo ""
echo "     Each pipeline has an associated run_*.sh script."
echo ""

echo "For more details, see Harrison Ritz's documentation."
read -rp "Would you like to open the mne-opm GitHub page? [Y/n]: " OPEN_GITHUB
if [[ ! "$OPEN_GITHUB" =~ ^[Nn]$ ]]; then
    open_url "https://github.com/harrisonritz/mne-opm"
fi
