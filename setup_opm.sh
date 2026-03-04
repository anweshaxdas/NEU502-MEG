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
    git clone -b dev https://github.com/harrisonritz/mne-opm.git
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
BIDS_DIR="$DATA_BASE/bids"
CONFIG_BASE="$DATA_BASE/configs"
SUBJECTS_DIR="$BIDS_DIR/derivatives/freesurfer"

echo "Creating project directory structure in $ROOT_DIR..."
echo ""

# Tree 1: raw/
mkdir -p "$DATA_BASE/raw/sub_${SUBJECT}/dicom"
mkdir -p "$DATA_BASE/raw/sub_${SUBJECT}/anat"
mkdir -p "$DATA_BASE/raw/sub_${SUBJECT}/session1_task"
mkdir -p "$DATA_BASE/raw/sub_${SUBJECT}/session1_noise"
mkdir -p "$DATA_BASE/raw/sub_${SUBJECT}/metadata"
mkdir -p "$DATA_BASE/raw/sub_${SUBJECT}/eyetracking"

# Tree 2: bids/
mkdir -p "$BIDS_DIR/sub-${SUBJECT}/ses-${SESSION}/meg"
mkdir -p "$BIDS_DIR/sub-${SUBJECT}/ses-${SESSION}/anat"
mkdir -p "$BIDS_DIR/derivatives/freesurfer/subjects"
mkdir -p "$BIDS_DIR/derivatives/${ANALYSIS}"

# Tree 3: configs/
mkdir -p "$CONFIG_BASE/${EXPERIMENT}/bids"

# Analysis directory
mkdir -p "$ROOT_DIR/analysis"

echo "✓ Directory structure created!"
echo ""
echo "Directory layout:"
echo ""
echo "  $ROOT_DIR/"
echo "  ├── analysis/"
echo "  └── data/"
echo "      ├── raw/"
echo "      │   └── sub_${SUBJECT}/"
echo "      │       ├── dicom/"
echo "      │       ├── anat/"
echo "      │       ├── session1_task/"
echo "      │       ├── session1_noise/"
echo "      │       ├── metadata/"
echo "      │       └── eyetracking/"
echo "      ├── bids/"
echo "      │   ├── sub-${SUBJECT}/"
echo "      │   │   └── ses-${SESSION}/"
echo "      │   │       ├── meg/"
echo "      │   │       └── anat/"
echo "      │   └── derivatives/"
echo "      │       ├── freesurfer/"
echo "      │       │   └── subjects/"
echo "      │       └── ${ANALYSIS}/"
echo "      └── configs/"
echo "          └── ${EXPERIMENT}/"
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

# Install gdown for Google Drive downloads
echo "Installing gdown (Google Drive downloader)..."
uv tool install gdown
echo ""

# 1. MRI DICOM data
read -rp "1. Download MRI dicom data to $ROOT_DIR/data/raw/sub_${SUBJECT}/dicom? [Y/n]: " DL_DICOM
if [[ ! "$DL_DICOM" =~ ^[Nn]$ ]]; then
    echo "   Downloading MRI dicom data..."
    gdown --folder "https://drive.google.com/drive/folders/1Tfd28fL3vgi83OKZ9yH2HS3ZvYu8BWqy" -O "$ROOT_DIR/data/raw/sub_${SUBJECT}/dicom" --remaining-ok
    echo "   ✓ MRI dicom data downloaded."
fi
echo ""

# 2. Eyetracking data
read -rp "2. Download eyetracking data to $ROOT_DIR/data/raw/sub_${SUBJECT}/eyetracking? [Y/n]: " DL_EYE
if [[ ! "$DL_EYE" =~ ^[Nn]$ ]]; then
    echo "   Downloading eyetracking data..."
    gdown --folder "https://drive.google.com/drive/folders/1OgAIt8APBo5peqrJB53k7l6XdcBuM22L" -O "$ROOT_DIR/data/raw/sub_${SUBJECT}/eyetracking" --remaining-ok
    echo "   ✓ Eyetracking data downloaded."
fi
echo ""

# 3. Psychopy event log
read -rp "3. Download Psychopy event log to $ROOT_DIR/data/raw/sub_${SUBJECT}/metadata? [Y/n]: " DL_PSYCH
if [[ ! "$DL_PSYCH" =~ ^[Nn]$ ]]; then
    echo "   Downloading Psychopy event log..."
    gdown --folder "https://drive.google.com/drive/folders/1alyi6ODMj9Gp1955NRTRya8l4S5JIprw" -O "$ROOT_DIR/data/raw/sub_${SUBJECT}/metadata" --remaining-ok
    echo "   ✓ Psychopy event log downloaded."
fi
echo ""

# 4. MEG empty room noise recording
read -rp "4. Download MEG empty room noise recording to $ROOT_DIR/data/raw/sub_${SUBJECT}/session1_noise? [Y/n]: " DL_NOISE
if [[ ! "$DL_NOISE" =~ ^[Nn]$ ]]; then
    echo "   Downloading MEG empty room noise recording..."
    gdown --folder "https://drive.google.com/drive/folders/1kFlC4z0s_NVNjd06ZNiJTG1_5wtavpMV" -O "$ROOT_DIR/data/raw/sub_${SUBJECT}/session1_noise" --remaining-ok
    echo "   ✓ MEG noise recording downloaded."
fi
echo ""

# 5. MEG subject recording
read -rp "5. Download MEG subject recording to $ROOT_DIR/data/raw/sub_${SUBJECT}/session1_task? [Y/n]: " DL_TASK
if [[ ! "$DL_TASK" =~ ^[Nn]$ ]]; then
    echo "   Downloading MEG subject recording..."
    gdown --folder "https://drive.google.com/drive/folders/1MOsnXZLpPr9VIA71SVxPx6Pi4uyKtr7P" -O "$ROOT_DIR/data/raw/sub_${SUBJECT}/session1_task" --remaining-ok
    echo "   ✓ MEG subject recording downloaded."
fi
echo ""

# 6. Main config file
read -rp "6. Download main config file to $ROOT_DIR/data/configs/${EXPERIMENT}? [Y/n]: " DL_CONFIG
if [[ ! "$DL_CONFIG" =~ ^[Nn]$ ]]; then
    echo "   Downloading main config file..."
    cd "$ROOT_DIR/data/configs/${EXPERIMENT}"
    gdown --fuzzy "https://drive.google.com/file/d/1OUrWj_UesWQFlbZygHYYDO0queHuCsW9/view?usp=sharing" --remaining-ok
    echo "   ✓ Main config file downloaded."
fi
echo ""

# 7. Subject-specific bids config file
read -rp "7. Download subject-specific bids config file to $ROOT_DIR/data/configs/${EXPERIMENT}/bids? [Y/n]: " DL_BIDS_CONFIG
if [[ ! "$DL_BIDS_CONFIG" =~ ^[Nn]$ ]]; then
    echo "   Downloading subject-specific bids config file..."
    cd "$ROOT_DIR/data/configs/${EXPERIMENT}/bids"
    gdown --fuzzy "https://drive.google.com/file/d/1WT8W9-nfS7atxm1REEMaoi4Xv2PVrQpt/view?usp=sharing" --remaining-ok
    echo "   ✓ Subject-specific bids config file downloaded."
fi
echo ""

# --- Step 8: Download and configure runlocal-mne-opm.sh ---
echo "--- Step 8: Download runlocal-mne-opm.sh and update its paths for you ---"
echo ""

read -rp "Download runlocal-mne-opm.sh to $ROOT_DIR/analysis? [Y/n]: " DL_RUNLOCAL
if [[ ! "$DL_RUNLOCAL" =~ ^[Nn]$ ]]; then
    echo "   Downloading runlocal-mne-opm.sh..."
    cd "$ROOT_DIR/analysis"
    gdown --fuzzy "https://drive.google.com/file/d/1Iw-8spc5nn9Gypv0_qryimlTnEUr4g4Y/view?usp=sharing" --remaining-ok
    chmod +x "$ROOT_DIR/analysis/runlocal-mne-opm.sh"
    echo "   ✓ runlocal-mne-opm.sh downloaded."
    echo ""

    echo "   Updating parameters and paths in runlocal-mne-opm.sh..."
    RUN_SCRIPT="$ROOT_DIR/analysis/runlocal-mne-opm.sh"

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
echo "    cd $INSTALL_DIR/mne-opm"
echo "    uv run python my_script.py"
echo ""
echo "---------------------------------------------"
echo ""

echo "How to use mne-opm:"
echo ""
echo "  1. Edit the config file as needed."
echo ""
echo "  2. Choose a PIPELINE in runlocal-mne-opm.sh (line 7) and run it."
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
