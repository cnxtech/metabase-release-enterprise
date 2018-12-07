#!/usr/bin/env bash

# After running ./release.sh run this when you are ready to publish the release

set -eu


if [ $# -lt 1 ]; then
    echo "usage: $0 X.Y.Z"
    exit 1
fi
VERSION=$1

echo "Updating Docker tag metabase/metabase:latest to metabase/metabase:v$VERSION"
docker pull metabase/metabase:v$VERSION
docker tag metabase/metabase:v$VERSION metabase/metabase:latest
docker push metabase/metabase:latest

# TODO:
# * update version-info.json
# * publish Github release
# * publish blog post
# * tweet
