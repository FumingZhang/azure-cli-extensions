#!/bin/bash

cat /dev/null > env.list
echo "TENANT_ID=$TENANT_ID" >> env.list
echo "AZCLI_ALT_SUBSCRIPTION_ID=$AZCLI_ALT_SUBSCRIPTION_ID" >> env.list
echo "AZCLI_ALT_CLIENT_ID=$AZCLI_ALT_CLIENT_ID" >> env.list
echo "AZCLI_ALT_CLIENT_SECRET=$MAPPED_AZCLI_ALT_CLIENT_SECRET" >> env.list
echo "TEST_SECRET=$MAPPED_TEST_SECRET" >> env.list

echo "PYTHON_VERSION=$PYTHON_VERSION" >> env.list
echo "COVERAGE=$COVERAGE" >> env.list
echo "TEST_MODE=$TEST_MODE" >> env.list
echo "PARALLELISM=$PARALLELISM" >> env.list
echo "REPO=$REPO" >> env.list
echo "BRANCH=$BRANCH" >> env.list
