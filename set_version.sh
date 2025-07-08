#!/bin/bash

#  set_version.sh
#  LockIt
#
#  Created by Knot Ding on 2025/7/9.
#

# Get the latest tag
TAG=$(git describe --tags --abbrev=0)

# Remove the 'v' prefix
VERSION=${TAG#v}

# Get the latest commit hash
COMMIT_HASH=$(git rev-parse --short HEAD)

# Get the path to the Info.plist
INFO_PLIST="LockIt/Info.plist"

# Update the CFBundleShortVersionString
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"

# Update the CFBundleVersion
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $COMMIT_HASH" "$INFO_PLIST"

echo "Set version to $VERSION ($COMMIT_HASH) in $INFO_PLIST"