#!/usr/bin/env bash

set -eu

red="\x1B[0;31m"
green="\x1B[0;32m"
nc="\x1B[0m"

check() {
  description=$1
  shift 1
  if sh -c "$*"; then
    echo -e "$green[pass]$nc $description"
  else
    echo -e "$red[fail]$nc $description"
  fi
}

if [ $# -lt 1 ]; then
    echo "usage: $0 X.Y.Z"
    exit 1
fi

VERSION=$1

jar_url="http://downloads.metabase.com/v$VERSION/metabase.jar"
jar_file="metabase-v$VERSION.jar"

# ensure the main repo is cloned
if ! [ -d "metabase" ]; then
    git clone git@github.com:metabase/metabase.git
fi

cd metabase
git fetch > /dev/null

tag_hash=$(git rev-list -n 1 "v$VERSION" | cut -c 1-7)

echo "tag commit hash: $tag_hash"

version_hash=$(git show "v$VERSION:bin/version" 2> /dev/null | sh | awk '{ print $2 }')

check "tagged commit's bin/version ($version_hash)" [ "$version_hash" == "$tag_hash" ]

if [ -f "$jar_file" ]; then
  echo "NOTE: using previously downloaded jar: $jar_file"
else
  curl -s -o "$jar_file" "$jar_url"
fi

jar_hash=$(java -jar "$jar_file" version | grep -Eo 'hash [0-9a-f]+' | awk '{ print $2 }')

check "jar commit hash ($jar_hash)" [ "$jar_hash" == "$tag_hash" ]

docker pull "metabase/metabase:v$VERSION" > /dev/null
docker_hash=$(docker run --rm "metabase/metabase:v$VERSION" version | grep -Eo 'hash [0-9a-f]+' | awk '{ print $2 }')
check "docker 'metabase/metabase:v$VERSION' commit hash ($docker_hash)" [ "$docker_hash" == "$tag_hash" ]

docker pull "metabase/metabase:latest" > /dev/null
docker_latest_hash=$(docker run --rm "metabase/metabase:latest" version | grep -Eo 'hash [0-9a-f]+' | awk '{ print $2 }')
check "docker 'metabase/metabase:latest' commit hash ($docker_latest_hash)" [ "$docker_latest_hash" == "$tag_hash" ]

check "launch-aws-eb.html" "curl -fs http://downloads.metabase.com/v$VERSION/launch-aws-eb.html > /dev/null"
check "metabase-aws-eb.zip" "curl -fs http://downloads.metabase.com/v$VERSION/metabase-aws-eb.zip > /dev/null"

cd ..

if ! [ -d "metabase-buildpack" ]; then
    git clone git@github.com:metabase/metabase-buildpack.git
fi

cd metabase-buildpack
git fetch > /dev/null

buildpack_version=$(git show origin/master:bin/version 2> /dev/null)
check "buildpack version ($buildpack_version)" [ "$buildpack_version" == "$VERSION" ]

latest_release=$(curl -f -s https://api.github.com/repos/metabase/metabase/releases/latest | jq -r '.tag_name')
check "latest github release ($latest_release)" [ "$latest_release" == "v$VERSION" ]

latest_version_info=$(curl -f -s http://static.metabase.com/version-info.json | jq -r '.latest.version')
check "latest version.info ($latest_version_info)" [ "$latest_version_info" == "v$VERSION" ]

check "mac app dmg" "curl -f -s -o /dev/null -r 0-0 http://downloads.metabase.com/v$VERSION/Metabase.dmg"

website_jar_version=$(curl -s 'https://metabase.com/start/jar.html' | grep -Eo 'v[0-9.]+' | head -1)
check "website jar version ($website_jar_version)" [ "$website_jar_version" == "v$VERSION" ]

website_mac_version=$(curl -s 'https://metabase.com/start/mac.html' | grep -Eo 'v[0-9.]+' | head -1)
check "website Mac version ($website_mac_version)" [ "$website_mac_version" == "v$VERSION" ]
