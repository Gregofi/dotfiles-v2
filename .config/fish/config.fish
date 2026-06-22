export EDITOR=nvim

bind \cj accept-autosuggestion

# if status is-interactive
# # Commands to run in interactive sessions can go here
# end

# aliases
# working with .dotfiles
alias hgit="git --git-dir=$HOME/.dotfiles --work-tree=$HOME"

alias n="nvim"
alias d="docker"
alias pac="pacman"
alias dc="docker compose"
alias p="pnpm"
alias px="pnpm exec"

alias gav="git add -v"
alias gcn!="git commit --amend --no-edit"
alias gpsup="git push"
alias gpsupf="git push --force-with-lease"
alias gco="git checkout"
alias gcm="git commit"
alias grhh="git reset --hard"

alias k=kubectl

alias src="source ~/.zshrc"

alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."

# pnpm
set -gx PNPM_HOME "/home/gregofi/.local/share/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

export PATH="$HOME/.local/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"

# opencode
fish_add_path /home/gregofi/.opencode/bin

# atuin
# if status is-interactive
#     atuin init fish | source
# end
