# Bats test helpers — source via `load 'helpers/setup'` then call _cbox_test_setup.

_cbox_test_setup() {
  CBOX_DOTFILES="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  CBOX_LIB="${CBOX_DOTFILES}/.local/share/cbox/lib"
  CBOX_TMP="$(mktemp -d -t cbox-test.XXXXXX)"
  export CBOX_HOME="${CBOX_TMP}/cbox"
  export CBOX_STATE_DIR="${CBOX_HOME}/state"
  mkdir -p "${CBOX_STATE_DIR}"
  export PATH="${CBOX_DOTFILES}/.local/bin:${PATH}"
}

teardown() {
  [[ -n "${CBOX_TMP:-}" ]] && rm -rf "${CBOX_TMP}"
}

fail() {
  echo "$@" >&2
  return 1
}
