#!/usr/bin/env bash
set -euo pipefail

# a small script for testing our built wheels in a variety of linux distros

IMAGE="${1:?usage: ./test_wheels_in_image.sh <image>}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
cd "$ROOT_DIR"

# setup our deps - should only need a python3 build
docker build -t wheeltest -f - . <<DOCKERFILE
FROM $IMAGE
RUN if command -v apk >/dev/null; then \
      apk add --no-cache python3 py3-pip bash; \
    elif command -v apt-get >/dev/null; then \
      apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-venv; \
    elif command -v dnf >/dev/null; then \
      dnf install -y python3 python3-pip; \
    elif command -v pacman >/dev/null; then \
      pacman -Sy --noconfirm python python-pip; \
    elif command -v zypper >/dev/null; then \
      zypper install -y python3 python3-pip; \
    elif command -v xbps-install >/dev/null; then \
      xbps-install -Sy python3 python3-pip bash; \
    fi
DOCKERFILE

# install + smoketest
docker run --rm -v "$PWD:/work" -w /work wheeltest bash -lc '
  set -euo pipefail
  python3 -m venv /tmp/venv
  source /tmp/venv/bin/activate
  pip install dist/*.whl
  for toml in */pyproject.toml; do
    module="$(basename "$(dirname "$toml")" | tr "-" "_")"
    python -c "import $module; $module.smoketest()" && echo "$module: OK"
  done

  # Verify all binaries and shared libs are self-contained (no missing deps)
  echo
  echo "Checking shared library dependencies..."
  ldd_out=$(find /tmp/venv -type f \( -executable -o -name "*.so*" \) -exec ldd {} + 2>/dev/null) || true
  if echo "$ldd_out" | grep -q "not found"; then
    echo "ERROR: binaries have missing shared library dependencies:"
    echo "$ldd_out" | grep "not found"
    exit 1
  fi
  echo "All shared library deps OK"
'

echo
echo "All good!"
