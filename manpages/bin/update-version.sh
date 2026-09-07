#!/bin/sh

## live-config(7) - System Configuration Components
## Copyright (C) 2016-2020 The Debian Live team
## Copyright (C) 2006-2015 Daniel Baumann <mail@daniel-baumann.ch>
##
## This program comes with ABSOLUTELY NO WARRANTY; for details see COPYING.
## This is free software, and you are welcome to redistribute it
## under certain conditions; see COPYING for details.


set -e

PROGRAM="LIVE\\\-CONFIG"
VERSION="$(cat ../VERSION)"

DATE="$(LC_ALL=C date +%Y\\\\-%m\\\\-%d)"

echo "Updating version headers..."

for MANPAGE in en/*
do
	SECTION="$(basename ${MANPAGE} | awk -F. '{ print $2 }')"

	sed -i -e "s|^.TH.*$|.TH ${PROGRAM} ${SECTION} ${DATE} ${VERSION} \"MiniOS Live Project\"|" ${MANPAGE}
done
