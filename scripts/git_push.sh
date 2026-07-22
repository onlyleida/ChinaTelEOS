#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

REMOTE_URL="https://github.com/onlyleida/ChinaTelEOS.git"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "当前目录不是 Git 仓库。" >&2
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  current="$(git remote get-url origin)"
  if [[ "$current" != "$REMOTE_URL" && "$current" != "${REMOTE_URL%.git}" && "$current" != "${REMOTE_URL}.git" ]]; then
    echo "origin 当前指向：$current"
    echo "期望地址：$REMOTE_URL"
    echo "如需改写，请手动执行：git remote set-url origin $REMOTE_URL" >&2
    exit 1
  fi
else
  git remote add origin "$REMOTE_URL"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "工作区有未提交更改，请先 commit 再 push：" >&2
  git status --short >&2
  exit 1
fi

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "当前不在命名分支上。" >&2
  exit 1
fi

git push -u origin "$branch"
echo "已推送到 origin/$branch"
