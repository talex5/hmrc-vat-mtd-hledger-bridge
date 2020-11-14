#!/bin/sh
read CONFIG
read OP
exec python -u $(dirname $0)/../hmrc-api.py "$CONFIG" "$OP"
