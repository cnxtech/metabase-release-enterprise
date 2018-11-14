#!/usr/bin/env bash

# The expectation is that this script will be run in a directory
# containing a 'certs' subdirectory with the
# keystore file (named metabase_keystore.jks) and
# The mac app pem signing key (named "key.pem")
# If not, you will be prompted


set -eu


if [ $# -lt 1 ]; then
    echo "usage: $0 X.Y.Z [BRANCH]"
    exit 1
fi
VERSION=$1

if [ $# -lt 2 ]; then
    BRANCH="release-$VERSION"
else
    BRANCH=$2
fi

# check that docker is running
docker ps > /dev/null

# ensure DockerHub credentials are configured
if [ -z ${DOCKERHUB_EMAIL+x} ] || [ -z ${DOCKERHUB_USERNAME+x} ] || [ -z ${DOCKERHUB_PASSWORD+x} ]; then
    echo "Ensure DOCKERHUB_EMAIL, DOCKERHUB_USERNAME, and DOCKERHUB_PASSWORD are set.";
    exit 1
fi

# ensure AWS is configured for the Beanstalk build
if [ -z ${AWS_DEFAULT_PROFILE+x} ]; then
    echo "Using default AWS_DEFAULT_PROFILE.";
    AWS_DEFAULT_PROFILE=default
fi

DEFAULT_KEYSTORE_PATH="$PWD/certs/metabase_keystore.jks"
# ensure we have access to the keystore
if [ -z ${KEYSTORE_PATH+x} ]; then
    KEYSTORE_PATH="$DEFAULT_KEYSTORE_PATH"
fi
if [ ! -f "$KEYSTORE_PATH" ]; then
    echo "Can't find Keystore with Jar signing key"
    exit 1
fi

# commenting out the below section until we bring the mac build into this
# # ensure we've configured the Mac signing key
# DEFAULT_KEY_PEM_PATH="$PWD/certs/key.pem"
# if [ -z "$KEY_PEM_PATH" ]; then
#     KEY_PEM_PATH="$DEFAULT_KEY_PEM_PATH"
# fi

# if [ !(-f "$KEY_PEM_PATH") ]; then
#     echo "Can't find Mac signing key"
#     exit 1
# fi


# commenting out the below section until we bring the mac build into this
# DEFAULT_CONFIG_JSON_PATH="$PWD/config.json"
# # ensure we have access to the Mac build config
# if [ -f "$CONFIG_JSON_PATH" ]; then
#     CONFIG_JSON_PATH="$DEFAULT_CONFIG_JSON_PATH"
# fi

# if [ !(-f "$CONFIG_JSON_PATH") ]; then
#     echo "Can't find Mach build config"
#     exit 1
# fi



# confirm the version and branch
echo "Releasing v$VERSION from branch $BRANCH. Press enter to continue or ctrl-C to abort."
read

# ensure the main repo is cloned
if ! [ -d "metabase" ]; then
    git clone git@github.com:metabase/metabase.git
fi

echo "fetching"
cd metabase
git fetch

echo "checkout the correct branch : $BRANCH from origin/$BRANCH"
git co "$BRANCH"

echo "ensure the version is correct"
sed -i '' s/^VERSION.*/VERSION=\"v$VERSION\"/ bin/version
git commit -m "v$VERSION" bin/version || true

echo "delete old tags"
git push --delete origin "v$VERSION" || true
git tag --delete "v$VERSION" || true

echo "taging it"
git tag -a "v$VERSION" -m "v$VERSION"
git push --follow-tags -u origin "$BRANCH"

echo "build it"
bin/build

echo "signing jar"
jarsigner -tsa "http://timestamp.digicert.com" -keystore "$KEYSTORE_PATH" "target/uberjar/metabase.jar" server

echo "verifing jar"
jarsigner -verify "target/uberjar/metabase.jar"

echo "uploading to s3"
aws s3 cp "target/uberjar/metabase.jar" "s3://downloads.metabase.com/v$VERSION/metabase.jar"

echo "build docker image + publish"
bin/docker/build_image.sh release "v$VERSION" --publish

echo "create elastic beanstalk artifacts"
bin/aws-eb-docker/release-eb-version.sh "v$VERSION"

# commenting out the below section until we bring the mac build into this
# mac it
# git submodule update --init
# brew install curl && brew link curl --force || true
# sudo cpan install File::Copy::Recursive JSON Readonly String::Util Text::Caml WWW::Curl::Simple
# ./bin/osx-setup
# echo "ok"

cd ..

echo "pulling down metabase-deploy"
if ! [ -d "metabase-deploy" ]; then
    echo "cant find ... cloning"
    git clone git@github.com:metabase/metabase-deploy.git
fi

echo "pulling"
cd metabase-deploy
git pull

echo "release heroku artifacts"
# This is subsumed by the new buildpack PR
# bin/release-heroku "v$VERSION"



echo "pulling down metabase-buildpack"
if ! [ -d "metabase-buildpack" ]; then
    echo "cant find ... cloning"
    git clone git@github.com:metabase/metabase-buildpack.git
fi

echo "pulling"
cd metabase-buildpack
git pull

echo "release heroku artifacts"
echo "$VERSION" > bin/version
git add .
git commit -m "Deploy v$VERSION"
git tag "$VERSION"
git push
git push --tags origin master