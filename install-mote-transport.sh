#!/bin/sh
set -eu

release_tag=mote-transport-2026.08.30-r02-canary
release_repo=motebus/codex-installer
release_base_url=${MOTE_TRANSPORT_RELEASE_BASE_URL:-https://github.com/$release_repo/releases/download/$release_tag}
artifact_dir=
keep_downloads=0
verify_only=0

usage() {
  cat >&2 <<'USAGE'
Usage: install-mote-transport.sh [OPTIONS]

Install or verify the pinned Mote Transport canary on Ubuntu amd64.

Options:
  --artifact-dir DIR  Verify/install release assets already in DIR
  --verify-only       Verify OS, architecture, checksums, and package metadata
                      without installing or inspecting the running services
  --keep-downloads    Keep the temporary download directory
  -h, --help          Show this help

This installer is fail-closed. It installs missing packages and is idempotent
when the exact release is already installed. It refuses an implicit upgrade or
downgrade; use the separately reviewed rollback-aware upgrade procedure for
hosts with different installed versions.
USAGE
}

while test "$#" -gt 0; do
  case "$1" in
    --artifact-dir)
      test "$#" -ge 2 || { usage; exit 64; }
      artifact_dir=$2
      shift 2
      ;;
    --verify-only)
      verify_only=1
      shift
      ;;
    --keep-downloads)
      keep_downloads=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'install-mote-transport: unknown option: %s\n' "$1" >&2
      usage
      exit 64
      ;;
  esac
done

fail() {
  printf 'install-mote-transport: %s\n' "$*" >&2
  exit 65
}

for command_name in awk curl dpkg dpkg-deb dpkg-query find grep mktemp sha256sum stat systemctl; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: $command_name"
done

test -r /etc/os-release || fail '/etc/os-release is not readable'
# shellcheck disable=SC1091
. /etc/os-release
test "${ID:-}" = ubuntu || fail "unsupported operating system: ${ID:-unknown}"
case "${VERSION_ID:-}" in
  24.04|26.04) ;;
  *) fail "unsupported Ubuntu release: ${VERSION_ID:-unknown}" ;;
esac
test "$(dpkg --print-architecture)" = amd64 || fail "unsupported architecture: $(dpkg --print-architecture)"

temporary_dir=
cleanup() {
  if test -n "$temporary_dir" && test "$keep_downloads" -eq 0; then
    case "$temporary_dir" in
      /tmp/mote-transport-install.*) rm -rf -- "$temporary_dir" ;;
      *) printf 'install-mote-transport: refusing unsafe cleanup path: %s\n' "$temporary_dir" >&2 ;;
    esac
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if test -n "$artifact_dir"; then
  test -d "$artifact_dir" || fail "artifact directory does not exist: $artifact_dir"
  artifact_dir=$(CDPATH= cd -- "$artifact_dir" && pwd)
else
  temporary_dir=$(mktemp -d /tmp/mote-transport-install.XXXXXX)
  chmod 0700 "$temporary_dir"
  artifact_dir=$temporary_dir
fi

fetch_artifact() {
  file_name=$1
  destination=$artifact_dir/$file_name
  test -f "$destination" && return 0
  partial=$destination.part
  rm -f -- "$partial"
  curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
    --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 \
    --output "$partial" "$release_base_url/$file_name"
  mv -- "$partial" "$destination"
}

verify_artifact() {
  package_name=$1
  package_version=$2
  package_arch=$3
  file_name=$4
  expected_sha256=$5
  package_path=$artifact_dir/$file_name

  fetch_artifact "$file_name"
  test "$(sha256sum "$package_path" | awk '{print $1}')" = "$expected_sha256" || \
    fail "SHA-256 mismatch: $file_name"
  test "$(dpkg-deb -f "$package_path" Package)" = "$package_name" || \
    fail "unexpected Debian package name: $file_name"
  test "$(dpkg-deb -f "$package_path" Version)" = "$package_version" || \
    fail "unexpected Debian package version: $file_name"
  test "$(dpkg-deb -f "$package_path" Architecture)" = "$package_arch" || \
    fail "unexpected Debian package architecture: $file_name"
  printf 'artifact_verified=%s:%s:%s\n' "$package_name" "$package_version" "$expected_sha256"
}

verify_artifact sphere 4.0.0-1 amd64 sphere_4.0.0-1_amd64.deb \
  7e0be26927afa349001caee54cf46117587386f7d42ce82a9611fa50ea1e7065
verify_artifact mote-proxy 1.4.0-14 all mote-proxy_1.4.0-14_all.deb \
  95e3c6e930973c203ccd8590453d33fb9b7339c6ca7a4d527479b97a774428bf
verify_artifact moted 3.2.0-33 amd64 moted_3.2.0-33_amd64.deb \
  5341a5552c45d57a48260c26fb683581b9db8f948d49727a3b054c221f8085f6

if test "$verify_only" -eq 1; then
  printf 'release_tag=%s\nverification=passed\n' "$release_tag"
  exit 0
fi

install_required=0
check_installed_version() {
  package_name=$1
  expected_version=$2
  installed_version=$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)
  if test -z "$installed_version"; then
    install_required=1
    printf 'package_state=%s:missing\n' "$package_name"
  elif test "$installed_version" = "$expected_version"; then
    printf 'package_state=%s:exact:%s\n' "$package_name" "$installed_version"
  else
    fail "refusing implicit version change for $package_name: installed=$installed_version release=$expected_version"
  fi
}

check_installed_version sphere 4.0.0-1
check_installed_version mote-proxy 1.4.0-14
check_installed_version moted 3.2.0-33

if test "$install_required" -eq 1; then
  test "$(id -u)" -eq 0 || {
    printf '%s\n' \
      'install-mote-transport: root is required to install missing packages; use the approved native graphical authorization flow' >&2
    exit 77
  }
  command -v apt-get >/dev/null 2>&1 || fail 'apt-get is required to install packages'

  backup=/var/backups/mote-transport-$release_tag-$(date -u +%Y%m%dT%H%M%SZ)
  test ! -e "$backup" || fail "backup path already exists: $backup"
  install -d -o root -g root -m 0700 "$backup"
  for path in /etc/mote /etc/ssh/ssh_config.d/50-mote-proxy.conf /etc/ssh/sshd_config.d/50-moted.conf; do
    if test -e "$path"; then
      backup_name=$(printf '%s' "$path" | sed 's#^/##; s#/#-#g')
      cp -a -- "$path" "$backup/$backup_name"
    fi
  done
  dpkg-query -W -f='${Package}\t${Version}\n' sphere mote-proxy moted \
    >"$backup/packages-before.tsv" 2>/dev/null || true
  chmod 0600 "$backup/packages-before.tsv"

  DEBIAN_FRONTEND=noninteractive apt-get \
    -o Dpkg::Options::=--force-confold \
    --no-install-recommends --yes install \
    "$artifact_dir/sphere_4.0.0-1_amd64.deb" \
    "$artifact_dir/mote-proxy_1.4.0-14_all.deb" \
    "$artifact_dir/moted_3.2.0-33_amd64.deb"
  printf 'configuration_backup=%s\n' "$backup"
else
  printf 'install_transaction=skipped_exact_versions_present\n'
fi

for package_record in 'sphere:4.0.0-1' 'mote-proxy:1.4.0-14' 'moted:3.2.0-33'; do
  package_name=${package_record%%:*}
  expected_version=${package_record#*:}
  test "$(dpkg-query -W -f='${db:Status-Status}' "$package_name")" = installed || \
    fail "package is not installed: $package_name"
  test "$(dpkg-query -W -f='${Version}' "$package_name")" = "$expected_version" || \
    fail "installed version drift: $package_name"
done

for service_name in sphere.service sphere-dc.service sphere-motebus.service moted.service moted-ssh-relay.service mote-proxy.service ssh.service; do
  systemctl is-active --quiet "$service_name" || fail "required service is not active: $service_name"
  printf 'service_active=%s\n' "$service_name"
done

for trusted_path in /etc/ssh /etc/ssh/ssh_config.d /etc/ssh/ssh_config.d/50-mote-proxy.conf; do
  test -e "$trusted_path" || fail "required SSH trust path is missing: $trusted_path"
  if find "$trusted_path" -maxdepth 0 \( ! -user root -o -perm /022 \) -print | grep -q .; then
    fail "unsafe SSH owner or write mode: $trusted_path"
  fi
done

effective_ssh=$(ssh -G -o BatchMode=yes -o StrictHostKeyChecking=yes validation.mote 2>/dev/null)
printf '%s\n' "$effective_ssh" | grep -Fqx 'batchmode yes' || fail 'SSH BatchMode is not effective for .mote'
printf '%s\n' "$effective_ssh" | grep -Fqx 'stricthostkeychecking true' || \
  printf '%s\n' "$effective_ssh" | grep -Fqx 'stricthostkeychecking yes' || \
  fail 'strict host-key validation is not effective for .mote'
printf '%s\n' "$effective_ssh" | grep -Fqx \
  'proxycommand /usr/libexec/mote-proxy/ssh-proxy %h %p' || \
  fail 'the packaged Mote ProxyCommand is not effective for .mote'

if test "$(id -u)" -eq 0; then
  /usr/sbin/sshd -t || fail 'OpenSSH server configuration syntax check failed'
  printf 'sshd_syntax=passed\n'
else
  printf 'sshd_syntax=not_rerun_nonroot_active_service_verified\n'
fi

/usr/sbin/mote-proxy doctor >/dev/null || fail 'mote-proxy doctor failed'
/usr/sbin/moted inspect >/dev/null || fail 'moted inspect failed'

printf 'release_tag=%s\n' "$release_tag"
printf 'installation=passed\n'
printf 'scope=agent-first-ssh,sftp\n'
printf 'retired=legacy-scp,rsync,rdp\n'
