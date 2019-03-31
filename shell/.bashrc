#!/usr/bin/env bash
# coding:utf-8 vi:et:ts=2

##  Colors, used by this init script
##  echo -e "${K}K${W}W${R}R${G}G${B}B${Y}Y${M}M${C}C${N}N"
K='\e[30;47m'
W='\e[37;40m'
R='\e[31;40m'
G='\e[32;40m'
B='\e[34;40m'
Y='\e[33;40m'
M='\e[35;40m'
C='\e[36;40m'
N='\033[0m'

##  Bash colors should be escaped for correct length calculation:
BK="\\[${K}\\]"
BW="\\[${W}\\]"
BR="\\[${R}\\]"
BG="\\[${G}\\]"
BB="\\[${B}\\]"
BY="\\[${Y}\\]"
BM="\\[${M}\\]"
BC="\\[${C}\\]"
BN="\\[${N}\\]"

##  Disable terminal/ssh freeze with C-S:
stty -ixon
##  Don't create |.pyc| files while executing python code from console.
export PYTHONDONTWRITEBYTECODE=1
##! Add npm global bin to path before local node_modules so tools that
##  require both global and local installation like react-native can work.
NPM_BIN=$(echo ~/.local/node-*/bin | tail -n1)
if test -e $NPM_BIN; then
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
if test -z $TMP; then
  export TMP=~/tmp
fi
if test -z $TEMP; then
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

export USER="grigoryvp"
##  Switchable truecolor for VIM, on by default
export TRUECOLOR="1"

##  OSX?
if test "$(uname)" = "Darwin"; then
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
  if test -e /opt/subversion/bin; then
    export PATH=/opt/subversion/bin:$PATH
  fi

  ## homebrew tools installed?
  if test -e /usr/local/sbin; then
    export PATH=/usr/local/sbin:$PATH
  fi

  ##  custom mongo installed?
  MONGOAPP=~/Applications/MongoDB.app
  MONGOBINDIR=$MONGOAPP/Contents/Resources/Vendor/mongodb
  if test -e $MONGOBINDIR/mongo; then
    alias mongo=$MONGOBINDIR/mongo
    alias mongodump=$MONGOBINDIR/mongodump
    alias mongorestore=$MONGOBINDIR/mongorestore
  fi

  ##  Will write to stderr if Java is not installed
  export JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null)
  ##  brew install android-sdk
  export ANDROID_HOME=/usr/local/opt/android-sdk
  # Installed here by 'brew install michaeldfallen/formula/git-radar'
  export RADAR_CMD='$(/usr/local/bin/git-radar --bash --fetch)'
  # Swift version manager
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
  if test -e ~/.local/android-studio/bin; then
    export PATH=~/.local/android-studio/bin:$PATH
  fi

  if test -e /usr/java/latest; then
    ##  Official SDK symlinks this to lates install.
    export JAVA_HOME=/usr/java/latest
  fi
  
  export RADAR_CMD='$(~/.git-radar/git-radar --bash --fetch)'
fi

if test -e ~/.rvm/scripts/rvm; then
  source ~/.rvm/scripts/rvm
fi

export PATH=$PATH:~/.rvm/bin # Add RVM to PATH for scripting

##  git aliases
alias gl='git log --color --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
alias ga='git add -N'
alias gb='git branch'
alias gc='git commit -am'
alias gd='git diff --ignore-space-change'
alias gdl='git diff --ignore-space-change --no-index'
alias gdt='git difftool --ignore-space-change'
##  Avoid conflict with 'go' programming language.
alias gg='git checkout'
alias gm='git mv'
##  'git push'
alias gp='git push'
##  'git up'
alias gu='git pull --all'
##  "git status"
gs() {
  echo -e "${G}current branch: ${R}$(git rev-parse --abbrev-ref HEAD)${N}"
  git status -s
}
##  "git all status"
gas() {
  git submodule foreach git status
  git status
}
##  "git all diff"
gad() {
  git submodule foreach git diff
  git diff
}
##  "git all add"
gaa() {
  git submodule foreach git add -N .
  git add -N .
}
##  "git all commit"
gac() {
  git submodule foreach git commit -am "$1"
  git commit -am "$1"
}
##  "git all push"
gap() {
  git submodule foreach git push
  git push
}
##  "git all pull"
gau() {
  git pull
  git submodule update --merge
}

##  svn aliases
alias svl='svn log'
alias svs='svn stat'
alias svc='svn commit -m'
svd() {
  svn diff --diff-cmd colordiff $@ | less -R
}

##  "HOST HOME" for Windows "home" on LSW.
if cat /proc/sys/kernel/osrelease 2>/dev/null | grep -q Microsoft; then
  export HHOME=/mnt/c/Users/user
else
  export HHOME=~
fi

## cd aliases (for consistency with win that don't have ~).
alias cdh="cd ${HOME}"
alias cdhh="cd ${HHOME}"
alias cdd="cd ${HHOME}/Documents"
alias cdp="cd ${HHOME}/Documents/PowerShell"
alias cdx="cd ${HHOME}/.xi"

## docker aliases
dmg() {
  if test -z "$1"; then
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

ll() {
  if test -e ~/.cargo/bin/exa; then
    exa \
      -l \
      -a \
      --group-directories-first \
      --ignore-glob .DS_Store\|desktop.ini\|PowerShell\|My\ Games \
      "$@"
  else
    ##! No spaces, '*' should be used instead.
    IGNORED=( \
      "Adobe" \
      "Anki" \
      "Bayonetta" \
      "WindowsPowerShell" \
      "desktop.ini" \
      "Diablo*" \
    )
    CMD_IGNORE=""
    IGNORED_COUNT=0
    ##  OSX does not support advanced keys
    if test "$(uname)" != "Darwin"; then
      for CUR in "${IGNORED[@]}"; do
        ##! No quotes to match things like "Diablo*"
        if test -e ${CUR}; then
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

psupdate() {
  export GIT_RADAR_FORMAT="git:%{branch}%{local} %{changes}"
  export PS1="${BW}\\W "
  if test -n "$PSGITON"; then
    if test -d ~/.git-radar || test -e /usr/local/bin/git-radar; then
      export PS1="${PS1}${BG}${RADAR_CMD} "
    fi
  fi
  export PS1="${PS1}${BM}{${DOCKER_MACHINE_NAME}} "
  export PS1="${PS1}${BY}\\\$ ${BN}"
}

psgiton() {
  export PSGITON=1
  psupdate
}

psgitoff() {
  export PSGITON=
  psupdate
}

#psupdate
##  Experimental on by default
psgiton

venv2() {
  if ! test -d ./.env; then
    virtualenv --no-site-packages ./.env
  fi
  source ./.env/bin/activate
}

venv() {
  if ! test -d ./.env; then
    if test _"$1" != _""; then
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
  if test _"$1" != _"" && test _"$1" != _"-s"; then
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