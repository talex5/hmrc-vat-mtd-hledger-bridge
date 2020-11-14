#!/bin/sh
set -eu
(echo "$1" && echo "$2" && cat) | qrexec-client-vm "$HMRC_API_VM" talex5.VAT
