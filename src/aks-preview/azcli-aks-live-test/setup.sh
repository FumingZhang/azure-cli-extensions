#!/bin/bash

set -eux
pwd

# clone azure-cli & azure-cli-extensions
git clone https://github.com/Azure/azure-cli.git
git clone https://github.com/Azure/azure-cli-extensions.git

# list branches
cd azure-cli/
git branch -a
cd -
cd azure-cli-extensions/
git branch -a
cd -

# install python packages
python -m venv azEnv
source azEnv/bin/activate
pip install azdev
pip install pytest-json-report pytest-rerunfailures --upgrade
# pip install pytest-html --upgrade

# check existing az 
which az || true
az version || true
az extension list || true

# install latest az
azdev setup -c azure-cli -r azure-cli-extensions
deactivate
source azEnv/bin/activate

# check installation result
which az
az version
