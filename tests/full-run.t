Do a full run. This includes creation of a test user on the test service.

A bit of setup:

  $ export LC_ALL=C.UTF-8 LANGUAGE=C.UTF-8 LC_ALL=C.UTF-8 COLUMNS=90
  $ export LEDGER_FILE=test.hledger
  $ export THE_WINDOW_SIZE='width=640&height=480'

Create test user on test server:

  $ $TESTDIR/../hmrc-api.py ~/.config/hmrc-vat/test-config.json create-test-user > user.json
  Done

Store the details in a new `config.json`:

  $ export TEST_USER=$(jq .userId user.json)
  $ export TEST_PASSWORD=$(jq .password user.json)
  $ jq '{ client_id, client_secret, endpoint, device_id, device_manufacturer, device_model, vrn: $user[0].vrn }' --slurpfile user user.json \
  > < ~/.config/hmrc-vat/test-config.json > config.json

It doesn't seem possible to log the user in automatically, so instead we open a tab in firefox
showing the test user's ID and password. Enter these when prompted later:

  $ firefox data:,user=$TEST_USER,password=$TEST_PASSWORD

Create the test user's accounts.
Note that the test API always returns results from 2017, even though we ask for the last 12 months'
worth, and the test user wasn't even registered for VAT back then.

  $ cat > test.hledger << EOF
  > 2017-03-31 Invoice 001 to client (just before reporting period)
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > 
  > 2017-04-01 Invoice 002 to client
  >         income:job                      -£200.00  ; VAT:20 (income tax charged on this)
  >         expenses:goods                  -£100.01  ; VAT:20
  >         liabilities:output-vat          -£ 60.00  ; VAT charged on the above
  >         assets:receivable:invoices       £360.01  ; Gross total
  > 
  > 2017-05-01 Unrelated stuff
  >         expenses:toys                     £10.00
  >         assets:bank
  > 
  > 2017-06-30 Invoice 003 to client
  >         income:job                      -£200.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 40.00  ; VAT charged on the above
  >         assets:receivable:invoices       £240.00  ; Gross total
  > 
  > 2017-07-01 Invoice 004 to client (just after reporting period)
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > EOF

Run main.py:

  $ echo confirm | "$TESTDIR/../main.py" config.json
  Will save fraud headers:
  {
    "Gov-Client-Connection-Method": "DESKTOP_APP_DIRECT",
    "Gov-Client-Device-ID": "*", (glob)
    "Gov-Client-User-IDs": "os=*", (glob)
    "Gov-Client-Timezone": "UTC+00:00", (glob)
    "Gov-Client-Screens": "width=*&height=*&scaling-factor=*&colour-depth=*", (glob)
    "Gov-Client-Window-Size": "width=*&height=*", (glob)
    "Gov-Client-User-Agent": "os-family=*&os-version=*&device-manufacturer=*&device-model=*", (glob)
    "Gov-Client-Multi-Factor": "",
    "Gov-Vendor-Product-Name": "TomsTaxes",
    "Gov-Vendor-Version": "TomsTaxes=1.0",
    "Gov-Vendor-License-IDs": ""
  }
  Please go to:
  
  https://test-api.service.hmrc.gov.uk/oauth/authorize* (glob)
  
  Awaiting network connection on port 7000...
  Got connection
  Saving token as hmrc-token.json
  Got obligations for last 12 months (* to *) (glob)
  OBLIGATION: period 2017-01-01 to 2017-03-31 is due on 2017-05-07 (fulfilled)
  OBLIGATION: period 2017-04-01 to 2017-06-30 is due on 2017-08-07 (OPEN)
  
  Data for HMRC date range 2017-04-01 to 2017-06-30 (hledger period '2017-04-01 to 2017-07-01')
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  2017-04-01 Invoice 002 to client     income:job                     £-200.00      £-200.00
                                       expenses:goods                 £-100.01      £-300.01
  2017-06-30 Invoice 003 to client     income:job                     £-200.00      £-500.01
  
  == Output VAT ==
  2017-04-01 Invoice 002 to client     liabilities:output-vat          £-60.00       £-60.00
  2017-06-30 Invoice 003 to client     liabilities:output-vat          £-40.00      £-100.00
  
  == Summary ==
  Total supplies on which we charged VAT: £500.01
  Expected output VAT: £100.00 (based on total supplies)
  Total output VAT: £100.00 (difference = £0.00)
  VAT due on sales: £93.00 (flat-rate of 15.5% on £600.01)
  
  *-*-* VAT return for 2017-04-01 to 2017-06-30 (glob)
          liabilities:output-vat          £   100.00
          liabilities:payable:vat         £   -93.00
          income:vat-flat-rate            £    -7.00
  
  === VAT return (2017-04-01 to 2017-06-30) ===
  {
    "vatDueSales": 93.0,
    "vatDueAcquisitions": 0,
    "totalVatDue": 93.0,
    "vatReclaimedCurrPeriod": 0,
    "netVatDue": 93.0,
    "totalValueSalesExVAT": 600.0,
    "totalValuePurchasesExVAT": 0,
    "totalValueGoodsSuppliedExVAT": 0,
    "totalAcquisitionsExVAT": 0,
    "periodKey": "CENSORED"
  }
  ===
  When you submit this VAT information you are making a legal declaration that the information is true and complete.
  A false declaration can result in prosecution.
  Confirm (enter 'confirm' to continue)Done
  Submitted!
  {"processingDate": "*", "formBundleNumber": "*", *} (glob)
