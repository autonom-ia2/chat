#!/bin/sh

set -eu

umask 077

# Stage forced-publisher.sh beside this installer before invoking it. The
# installer never downloads or evaluates remote code.

fail() {
  printf '%s\n' 'instagram_publisher_install_failed' >&2
  exit 2
}

[ "$(id -u)" = "0" ] || fail
[ "$#" -eq 0 ] || fail

publisher_user='chatwoot_publisher'
publisher_home='/var/lib/chatwoot-publisher'
publisher_ssh_dir="${publisher_home}/.ssh"
publisher_command='/usr/local/libexec/instagram-tester-publisher-root'
sudoers_path='/etc/sudoers.d/instagram-tester-publisher'
source_wrapper="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/forced-publisher.sh"
[ -f "$source_wrapper" ] || fail
[ ! -L "$source_wrapper" ] || fail

IFS= read -r public_key || fail
[ -n "$public_key" ] || fail
key_type=${public_key%% *}
key_rest=${public_key#* }
key_data=${key_rest%% *}
[ "$key_type" = 'ssh-ed25519' ] || fail
[ -n "$key_data" ] || fail
case "$key_data" in
  *[!A-Za-z0-9+/=]*) fail ;;
esac
[ "${#key_data}" -ge 40 ] || fail

if ! /usr/bin/id "$publisher_user" >/dev/null 2>&1; then
  /usr/sbin/useradd --system --create-home --home-dir "$publisher_home" --shell /bin/sh "$publisher_user" || fail
fi

actual_home=$(/usr/bin/getent passwd "$publisher_user" | /usr/bin/awk -F: '{print $6}')
[ "$actual_home" = "$publisher_home" ] || fail
actual_shell=$(/usr/bin/getent passwd "$publisher_user" | /usr/bin/awk -F: '{print $7}')
[ "$actual_shell" = '/bin/sh' ] || fail
publisher_groups=$(/usr/bin/id -nG "$publisher_user" 2>/dev/null) || fail
case " $publisher_groups " in
  *' docker '* | *' sudo '* | *' wheel '* | *' root '* | *' admin '*) fail ;;
esac

/usr/bin/install -d -o root -g root -m 0755 /usr/local/libexec
/usr/bin/install -o root -g root -m 0755 "$source_wrapper" "$publisher_command"
/usr/bin/install -d -o root -g root -m 0755 "$publisher_home" "$publisher_ssh_dir"
[ ! -L "${publisher_ssh_dir}/authorized_keys" ] || fail

authorized_keys_tmp=$(/usr/bin/mktemp "${publisher_ssh_dir}/authorized_keys.XXXXXX") || fail
trap '/bin/rm -f "$authorized_keys_tmp"' EXIT
/bin/chown root:root "$authorized_keys_tmp"
/bin/chmod 0644 "$authorized_keys_tmp"
printf '%s\n' "command=\"/usr/bin/sudo -n $publisher_command\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 $key_data" > "$authorized_keys_tmp"
/bin/mv -f "$authorized_keys_tmp" "${publisher_ssh_dir}/authorized_keys"
trap - EXIT

[ ! -L "$sudoers_path" ] || fail
sudoers_tmp=$(/usr/bin/mktemp /etc/sudoers.d/instagram-tester-publisher.XXXXXX) || fail
trap '/bin/rm -f "$sudoers_tmp"' EXIT
/bin/chown root:root "$sudoers_tmp"
/bin/chmod 0440 "$sudoers_tmp"
printf '%s\n' "$publisher_user ALL=(root) NOPASSWD: $publisher_command \"\"" > "$sudoers_tmp"
/usr/sbin/visudo -cf "$sudoers_tmp" >/dev/null 2>&1 || fail
/bin/mv -f "$sudoers_tmp" "$sudoers_path"
trap - EXIT

/bin/chown root:root "$publisher_home" "$publisher_ssh_dir" "${publisher_ssh_dir}/authorized_keys" "$sudoers_path"
/bin/chmod 0755 "$publisher_home" "$publisher_ssh_dir"
/bin/chmod 0644 "${publisher_ssh_dir}/authorized_keys"
/bin/chmod 0440 "$sudoers_path"
