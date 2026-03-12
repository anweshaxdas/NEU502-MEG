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

# --- mne-opm (Mark's fork of the dev branch) ---
echo "--- Step 2: Install mne-opm (Mark's fork of the dev branch) ---"
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
    echo "Cloning mne-opm (Mark's fork of the dev branch) from GitHub..."
    git clone -b my-working-branch https://github.com/mrribbits/mne-opm.git
fi

echo ""
echo "✓ mne-opm (Mark's fork of the dev branch) cloned successfully!"
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
PIPELINE="coreg"
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

# Tree 3: configs/
mkdir -p "$CONFIG_BASE/$EXPERIMENT/bids"

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
echo "          │       └── freesurfer/"
echo "          │           └── subjects/"
echo "          └── configs/"
echo "              └── $EXPERIMENT/"
echo "                  └── bids/"
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
echo "We will now download the sample dataset. You'll have the option of"
echo "downloading just the raw data, or downloading data that's been processed"
echo "to a certain point. Students should choose the latter."
echo ""

# Helper function: download a file from Dropbox using curl or wget
download_file() {
    local url="$1"
    local dest="$2"
    local dl_url="${url/dl=0/dl=1}"

    if command -v curl &> /dev/null; then
        curl -L -H "Cache-Control: no-cache" -o "$dest" "$dl_url"
    else
        wget --no-cache -q -O "$dest" "$dl_url"
    fi
}

# 1. Raw sample dataset (default No)
echo "============================================="
echo "  Option 1: Full raw dataset."
echo "  Requires ALL processing pipelines (nifti,"
echo "  bids, freesurfer, coreg, etc)."
echo "  Students do not need this."
echo "============================================="
echo ""
read -rp "1. Download the raw sample dataset? [y/N]: " DL_RAW
if [[ "$DL_RAW" =~ ^[Yy]$ ]]; then
    echo "   Downloading raw sample dataset (this may take a while)..."
    TMP_DIR=$(mktemp -d)
    if download_file "https://www.dropbox.com/scl/fi/kap08gztdx1wo3x16hj67/MEG-sample-data-raw.zip?rlkey=9zuow728782kb9gbug0515771&st=g2wbnzcy&dl=0" "$TMP_DIR/MEG-sample-data-raw.zip"; then
        echo "   Extracting..."
        unzip -qo "$TMP_DIR/MEG-sample-data-raw.zip" -d "$TMP_DIR" || true
        echo "   Merging into project directory..."
        rsync -a "$TMP_DIR/MEG-sample-data-raw/oddball/" "$ROOT_DIR/"
        rm -rf "$TMP_DIR"
        echo "   ✓ Raw sample dataset downloaded and extracted."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/kap08gztdx1wo3x16hj67/MEG-sample-data-raw.zip?rlkey=9zuow728782kb9gbug0515771&st=g2wbnzcy&dl=0"
        echo "   Then unzip and copy the contents of MEG-sample-data-raw/oddball/ into:"
        echo "     $ROOT_DIR/"
        rm -rf "$TMP_DIR"
    fi
fi
echo ""

# 2. Processed dataset for students (default Yes)
echo "============================================="
echo "  Option 2: Mostly processed dataset."
echo "  Data is ready for the coreg pipeline"
echo "  going forward. Students should choose this."
echo "============================================="
echo ""
read -rp "2. Download the processed sample dataset? [Y/n]: " DL_STUDENT
if [[ ! "$DL_STUDENT" =~ ^[Nn]$ ]]; then
    echo "   Downloading processed sample dataset (this may take a while)..."
    TMP_DIR=$(mktemp -d)
    if download_file "https://www.dropbox.com/scl/fi/puuz2s3bu2q2d4b6mej2l/MEG-for-students.zip?rlkey=z3gdunbuewna5d1u2w9ujb7zw&st=tobsoo7j&dl=0" "$TMP_DIR/MEG-for-students.zip"; then
        echo "   Extracting..."
        unzip -qo "$TMP_DIR/MEG-for-students.zip" -d "$TMP_DIR" || true
        echo "   Merging into project directory..."
        rsync -a --ignore-existing "$TMP_DIR/oddball/" "$ROOT_DIR/"
        rm -rf "$TMP_DIR"
        echo "   ✓ Processed sample dataset downloaded and extracted."
    else
        echo ""
        echo "   ⚠ Download failed. Please download manually from your browser:"
        echo "     https://www.dropbox.com/scl/fi/puuz2s3bu2q2d4b6mej2l/MEG-for-students.zip?rlkey=z3gdunbuewna5d1u2w9ujb7zw&st=tobsoo7j&dl=0"
        echo "   Then unzip and copy the contents of oddball/ into:"
        echo "     $ROOT_DIR/"
        rm -rf "$TMP_DIR"
    fi
fi
echo ""

# 3. Scripts and config files
echo "============================================="
echo "  Download scripts and configuration files."
echo "  Everyone should download these."
echo "============================================="
echo ""
GITHUB_RAW="https://raw.githubusercontent.com/mrribbits/NEU502-2026/main"

read -rp "3. Download scripts and config files? [Y/n]: " DL_SCRIPTS
if [[ ! "$DL_SCRIPTS" =~ ^[Nn]$ ]]; then

    # --- Analysis scripts ---
    DEST_DIR="$ROOT_DIR/analysis"
    mkdir -p "$DEST_DIR"

    echo "   Downloading runlocal-mne-opm.sh..."
    if curl -LsSf "$GITHUB_RAW/analysis/runlocal-mne-opm.sh" -o "$DEST_DIR/runlocal-mne-opm.sh"; then
        chmod +x "$DEST_DIR/runlocal-mne-opm.sh"
        echo "   ✓ runlocal-mne-opm.sh downloaded."
    else
        echo "   ⚠ Failed. Download manually from: $GITHUB_RAW/analysis/runlocal-mne-opm.sh"
    fi

    echo "   Downloading check-meg-and-eyedata-annotations.py..."
    if curl -LsSf "$GITHUB_RAW/analysis/check-meg-and-eyedata-annotations.py" -o "$DEST_DIR/check-meg-and-eyedata-annotations.py"; then
        echo "   ✓ check-meg-and-eyedata-annotations.py downloaded."
    else
        echo "   ⚠ Failed. Download manually from: $GITHUB_RAW/analysis/check-meg-and-eyedata-annotations.py"
    fi
    echo ""

    # --- Config files ---
    DEST_DIR="$CONFIG_BASE/$EXPERIMENT"
    mkdir -p "$DEST_DIR/bids"

    echo "   Downloading config-analysis1.py..."
    if curl -LsSf "$GITHUB_RAW/configs/oddball/config-analysis1.py" -o "$DEST_DIR/config-analysis1.py"; then
        echo "   ✓ config-analysis1.py downloaded."
    else
        echo "   ⚠ Failed. Download manually from: $GITHUB_RAW/configs/oddball/config-analysis1.py"
    fi

    echo "   Downloading sub-001_config-bids.py..."
    if curl -LsSf "$GITHUB_RAW/configs/oddball/bids/sub-001_config-bids.py" -o "$DEST_DIR/bids/sub-001_config-bids.py"; then
        echo "   ✓ sub-001_config-bids.py downloaded."
    else
        echo "   ⚠ Failed. Download manually from: $GITHUB_RAW/configs/oddball/bids/sub-001_config-bids.py"
    fi
    echo ""

    # --- Update paths in runlocal-mne-opm.sh ---
    RUN_SCRIPT="$ROOT_DIR/analysis/runlocal-mne-opm.sh"
    if [ -f "$RUN_SCRIPT" ]; then
        echo "   Updating parameters and paths in runlocal-mne-opm.sh..."
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
    fi

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
echo "     $CONFIG_BASE/$EXPERIMENT/config-analysis1.py"
echo ""
echo "  2. Choose a PIPELINE in runlocal-mne-opm.sh (line 7) and run it:"
echo "     $ROOT_DIR/analysis/runlocal-mne-opm.sh"
echo ""
echo "     Valid PIPELINE options:"
echo "     nifti | bids | freesurfer | coreg | preproc | sensor | source | all | func | anat"
echo ""
echo "     Students should start at coreg."
echo ""
echo "     Each pipeline has an associated run_*.sh script you can delve into."
echo ""

echo "For more details, see Harrison Ritz's documentation."
read -rp "Would you like to open the mne-opm GitHub page? [Y/n]: " OPEN_GITHUB
if [[ ! "$OPEN_GITHUB" =~ ^[Nn]$ ]]; then
    open_url "https://github.com/harrisonritz/mne-opm"
fi
