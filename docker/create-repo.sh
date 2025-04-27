#!/bin/bash
set -e

TOKEN=${1:-$(openssl rand -hex 20)}
REPO_PATH="/srv/git/$TOKEN.git"

git init --bare $REPO_PATH
git -C $REPO_PATH config http.receivepack true
git -C $REPO_PATH config http.uploadpack true
chown -R www-data:www-data $REPO_PATH

echo "Repository created at: $REPO_PATH"
echo "Clone URL: http://yourserver/$TOKEN.git"
