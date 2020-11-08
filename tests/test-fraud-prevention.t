For testing, fix the window size reported in the fraud header:

  $ export THE_WINDOW_SIZE='width=1024&height=768'

Try validating the fraud headers:

  $ "$TESTDIR/../hmrc-api.py" ~/.config/hmrc-vat/test-config.json fraud-prevention > results.json
  Sending fraud headers:
  {
    "Gov-Client-Connection-Method": "DESKTOP_APP_DIRECT",
    "Gov-Client-Device-ID": "*", (glob)
    "Gov-Client-User-IDs": "os=*", (glob)
    "Gov-Client-Timezone": "UTC+00:00", (glob)
    "Gov-Client-Local-IPs": "*", (glob)
    "Gov-Client-MAC-Addresses": "*", (glob)
    "Gov-Client-Screens": "width=*&height=*&scaling-factor=*&colour-depth=*", (glob)
    "Gov-Client-Window-Size": "width=*&height=*", (glob)
    "Gov-Client-User-Agent": "*/* (*/*)", (glob)
    "Gov-Client-Multi-Factor": "",
    "Gov-Vendor-Version": "TomsTaxes=1.0",
    "Gov-Vendor-License-IDs": ""
  }
  Done

  $ jq . < results.json
  {
    "specVersion": "2.x",
    "code": "POTENTIALLY_INVALID_HEADERS",
    "message": "At least 1 header is potentially invalid",
    "warnings": [
      {
        "code": "EMPTY_HEADER",
        "message": "Value is empty. This may be correct for single factor authentication, for example username and password. If this is the case, you must contact us explaining why you cannot submit this header.",
        "headers": [
          "gov-client-multi-factor"
        ]
      },
      {
        "code": "EMPTY_HEADER",
        "message": "Value required",
        "headers": [
          "gov-vendor-license-ids"
        ]
      }
    ]
  }
