#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Error: Please provide a repository token"
  echo "Usage: $0 <token>"
  exit 1
fi

REPO_PATH="/srv/git/$1.git"

if [ ! -d "$REPO_PATH" ]; then
  echo "Error: Repository $1.git not found"
  exit 1
fi

rm -rf "$REPO_PATH"
echo "Repository $1.git deleted successfully"
