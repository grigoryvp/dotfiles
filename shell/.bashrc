#!/usr/bin/env bash
# coding:utf-8 vi:et:ts=2

#  Non-interactive shell?
if ! [ -t 0 ]; then
  return
fi

##  bash/zsh portable way to encode "Escape" character.
PS_ESC=$(printf '\033')
##  Don't show git in PS by default, it conflicts with the "g" alias.
PS_GIT_ON=

if [ -n "$ZSH_VERSION" ]; then
  ##  Colors should be escaped for correct length calculation.
  PS_K="%{${PS_ESC}[30;47m%}"
  PS_W="%{${PS_ESC}[37;49m%}"
  PS_R="%{${PS_ESC}[31;49m%}"
  PS_G="%{${PS_ESC}[32;49m%}"
  PS_B="%{${PS_ESC}[34;49m%}"
  PS_Y="%{${PS_ESC}[33;49m%}"
  PS_M="%{${PS_ESC}[35;49m%}"
  PS_C="%{${PS_ESC}[36;49m%}"
  PS_N="%{${PS_ESC}[0m%}"
  PS_WORKDIR="%~"
  PS_DOLLAR="$"
  ##  Substring re-interpolation.
  setopt promptsubst
  ##  Do not display "no matches found" error for blobs
  setopt +o nomatch
elif [ -n "$BASH_VERSION" ]; then
  ##  Colors should be escaped for correct length calculation.
  PS_K="\\[${PS_ESC}[30;47m\\]"
  PS_W="\\[${PS_ESC}[37;49m\\]"
  PS_R="\\[${PS_ESC}[31;49m\\]"
  PS_G="\\[${PS_ESC}[32;49m\\]"
  PS_B="\\[${PS_ESC}[34;49m\\]"
  PS_Y="\\[${PS_ESC}[33;49m\\]"
  PS_M="\\[${PS_ESC}[35;49m\\]"
  PS_C="\\[${PS_ESC}[36;49m\\]"
  PS_N="\\[${PS_ESC}[0m\\]"
  PS_WORKDIR="\\W"
  PS_DOLLAR="\\\$"
else
  echo "Unsupported shell"
fi

##  Disable terminal/ssh freeze with C-S:
stty -ixon
##  Don't create |.pyc| files while executing python code from console.
export PYTHONDONTWRITEBYTECODE=1
##! Add npm global bin to path before local node_modules so tools that
##  require both global and local installation like react-native can work.
NPM_BIN=$(echo ~/.local/node-*/bin | tail -n1)
if [ -e $NPM_BIN ]; then
  export PATH=$PATH:$NPM_BIN
fi
##* Usefull for npm tools that are not installed globally
export PATH=$PATH:./node_modules/.bin
##  Rust 'install' places binaries here
export PATH=$PATH:~/.cargo/bin
##  For custom nodejs build (ubuntu have old one in repository)
export PATH=$PATH:~/.local/nodejs/bin
##  git can clone from repos without certificates.
export GIT_SSL_NO_VERIFY=true
##  256-colors in terminal for apps that knows how to use it.
export TERM=xterm-256color
##  Used by apps to launch text editor.
export EDITOR=vim
##  Required for VIM, otherwise it will start creating dirs names '$TMP'.
if [ -z $TMP ]; then
  export TMP=~/tmp
fi
if [ -z $TEMP ]; then
  export TEMP=~/tmp
fi
##  gnome-ssh-askpass don't work.
unset SSH_ASKPASS
##  make less display ASCII colors, quit if one screen and don't clear
##  screen after it quits.
export LESS="-R -F -X"
##  Don't display lein root warning while using in docker
export LEIN_ROOT=true

##  No more requred.
# export GOPATH=~/go
# export PATH=$GOPATH/bin:$PATH

##  For docker containers where they are not set
export LANG="en_US.UTF-8"
export LANGUAGE="en_US:en"
export LC_ALL="en_US.UTF-8"

##  Switchable truecolor for VIM, on by default
export TRUECOLOR="1"

##  Always install dependencies in .venv for poetry.
export POETRY_VIRTUALENVS_IN_PROJECT="1"
##  Always install dependencies in .venv for pipenv.
export PIPENV_VENV_IN_PROJECT="1"
##  Do not lock dependencies (very slow).
export PIPENV_SKIP_LOCK="1"

##  OSX?
if [ "$(uname)" = "Darwin" ]; then
  ##  Add color to |ls| output
  export CLICOLOR=1
  ##  Better 'ls' output colors.
  export LSCOLORS=Exfxcxdxbxegedabagacad
  ##  For django 'syncdb' command to work.
  export LC_ALL=en_US.UTF-8
  ##  |PYTHONDONTWRITEBYTECODE| don't work on OSX 10.8, default python is
  ##  64-bit that is not compatible with wxWidgets.
  # alias python="arch -i386 /usr/bin/python2.7 -B"

  ##  custom svn installed?
  if [ -e /opt/subversion/bin ]; then
    export PATH=/opt/subversion/bin:$PATH
  fi

  ##  MacOS Apple Silicon homebrew installed?
  if [ -e /opt/homebrew/bin/brew ]; then
    eval $(/opt/homebrew/bin/brew shellenv)
  fi

  ##  custom mongo installed?
  MONGOAPP=~/Applications/MongoDB.app
  MONGOBINDIR=$MONGOAPP/Contents/Resources/Vendor/mongodb
  if [ -e $MONGOBINDIR/mongo ]; then
    alias mongo=$MONGOBINDIR/mongo
    alias mongodump=$MONGOBINDIR/mongodump
    alias mongorestore=$MONGOBINDIR/mongorestore
  fi

  ##  Will write to stderr if Java is not installed
  export JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null)
  ##  brew install android-sdk
  export ANDROID_HOME=/usr/local/opt/android-sdk
  ##  Installed here by 'brew install michaeldfallen/formula/git-radar'
  if [ "$SHELL" = "/bin/zsh" ]; then
    export RADAR_CMD='$(git-radar --zsh --fetch)'
  else
    export RADAR_CMD='$(git-radar --bash --fetch)'
  fi

  ##  Swift version manager
  if which swiftenv > /dev/null; then
    eval "$(swiftenv init -)"
  fi
else
  ##  Remap caps lock to backspace.
  # gsettings set org.gnome.desktop.input-sources xkb-options "['caps:backspace']"

  ##FIXME: Seems not persisting on Ubuntu, need to check why.
  # setterm -background black -foreground white

  ##  GTK_IM_MODULE is set to 'xim' in ubuntu, lots of GTK errors in chrome.
  ##  Disable disk cache so multiple chrome instances will not kill HDD.
  CHROME_BIN=/opt/google/chrome/chrome
  alias chrome='GTK_IM_MODULE="" $CHROME_BIN --disk-cache-size=10000000'

  ##  android studio installed?
  if [ -e ~/.local/android-studio/bin ]; then
    export PATH=~/.local/android-studio/bin:$PATH
  fi

  if [ -e /usr/java/latest ]; then
    ##  Official SDK symlinks this to lates install.
    export JAVA_HOME=/usr/java/latest
  fi
  
  export RADAR_CMD='$(~/.git-radar/git-radar --bash --fetch)'
fi

if [ -e ~/.rvm/scripts/rvm ]; then
  source ~/.rvm/scripts/rvm
fi

export PATH=$PATH:~/.rvm/bin # Add RVM to PATH for scripting

##  git aliases
alias g=git

##  svn aliases
alias svl='svn log'
alias svs='svn stat'
alias svc='svn commit -m'
svd() {
  svn diff --diff-cmd colordiff $@ | less -R
}

##  "HOST HOME" for Windows "home" on WSL
if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  HHOME=$(wslpath $(cmd.exe /C "echo %USERPROFILE%" 2>/dev/null))
  ##  Remove '\r' from the end of the 'cmd.exe' output
  export HHOME=$(echo $HHOME | tr -d '\r')
else
  export HHOME=~
fi

##  cd aliases for wsl-mac-nix consistency
alias cdh="cd ${HOME}"
alias cdd="cd ${HOME}/Documents"
alias cdx="cd ${HOME}/.xi"
alias cdc="cd ${HHOME}/.box-cfg"
alias cdhh="cd ${HHOME}"

##  Python virtual environment; built-in 'venv' instals old bundled 'pip'.
alias vec="python -m virtualenv .venv"
alias vea=". .venv/bin/activate"
alias ved="deactivate"
alias ver="rm -rf .venv"

alias pon="poetry init --no-interaction"
alias poi="poetry install"
alias poa="poetry add"
alias por="poetry run"
alias pop="poetry run python"
alias pom="poetry run python manage.py"

##  docker aliases
dmg() {
  if [ -z "$1" ]; then
    docker-machine env -u >~/tmp/docker-machine-env
  else
    docker-machine env $1 >~/tmp/docker-machine-env
  fi
  eval $(cat ~/tmp/docker-machine-env)
}
di() {
  echo -n '{{.Name}}' > ~/tmp/di-format
  echo -n ' on {{.OperatingSystem}}' >> ~/tmp/di-format
  echo -n ' running docker {{.ServerVersion}}' >> ~/tmp/di-format
  docker info -f "$(cat ~/tmp/di-format)"
}
alias dsl='docker service ls'
alias dsi='docker service inspect --pretty'

# Always run tox in quiet mode, it spams a lot of useless info by default.
alias tox='tox -q'

# For windows consistensy
alias rmf='rm -rf'

my_list() {
  if [ -e /usr/local/bin/lsd ]; then
    /usr/local/bin/lsd "$@"
  elif [ -e /usr/local/bin/exa ]; then
    /usr/local/bin/exa \
      -l \
      -a \
      --group-directories-first \
      --ignore-glob .DS_Store\|desktop.ini\|PowerShell\|My\ Games \
      "$@"
  else
    ##! No spaces, '*' should be used instead.
    IGNORED=( \
      "WindowsPowerShell" \
      "PowerShell" \
      "desktop.ini" \
      ".vscode" \
    )
    CMD_IGNORE=""
    IGNORED_COUNT=0
    ##  OSX does not support advanced keys
    if [ "$(uname)" != "Darwin" ]; then
      for CUR in "${IGNORED[@]}"; do
        ##! No quotes to match things like "Diablo*"
        if [ -e ${CUR} ]; then
          ((IGNORED_COUNT++))
        fi
        CMD_IGNORE="${CMD_IGNORE} -I ${CUR}"
      done
      LS_ARG_COLOR="--color"
      LS_ARG_GROUP="--group-directories-first"
    fi
    ##  Due to LESS options this will pass-through on one screen.
    ##  -l: One column by default, as in powershell.
    #3  -h: Human-readable sizes.
    ##  -A: Show all files except special '.' and '..'.
    ##  -F: Append indicators.
    ##  --color: Color output for linux (CLICOLOR for OSX).
    ##  --group-directories-first: Show dirs first.
    ##  -I: Ignore files.
    ##  "$@": quote args so "ll Visual\ Studio\ 2015" will work.
    ls \
      -l \
      -h \
      -A \
      -F \
      ${LS_ARG_COLOR} \
      ${LS_ARG_GROUP} \
      ${CMD_IGNORE} \
      "$@" \
      | less
    if ((IGNORED_COUNT > 0)); then
      echo -e "${R}${IGNORED_COUNT} items ignored${N}"
    fi
  fi
}
alias ll=my_list
alias ff=ag

_prompt_command() {
  PS_EXIT="$?"
  export PS1="${PS_N}${PS_W}${PS_WORKDIR} ${PS_N}"
  if [ -n "$PS_GIT_ON" ]; then
    if [ -d ~/.git-radar ] || which git-radar >/dev/null; then
      #! Spaces before optional changes and before next prompt part.
      export GIT_RADAR_FORMAT="git:%{branch}%{local}%{ :changes} "
      export PS1="${PS1}${PS_G}${RADAR_CMD}${PS_N}"
    fi
  fi
  if [ -n "${DOCKER_MACHINE_NAME}" ]; then
    export PS1="${PS1}${PS_M}{${DOCKER_MACHINE_NAME}} ${PS_N}"
  fi
  if [ -n "${VIRTUAL_ENV}" ]; then
    export PS1="${PS1}🐍 "
  fi
  export PS1="${PS1}(${PS_C}${PS_EXIT}${PS_N}) "
  export PS1="${PS1}${PS_Y}${PS_DOLLAR} ${PS_N}"
}
export PROMPT_COMMAND=_prompt_command
# ZSH alternative to "PROMPT_COMMAND"
precmd() {
  eval "$PROMPT_COMMAND"
}

psgiton() {
  export PS_GIT_ON=1
  psupdate
}

psgitoff() {
  export PS_GIT_ON=
  psupdate
}

venv2() {
  if ! [ -d ./.env ]; then
    virtualenv --no-site-packages ./.env
  fi
  source ./.env/bin/activate
}

venv() {
  if ! [ -d ./.env ]; then
    if [ _"$1" != _"" ]; then
      echo "using $1"
      $1 -m venv ./.env
    else
      python3 -m venv ./.env
    fi
  fi
  source ./.env/bin/activate
}

freqdown() {
  sudo cpupower frequency-set --min 2.4Ghz --max 2.4ghz
}

##  Simple HTTP erver in current dir.
srv() {
  if [ _"$1" != _"" ] && [ _"$1" != _"-s" ]; then
    if echo $@ | grep -- -s > /dev/null; then
      (cd $1 && php -S 0.0.0.0:80 >/dev/null 2>/dev/null)
    else
      (cd $1 && php -S 0.0.0.0:80)
    fi
  else
    if echo $@ | grep -- -s > /dev/null; then
      php -S 0.0.0.0:80 >/dev/null 2>/dev/null
    else
      php -S 0.0.0.0:80
    fi
  fi
}

pp() {
  ping -i 0.2 1.1.1.1
}

##  For ~/.install_... to detect if file already sourced.
export BASHRC_LOADED=1

##  Load rbenv, if installed
if [ -d $HOME/.rbenv ]; then
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
fi

##  Load pyenv, if installed
if [ -d $HOME/.pyenv ]; then
  export PATH="$HOME/.pyenv/bin:$PATH"
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"
fi

##  Load nodenv, if installed
if [ -d $HOME/.nodenv ]; then
  export PATH="$HOME/.nodenv/bin:$PATH"
  eval "$(nodenv init -)"
fi
