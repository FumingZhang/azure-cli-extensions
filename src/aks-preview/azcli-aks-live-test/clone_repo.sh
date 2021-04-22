#!/bin/bash

set -eux
pwd

# clone azure-cli (default is the official repo)
# git clone https://github.com/Azure/azure-cli.git
git clone $CLI_REPO

# ckeckout to a specific azure-cli branch (default is the dev branch)
cd azure-cli/
git branch -a
git checkout $CLI_BRANCH
cd -

# check branch & commit logs
cd azure-cli-extensions/
git branch -a
git log -10
cd -
