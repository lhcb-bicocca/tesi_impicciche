#!/bin/sh
env_dir_name="tesi-env"
ANALYSIS_HELPERS_MODE="latest"
ANALYSIS_HELPERS_REPO="git+ssh://git@github.com/cpviolation/analysis_helpers.git"
ANALYSIS_HELPERS_GIT_CLONE_URL="ssh://git@github.com/cpviolation/analysis_helpers.git"
ANALYSIS_HELPERS_CI_HTTPS_CLONE_URL="https://github.com/cpviolation/analysis_helpers.git"
DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH="${PWD}/external/analysis_helpers"
ANALYSIS_HELPERS_EDITABLE_PATH="${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}"
ANALYSIS_HELPERS_PATH_SET=0
ENV_CREATED=0
FORCE_ANALYSIS_HELPERS_INSTALL=0
CI_MODE=0
# Keep analysis_helpers runtime extras here so they are installed explicitly,
# without asking pip to re-resolve the whole environment and re-trigger ROOT/pandas conflicts.
ANALYSIS_HELPERS_EXTRA_DEPS="vector"

if [ "${CI}" = "true" ]; then
  CI_MODE=1
fi

print_usage() {
  cat <<EOF
Usage: . ./setup.sh [options]

Options:
  --analysis-helpers MODE       Install mode for analysis_helpers: latest|editable (default: latest)
  --analysis-helpers-path PATH  Local path used when MODE=editable (default: ./external/analysis_helpers)
  --update-analysis-helpers     Force reinstall/update of analysis_helpers even if already installed
  -h, --help                    Show this help and exit
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --analysis-helpers)
      ANALYSIS_HELPERS_MODE="$2"
      shift 2
      ;;
    --analysis-helpers-path)
      ANALYSIS_HELPERS_EDITABLE_PATH="$2"
      ANALYSIS_HELPERS_PATH_SET=1
      shift 2
      ;;
    --update-analysis-helpers)
      FORCE_ANALYSIS_HELPERS_INSTALL=1
      shift
      ;;
    -h|--help)
      print_usage
      return 0 2>/dev/null || exit 0
      ;;
    *)
      echo "Error: Unknown option '$1'."
      print_usage
      return 1 2>/dev/null || exit 1
      ;;
  esac
done

if [ "${ANALYSIS_HELPERS_MODE}" != "latest" ] && [ "${ANALYSIS_HELPERS_MODE}" != "editable" ]; then
  echo "Error: --analysis-helpers must be 'latest' or 'editable'."
  return 1 2>/dev/null || exit 1
fi

if [ "${ANALYSIS_HELPERS_MODE}" = "editable" ] && [ "${ANALYSIS_HELPERS_PATH_SET}" -eq 0 ]; then
  ANALYSIS_HELPERS_EDITABLE_PATH="${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}"
fi

install_analysis_helpers() {
  if [ "${FORCE_ANALYSIS_HELPERS_INSTALL}" -eq 0 ] && ${env_dir_name}/run pip show analysis_helpers >/dev/null 2>&1; then
    echo "analysis_helpers already installed. Skipping reinstall."
    echo "Use --update-analysis-helpers to force an update/reinstall."
    return 0
  fi

  if [ "${ANALYSIS_HELPERS_MODE}" = "latest" ]; then
    if [ "${CI_MODE}" -eq 1 ]; then
      echo "CI mode detected. Cloning analysis_helpers via HTTPS into ${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}..."
      mkdir -p "$(dirname "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}")"
      CI_ANALYSIS_HELPERS_CLONE_URL="${ANALYSIS_HELPERS_CI_HTTPS_CLONE_URL}"
      if [ -n "${ANALYSIS_HELPERS_GITHUB_TOKEN}" ]; then
        CI_ANALYSIS_HELPERS_CLONE_URL="https://x-access-token:${ANALYSIS_HELPERS_GITHUB_TOKEN}@github.com/cpviolation/analysis_helpers.git"
      fi
      if [ -d "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}/.git" ]; then
        git -C "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}" remote set-url origin "${CI_ANALYSIS_HELPERS_CLONE_URL}" || return 1
        git -C "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}" fetch --all --prune || return 1
        git -C "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}" reset --hard origin/master || return 1
      else
        rm -rf "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}"
        git clone "${CI_ANALYSIS_HELPERS_CLONE_URL}" "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}" || return 1
      fi
      echo "Installing analysis_helpers from CI clone..."
      ${env_dir_name}/run pip install --upgrade --no-deps "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}"
      return $?
    fi

    echo "Installing latest analysis_helpers from ${ANALYSIS_HELPERS_REPO}..."
    ${env_dir_name}/run pip install --upgrade --no-deps "${ANALYSIS_HELPERS_REPO}"
  else
    if [ ! -d "${ANALYSIS_HELPERS_EDITABLE_PATH}" ]; then
      if [ "${ANALYSIS_HELPERS_EDITABLE_PATH}" = "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}" ]; then
        echo "Editable path not found, cloning analysis_helpers into default location..."
        mkdir -p "$(dirname "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}")"
        git clone "${ANALYSIS_HELPERS_GIT_CLONE_URL}" "${DEFAULT_ANALYSIS_HELPERS_EDITABLE_PATH}" || return 1
      else
        echo "Error: Editable path not found: ${ANALYSIS_HELPERS_EDITABLE_PATH}"
        echo "       Clone the repository there or pass --analysis-helpers-path <path>."
        return 1
      fi
    fi

    echo "Installing editable analysis_helpers from ${ANALYSIS_HELPERS_EDITABLE_PATH}..."
    ${env_dir_name}/run pip install --upgrade --no-deps -e "${ANALYSIS_HELPERS_EDITABLE_PATH}"
  fi

  # Let the conda ROOT stack provide cppyy/CPyCppyy so ROOT imports stay coherent.
  ${env_dir_name}/run pip uninstall -y cppyy CPyCppyy >/dev/null 2>&1 || true
}

install_analysis_helpers_extra_deps() {
  for dep in ${ANALYSIS_HELPERS_EXTRA_DEPS}; do
    ${env_dir_name}/run pip install --upgrade --no-deps "${dep}"
  done
}

# Ensure that the virtual environment is created if not found
if [ ! -d "${env_dir_name}" ]; then
  echo "Creating the conda environment in ${env_dir_name}..."
  source /cvmfs/lhcb.cern.ch/lib/LbEnv
  lb-conda-dev virtual-env default/2026-05-18_11-29 "${env_dir_name}"
  ${env_dir_name}/run pip install --upgrade pip
  ${env_dir_name}/run pip install -r requirements.txt
  install_analysis_helpers_extra_deps
  install_analysis_helpers
  ENV_CREATED=1
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create the conda environment."
    exit 1
  fi
fi

if [ -d "${env_dir_name}" ] && [ "${ENV_CREATED}" -eq 0 ]; then
  install_analysis_helpers_extra_deps
  install_analysis_helpers
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install analysis_helpers (${ANALYSIS_HELPERS_MODE})."
    return 1 2>/dev/null || exit 1
  fi
fi

# Check if the directory exists before attempting to run
if [ -d "${env_dir_name}" ]; then
  ${env_dir_name}/run env D02KSHH=${PWD} PYTHONPATH=${PWD}/src bash --rcfile <(echo "[ -f \"$HOME/.bashrc.d/historyrc\" ] && source \"$HOME/.bashrc.d/historyrc\"; [ -f \"$HOME/.bashrc.d/aliasrc\" ] && source \"$HOME/.bashrc.d/aliasrc\"; PS1='(${env_dir_name}) ';") -i
else
  echo "Error: ${env_dir_name} directory not found."
  exit 1
fi

# Create directories for the output files
# DATADIRECTORIES=("data/ana-prod/" "data/skimming/" "data/skimming/minimalistic/")
# for directory in "${DATADIRECTORIES[@]}"; do
#   if [ ! -d "$directory" ]; then
#     mkdir -p "$directory"
#   fi
# done