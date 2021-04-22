#!/bin/bash

set -eux
pwd

# clone azure-cli & azure-cli-extensions
git clone https://github.com/Azure/azure-cli.git
git clone https://github.com/Azure/azure-cli-extensions.git
# git clone $REPO

# list branches
cd azure-cli/
git branch -a
cd -
cd azure-cli-extensions/
git branch -a
# git checkout $BRANCH
git log -5
cat src/aks-preview/setup.py
cd -
