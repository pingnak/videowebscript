#!/bin/sh
set mediapath=/Volumes/media
if "" == "%1" set mediapath=%1
python videowebscript.py %mediapath%\Video %2
python jukeboxscript.py  %mediapath%\Music %2

