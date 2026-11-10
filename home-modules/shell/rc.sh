# shellcheck shell=sh

if [ "${ISSL_RC_SH_LOADED:-0}" = "1" ]; then
  return 0
fi
ISSL_RC_SH_LOADED=1

issl_bootstrap_shell_home="${XDG_CONFIG_HOME:-$HOME/.config}/issl/shell"

if [ -f "${issl_bootstrap_shell_home}/env.sh" ]; then
  . "${issl_bootstrap_shell_home}/env.sh"
fi

# ===== Functions and Aliases ===== #

# Configure GNU-style color output for common tools when available.
if command -v dircolors > /dev/null 2>&1; then
  # Prefer ~/.dircolors, then the shared ISSL file.
  issl_dircolors_path="${ISSL_SHELL_HOME}/.dircolors"
  if [ -r "${HOME}/.dircolors" ]; then
    eval "$(dircolors -b "${HOME}/.dircolors")"
  elif [ -r "${issl_dircolors_path}" ]; then
    eval "$(dircolors -b "${issl_dircolors_path}")"
  else
    # Fall back to system default LS_COLORS.
    eval "$(dircolors -b)"
  fi

  alias ls='ls --color=auto --classify=auto'     # Colorize directory listings and classify entries.
  alias dir='dir --color=auto --classify=auto'   # Colorize dir output and classify entries.
  alias vdir='vdir --color=auto --classify=auto' # Colorize verbose dir output and classify entries.
  alias grep='grep --color=auto'                 # Highlight grep matches.
  alias fgrep='grep -F --color=auto'             # Highlight fixed-string grep matches.
  alias egrep='grep -E --color=auto'             # Highlight extended-regex grep matches.
else
  alias ls='ls --classify=auto'     # Classify entries in directory listings.
  alias dir='dir --classify=auto'   # Classify entries in dir output.
  alias vdir='vdir --classify=auto' # Classify entries in verbose dir output.
fi

alias rm='rm -i' # Ask before file removal.
alias mv='mv -i' # Ask before overwrite on move.
alias cp='cp -i' # Ask before overwrite on copy.

alias la='ls -A'  # Show all except the . and .. entries.
alias ll='ls -lh' # Long list with human-readable sizes.
alias lla='ll -A' # Long list including hidden files except the . and .. entries.
alias lr='ls -R'  # Recursive listing.
alias lra='lr -A' # Recursive listing including hidden files except the . and .. entries.

# Use colordiff when available, otherwise keep unified diff output.
if command -v colordiff > /dev/null 2>&1; then
  alias diff='colordiff -u' # Unified diff with color.
else
  alias diff='diff -u' # Unified diff without color.
fi

alias makej='make -j$(( $(nproc 2>/dev/null || echo 1) + 1 ))' # Build in parallel with CPU cores + 1 jobs.

# Preprocess non-text input files for less when lesspipe is available.
if [ -x /usr/bin/lesspipe ]; then
  eval "$(SHELL=/bin/sh lesspipe)"
fi

man() {
  env \
    LESS_TERMCAP_md="$(printf '\033[01;36m')" \
    LESS_TERMCAP_me="$(printf '\033[0m')" \
    LESS_TERMCAP_us="$(printf '\033[01;32m')" \
    LESS_TERMCAP_ue="$(printf '\033[0m')" \
    LESS_TERMCAP_so="$(printf '\033[45;93m')" \
    LESS_TERMCAP_se="$(printf '\033[0m')" \
    man "$@"
}
