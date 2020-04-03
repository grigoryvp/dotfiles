#!/bin/bash
xkbset mousekeys
xkbcomp ~/.box-cfg/shell/xkb.conf $DISPLAY
