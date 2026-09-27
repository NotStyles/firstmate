#!/usr/bin/env bash
# Drives the real bin/fm-remote-secondmate-control.sh sync leg (the host-local
# command session-start, spawn, and /updatefirstmate all invoke over SSH)
# against a real git topology: forge (bare origin), primary, host code root,
# and a separate-clone remote secondmate home cloned at an OLD release.
# Usage: drive-remote-sync.sh <firstmate-root-to-run> <label>
set -u
R=$1; LABEL=$2
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
W=$(mktemp -d /tmp/fm-drive.XXXXXX)
say() { printf '\n### %s\n' "$*"; }
git init -q -b main "$W/main"
printf 'projects/\nstate/\ndata/\nconfig/\n.no-mistakes/\n.fm-secondmate-home\n' > "$W/main/.gitignore"
printf 'v1\n' > "$W/main/AGENTS.md"; mkdir -p "$W/main/bin"; printf 'echo a\n' > "$W/main/bin/tool.sh"
git -C "$W/main" add -A; git -C "$W/main" commit -qm c1
git init -q --bare "$W/forge.git"
git -C "$W/main" remote add origin "$W/forge.git"; git -C "$W/main" push -q -u origin main
git --git-dir="$W/forge.git" symbolic-ref HEAD refs/heads/main
git clone -q "$W/forge.git" "$W/coderoot"
# Remote home cloned at the OLD release, then drop origin/HEAD like a pre-set-head clone.
git clone -q "$W/forge.git" "$W/sm1"; git -C "$W/sm1" checkout -q main
mkdir -p "$W/sm1/state" "$W/sm1/data" "$W/sm1/config" "$W/sm1/projects"; echo sm1 > "$W/sm1/.fm-secondmate-home"
git -C "$W/sm1" symbolic-ref --delete refs/remotes/origin/HEAD
# Primary releases 37 commits and pushes them (the real-world "37 ahead" case).
for i in $(seq 1 37); do printf 'r%s\n' "$i" >> "$W/main/README.md"; git -C "$W/main" add -A; git -C "$W/main" commit -qm "rel $i"; done
git -C "$W/main" push -q origin main
NEW=$(git -C "$W/main" rev-parse HEAD)
say "[$LABEL] S1: 2-arg sync <id> <primary-commit> (session-start / spawn wire shape)"
start=$(date +%s)
FM_HOME="$W/sm1" FM_ROOT_OVERRIDE="$W/coderoot" "$R/bin/fm-remote-secondmate-control.sh" sync sm1 "$NEW"; echo "rc=$? elapsed=$(( $(date +%s)-start ))s"
echo "home HEAD == release: $([ "$(git -C "$W/sm1" rev-parse HEAD)" = "$NEW" ] && echo yes || echo no)"
echo "git status -sb:"; git -C "$W/sm1" status -sb | head -1
echo "origin/HEAD: $(git -C "$W/sm1" symbolic-ref --quiet refs/remotes/origin/HEAD || echo '<missing>')"
echo "rev-list --count origin/main..HEAD: $(git -C "$W/sm1" rev-list --count origin/main..HEAD)"
echo "porcelain changes: $(git -C "$W/sm1" status --porcelain | wc -l)"

say "[$LABEL] S2: already-current home with stale tracking refs"
git -C "$W/sm1" update-ref refs/remotes/origin/main "$(git -C "$W/main" rev-parse HEAD~5)"
git -C "$W/sm1" symbolic-ref --delete refs/remotes/origin/HEAD 2>/dev/null
FM_HOME="$W/sm1" FM_ROOT_OVERRIDE="$W/coderoot" "$R/bin/fm-remote-secondmate-control.sh" sync sm1 "$NEW"; echo "rc=$?"
git -C "$W/sm1" status -sb | head -1
echo "origin/HEAD: $(git -C "$W/sm1" symbolic-ref --quiet refs/remotes/origin/HEAD || echo '<missing>')"

say "[$LABEL] S3: adversarial - origin unreachable (forge moved away); sync must still converge"
printf 'r-more\n' >> "$W/main/README.md"; git -C "$W/main" commit -qam more; git -C "$W/main" push -q origin main
NEW2=$(git -C "$W/main" rev-parse HEAD)
git -C "$W/coderoot" fetch -q origin   # host copy has the commit so import works without origin
mv "$W/forge.git" "$W/forge.gone"
start=$(date +%s)
FM_HOME="$W/sm1" FM_ROOT_OVERRIDE="$W/coderoot" "$R/bin/fm-remote-secondmate-control.sh" sync sm1 "$NEW2"; echo "rc=$? elapsed=$(( $(date +%s)-start ))s"
echo "home HEAD == release2: $([ "$(git -C "$W/sm1" rev-parse HEAD)" = "$NEW2" ] && echo yes || echo no)"
mv "$W/forge.gone" "$W/forge.git"

say "[$LABEL] S4: adversarial - origin hangs (ssh url, core.sshCommand sleeps 30s); bounded + configured ssh preserved"
cat > "$W/slowssh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$W/ssh.log"
sleep 30
SH
chmod +x "$W/slowssh"
git -C "$W/sm1" remote set-url origin "ssh://git@forge.invalid/repo.git"
git -C "$W/sm1" config core.sshCommand "$W/slowssh"
printf 'r-more2\n' >> "$W/main/README.md"; git -C "$W/main" commit -qam more2; git -C "$W/main" push -q origin main
NEW3=$(git -C "$W/main" rev-parse HEAD); git -C "$W/coderoot" fetch -q origin
start=$(date +%s)
FM_HOME="$W/sm1" FM_ROOT_OVERRIDE="$W/coderoot" "$R/bin/fm-remote-secondmate-control.sh" sync sm1 "$NEW3"; echo "rc=$? elapsed=$(( $(date +%s)-start ))s"
echo "home HEAD == release3: $([ "$(git -C "$W/sm1" rev-parse HEAD)" = "$NEW3" ] && echo yes || echo no)"
echo "configured sshCommand invocations:"; cat "$W/ssh.log" 2>/dev/null || echo '<none>'
git -C "$W/sm1" config --unset core.sshCommand; git -C "$W/sm1" remote set-url origin "$W/forge.git"

say "[$LABEL] S5: adversarial - dirty home is refused and its working tree + tracking refs untouched"
printf 'r-more3\n' >> "$W/main/README.md"; git -C "$W/main" commit -qam more3; git -C "$W/main" push -q origin main
NEW4=$(git -C "$W/main" rev-parse HEAD); git -C "$W/coderoot" fetch -q origin
printf 'local edit\n' >> "$W/sm1/AGENTS.md"
before_om=$(git -C "$W/sm1" rev-parse origin/main); before_head=$(git -C "$W/sm1" rev-parse HEAD)
FM_HOME="$W/sm1" FM_ROOT_OVERRIDE="$W/coderoot" "$R/bin/fm-remote-secondmate-control.sh" sync sm1 "$NEW4"; echo "rc=$?"
echo "HEAD unchanged: $([ "$(git -C "$W/sm1" rev-parse HEAD)" = "$before_head" ] && echo yes || echo no)"
echo "origin/main unchanged: $([ "$(git -C "$W/sm1" rev-parse origin/main)" = "$before_om" ] && echo yes || echo no)"
echo "local edit preserved: $(tail -1 "$W/sm1/AGENTS.md")"
git -C "$W/sm1" checkout -q -- AGENTS.md

say "[$LABEL] S6: wire shape - a 3-arg sync is still rejected as usage (shape unchanged)"
FM_HOME="$W/sm1" FM_ROOT_OVERRIDE="$W/coderoot" "$R/bin/fm-remote-secondmate-control.sh" sync sm1 "$NEW4" yes >/dev/null 2>&1; echo "rc=$?"
rm -rf "$W"
