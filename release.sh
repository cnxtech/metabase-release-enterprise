#!/usr/bin/env bash

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 X.Y.Z"
    exit 1
fi
VERSION=$1

BRANCH='enterprise-master'

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

# confirm the version and branch
echo "Releasing v$VERSION from branch $BRANCH. Press enter to continue or ctrl-C to abort."
read

# ensure the main repo is cloned
if ! [ -d "metabase-enterprise" ]; then
    git clone git@github.com:metabase/metabase-enterprise.git
fi

echo "fetching"
cd metabase-enterprise
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

echo "Remove old Metabase uberjars"
rm -rf target/uberjar/metabase.jar

echo "Remove old local installations of metabase-core lib..."
rm -rf ~/.m2/repository/metabase*

echo "Installing yarn deps"
yarn

echo "build it"
bin/build

echo "Building Docker image"
docker_image_tag="metabase/metabase-enterprise:$VERSION"
cp target/uberjar/metabase.jar bin/docker/metabase.jar
docker build -t "$docker_image_tag" bin/docker

echo "Pushing Docker image with tag $docker_image_tag"
docker push

echo "Pushing Docker tag metabase/metabase-enterprise:latest"
docker push metabase/metabase-enterprise:latest

echo "uploading to s3"
aws s3 cp "target/uberjar/metabase.jar" "s3://downloads.metabase.com/enterprise/latest/metabase.jar"
