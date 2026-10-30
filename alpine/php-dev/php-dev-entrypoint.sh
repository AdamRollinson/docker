#!/bin/bash
set -e

# shellcheck source=../base/entrypoint-lib.sh
. /usr/local/lib/entrypoint-lib.sh

# Loads the debugger or coverage driver chosen by PHP_DEBUGGER, then hands over to the php
# entrypoint, so php.ini rendering, php.* overrides, APP_INSTALL, cron and worker mode behave
# exactly as in the php image.
render_debugger || exit 1

exec php-entrypoint.sh "$@"
