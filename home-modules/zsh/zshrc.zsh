if [ "${ISSL_ZSHRC_LOADED:-0}" = "1" ]; then
  return 0
fi
ISSL_ZSHRC_LOADED=1

issl_bootstrap_shell_home="${XDG_CONFIG_HOME:-$HOME/.config}/issl/shell"

if [ -f "${issl_bootstrap_shell_home}/rc.sh" ]; then
  . "${issl_bootstrap_shell_home}/rc.sh"
fi

# ===== History ===== #

export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history" # Persist history under the XDG state directory.

# zsh does not create the history file's parent directory on its own.
issl_zsh_histfile_dir="${HISTFILE:h}"
if [ ! -d "${issl_zsh_histfile_dir}" ]; then
  mkdir -p "${issl_zsh_histfile_dir}" 2> /dev/null || true
fi

export HISTSIZE=10000 # Keep up to 10000 commands in memory.
export SAVEHIST=10000 # Persist up to 10000 commands to HISTFILE.

setopt hist_ignore_space  # Skip commands that start with a space.
setopt hist_ignore_dups   # Skip recording a command that duplicates the previous one.
setopt hist_find_no_dups  # Skip duplicates when searching or scrolling history.
setopt extended_history   # Record execution timestamps in history entries.
setopt hist_reduce_blanks # Compress redundant internal whitespace before saving.
setopt append_history     # Append history entries instead of overwriting the file.
setopt share_history      # Share history across concurrent zsh sessions.
setopt hist_fcntl_lock    # Lock the history file with fcntl() for safe concurrent access.

# ===== Options ===== #

setopt auto_menu            # Show completion menu automatically on ambiguous completion.
setopt auto_param_keys      # Insert matching parameter expansion syntax during completion.
setopt complete_in_word     # Complete from both ends of the word around the cursor.
setopt correct              # Ask before running a command whose name looks misspelled.
setopt interactive_comments # Allow comments in interactive commands.
setopt magic_equal_subst    # Expand command arguments after '=' as file names where applicable.
setopt mark_dirs            # Append a trailing slash to completed directory names.
setopt no_beep              # Disable terminal beeps from Zsh.
setopt prompt_subst         # Expand parameters and command substitutions in prompts.
setopt rm_star_wait         # Add a short delay before confirming dangerous rm globs.

# ===== Prompt ===== #

autoload -Uz add-zsh-hook vcs_info

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats '%b'
zstyle ':vcs_info:git:*' actionformats '%b|%a'

if [[ -n ${TERM-} && ${TERM-} != "dumb" ]]; then
  PROMPT='zsh:%F{green}%~%f %F{magenta}${issl_prompt_vcs}%f$ '
  RPROMPT='%F{yellow}%w %T%f'
else
  PROMPT='zsh:%~ ${issl_prompt_vcs}$ '
  RPROMPT=''
fi

typeset -g issl_prompt_vcs=''

# Refresh the VCS information before every prompt.
# The hook unregisters itself once neither prompt references the VCS information.
issl_prompt_precmd() {
  setopt localoptions no_err_exit no_err_return no_warn_nested_var no_ignore_braces no_force_float no_sh_glob unset

  if [[ -o restricted ]] || [[ ${PROMPT} != *issl_prompt_vcs* && ${RPROMPT} != *issl_prompt_vcs* ]]; then
    issl_prompt_vcs=''
    add-zsh-hook -d precmd issl_prompt_precmd
    return
  fi

  # Keep git in the command hash table, which vcs_info tests to detect git.
  hash git 2> /dev/null

  vcs_info
  # Escape the prompt metacharacters in the VCS information.
  issl_prompt_vcs=${vcs_info_msg_0_}
  if [[ -o prompt_percent ]]; then
    issl_prompt_vcs=${issl_prompt_vcs//\%/%%}
  fi
  if [[ -o prompt_bang ]]; then
    issl_prompt_vcs=${issl_prompt_vcs//\!/!!}
  fi
}
add-zsh-hook precmd issl_prompt_precmd

# ===== Completion ===== #

# Add $ZDOTDIR/functions to fpath for user-managed functions and completions.
issl_zsh_functions_dir="${ZDOTDIR}/functions"
if [ ! -d "${issl_zsh_functions_dir}" ]; then
  mkdir -p "${issl_zsh_functions_dir}" 2> /dev/null || true
fi
if [ -d "${issl_zsh_functions_dir}" ]; then
  fpath=("${issl_zsh_functions_dir}" "${fpath[@]}")
fi

# Make toolchain-provided cargo completion discoverable by compinit.
if command -v rustc > /dev/null 2>&1; then
  issl_rustup_cargo_completion_dir="$(rustc --print sysroot 2> /dev/null)/share/zsh/site-functions"
  if [ -f "${issl_rustup_cargo_completion_dir}/_cargo" ]; then
    fpath=("${issl_rustup_cargo_completion_dir}" "${fpath[@]}")
  fi
fi

# Configure completion styles.
if [ -n "${LS_COLORS:-}" ]; then
  zstyle ':completion:*:default' list-colors "${(@)${(s.:.)LS_COLORS}:#}"
fi
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _oldlist _expand _complete _correct
zstyle ':completion:*' group-name ''
zstyle ':completion:*' ignore-parents parent pwd ..
zstyle ':completion:*' insert-tab false
zstyle ':completion:*' list-dirs-first true
zstyle ':completion:*' list-prompt '%SAt %p: hit TAB for more, or the character to insert%s'
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=2
zstyle ':completion:*' rehash true
zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:corrections' format '%F{green}%d (errors: %e)%f'
zstyle ':completion:*:descriptions' format '%B%F{white}--- %d ---%f%b'
zstyle ':completion:*:messages' format '%F{yellow}%d'
zstyle ':completion:*:options' description 'yes'
zstyle ':completion:*:warnings' format '%F{red}No matches for: %F{white}%d%b'
zstyle ':completion:*:*:git-checkout:*:*' list-colors '=(#b) #([0-9]#)*=0=00;33'
zstyle ':completion:*:*:git-switch:*:*' list-colors '=(#b) #([0-9]#)*=0=00;33'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=00;31'

autoload -Uz compinit
compinit

# Evaluate a generated completion script with the default Zsh options.
issl_eval_completion() {
  emulate -L zsh

  eval "$1"
}

# Enable uv completion when uv is available.
if command -v uv > /dev/null 2>&1; then
  if uv generate-shell-completion zsh > /dev/null 2>&1; then
    issl_eval_completion "$(uv generate-shell-completion zsh)"
  fi
fi

# Enable rustup completion when rustup is available.
if command -v rustup > /dev/null 2>&1; then
  issl_eval_completion "$(rustup completions zsh)"
fi

# ===== Functions and Aliases ===== #

autoload -Uz zmv
alias mmv='noglob zmv -W'
