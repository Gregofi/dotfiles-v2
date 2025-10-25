# Lines configured by zsh-newuser-install
EDITOR=nvim
HISTFILE=~/.histfile
HISTSIZE=10000
SAVEHIST=10000

autoload -Uz vcs_info

zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' unstagedstr '%F{red}✗%f'
zstyle ':vcs_info:git:*' stagedstr '%F{yellow}●%f'
zstyle ':vcs_info:git:*' formats '(%b %u%c)'
# when rebase/merge/cherrypick.. is in progress
zstyle ':vcs_info:git:*' actionformats '(%b|%a %u%c)'
zstyle ':vcs_info:*' enable git

precmd() { vcs_info }
setopt prompt_subst

PROMPT='%F{yellow}%~%f %F{magenta}${vcs_info_msg_0_}%f '
RPROMPT='%(?..%F{red}%?%f) %F{blue}%*%f'

setopt autocd
unsetopt beep
bindkey -v
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word
bindkey  "^[[H"   beginning-of-line
bindkey  "^[[F"   end-of-line
bindkey  "^[[3~"  delete-char

zstyle :compinstall filename '/home/gregofi/.zshrc'

autoload -Uz compinit
compinit

# prefix history

FUZZY_HIST_IDX=$(( $HISTSIZE - 1 ))
FUZZY_HIST_LAST=""
FUZZY_SEARCH_FOR=""

fuzzy_hist_search() {
    if [[ $BUFFER != $FUZZY_HIST_LAST ]]; then
        FUZZY_SEARCH_FOR=$BUFFER
        FUZZY_HIST_IDX=$HISTSIZE
    fi

    # todo: this will always return, even if idx is out of bounds
    local next=$(grep -E --line-number "$FUZZY_SEARCH_FOR" $HISTFILE | head -n $FUZZY_HIST_IDX)
    if [[ -z $next ]]; then
        return
    fi

    FUZZY_HIST_IDX=$(( $(echo $next | wc -l) - 1 ))
    FUZZY_HIST_LAST=$(echo $next | tail -n 1 | cut -d: -f2-)

    BUFFER=${FUZZY_HIST_LAST}
    CURSOR=${#BUFFER}
    zle redisplay
}

zle -N fuzzy_hist_search
bindkey '^J' fuzzy_hist_search

# aliases
# working with .dotfiles
alias hgit="git --git-dir=${HOME}/.dotfiles --work-tree=$HOME"

alias n=nvim
alias d=docker
alias p=pacman
alias dc=docker compose

alias g=git
alias gav=git add -v
alias gcn!=git commit --amend --no-edit
alias gpsup=git push
alias gpsupf=git push --force-with-lease
alias gco=git checkout
alias gcm=git commit

alias k=kubectl
