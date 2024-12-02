#!/bin/bash
set -e

echo "Starting to package AWS Lambda Function (Python)."

source_path="../sync_db_lambda"
packages_dir="tf_generated/packages"
runtime="python3.12"
venv="venv"

echo "Remove and create new packages directory."
rm -rf "$packages_dir"
mkdir -p "$packages_dir"

echo "Create and activate a virtual environment $runtime."
$runtime -m venv "$venv"
source "$venv/bin/activate"

echo "Install dependencies."
pip install -r "$source_path/requirements.txt"

echo "Deactivate virtual environment."
deactivate

echo "Copy dependencies to $packages_dir directory."
cp -r "$venv/lib/$runtime/site-packages/"* "$packages_dir"

echo "Copy main.py file to $packages_dir directory."
cp "$source_path/main.py" "$packages_dir/"

echo "DONE"
echo "Packages Path: $(pwd)/$packages_dir"
