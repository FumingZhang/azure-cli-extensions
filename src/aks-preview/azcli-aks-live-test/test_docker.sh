#!/bin/bash

echo $TENANT_ID
echo $AZCLI_ALT_SUBSCRIPTION_ID
echo $AZCLI_ALT_CLIENT_ID
echo $AZCLI_ALT_CLIENT_SECRET
echo $TEST_SECRET

echo $PYTHON_VERSION
echo $COVERAGE
echo $LIVEMODE
echo $PARALLELISM
echo $REPO
echo $BRANCH

source ./azEnv/bin/activate
python ./test.py
az version
