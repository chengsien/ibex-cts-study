#!/usr/bin/env bash
# Rebuild the ORFS docker image from its layer blobs when `docker pull` is
# blocked by Docker Hub's anonymous manifest rate limit (HTTP 429).
# Blob downloads are not rate limited; the layer digests are published by the
# Docker Hub web API. Every blob is verified against its SHA256 digest.
set -euo pipefail
TAG="${1:-26Q4-260-gc9ac73efc}"
WORK="${2:-$PWD/orfs_image_build}"
mkdir -p "$WORK/blobs"; cd "$WORK"
curl -sf "https://hub.docker.com/v2/repositories/openroad/orfs/tags/$TAG/images" > images.json
python3 -c "
import json;d=json.load(open('images.json'));d=[i for i in d if i['architecture']=='amd64'][0]
[print(l['digest']) for l in d['layers'] if l.get('digest')]" > digests.txt
tok=$(curl -sf "https://auth.docker.io/token?service=registry.docker.io&scope=repository:openroad/orfs:pull" \
      | python3 -c "import json,sys;print(json.load(sys.stdin)['token'])")
while read -r d; do
  f=${d#sha256:}; [[ -s blobs/$f ]] && continue
  curl -sfL -H "Authorization: Bearer $tok" -o "blobs/$f" \
    "https://registry-1.docker.io/v2/openroad/orfs/blobs/$d"
done < digests.txt
while read -r d; do f=${d#sha256:}; echo "$f  blobs/$f"; done < digests.txt | sha256sum -c --quiet
rm -rf rootfs && mkdir rootfs
python3 - rootfs $(sed 's/sha256:/blobs\//' digests.txt) <<'PY'
import tarfile, os, shutil, sys
root=sys.argv[1]
def rm(p):
    if os.path.islink(p) or os.path.isfile(p): os.unlink(p)
    elif os.path.isdir(p): shutil.rmtree(p)
for b in sys.argv[2:]:
    with tarfile.open(b) as t:
        keep=[]
        for m in t.getmembers():
            base=os.path.basename(m.name); d=os.path.dirname(m.name)
            if base=='.wh..wh..opq':                       # opaque dir
                tgt=os.path.join(root,d)
                if os.path.isdir(tgt):
                    for c in os.listdir(tgt): rm(os.path.join(tgt,c))
            elif base.startswith('.wh.'):                  # whiteout
                rm(os.path.join(root,d,base[4:]))
            else: keep.append(m)
        for m in keep:
            p=os.path.join(root,m.name)
            if os.path.lexists(p) and not (m.isdir() and os.path.isdir(p) and not os.path.islink(p)):
                rm(p)
        t.extractall(root, members=keep, numeric_owner=True, filter='fully_trusted')
PY
tar -C rootfs -c . | docker import \
  --change 'ENV PATH=/usr/local/bin/wrapped-cc:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
  --change 'WORKDIR /OpenROAD-flow-scripts' --change 'CMD ["/bin/bash"]' \
  - "openroad/orfs:$TAG"
echo "imported openroad/orfs:$TAG"
