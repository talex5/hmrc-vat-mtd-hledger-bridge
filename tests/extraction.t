vim: set expandtab

Set up cram environment:

  $ export PATH="$TESTDIR:$PATH"

Check the example file:

  $ get-report 2020-07-01 2020-09-30 > report.json < $TESTDIR/../example.hledger
  Data for HMRC date range 2020-07-01 to 2020-09-30 (hledger period '2020-07-01 to 2020-10-01')
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  2020-07-01 Invoice 001 to client     income:job                     £-100.00      £-100.00
  2020-09-30 Invoice 002 to client     income:job                     £-200.00      £-300.00
                                       expenses:goods                 £-100.01      £-400.01
  
  == Output VAT ==
  2020-07-01 Invoice 001 to client     liabilities:output-vat          £-20.00       £-20.00
  2020-09-30 Invoice 002 to client     liabilities:output-vat          £-60.00       £-80.00
  
  == Summary ==
  Total supplies on which we charged VAT: £400.01
  Expected output VAT: £80.00 (based on total supplies)
  Total output VAT: £80.00 (difference = £0.00)
  VAT due on sales: £74.40 (flat-rate of 15.5% on £480.01)
  
  2020-12-05 VAT return for 2020-07-01 to 2020-09-30
          liabilities:output-vat          £    80.00
          liabilities:payable:vat         £   -74.40
          income:vat-flat-rate            £    -5.60

  $ jq . < report.json
  {
    "periodStart": "2020-07-01",
    "periodEnd": "2020-09-30",
    "vatDueSales": 74.4,
    "vatDueAcquisitions": 0,
    "totalVatDue": 74.4,
    "vatReclaimedCurrPeriod": 0,
    "netVatDue": 74.4,
    "totalValueSalesExVAT": 480,
    "totalValuePurchasesExVAT": 0,
    "totalValueGoodsSuppliedExVAT": 0,
    "totalAcquisitionsExVAT": 0
  }

Forgot to tag something as VAT:

  $ get-report 2020-07-01 2020-09-30 << EOF
  > 2020-07-01 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > 
  > 2020-09-30 Invoice 002 to client
  >         income:job                      -£200.00  ; VAT:20 (income tax charged on this)
  >         expenses:goods                  -£100.01  ; Missing VAT tag
  >         liabilities:output-vat          -£ 60.00  ; VAT charged on the above
  >         assets:receivable:invoices       £360.01  ; Gross total
  > EOF
  Data for HMRC date range 2020-07-01 to 2020-09-30 (hledger period '2020-07-01 to 2020-10-01')
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  2020-07-01 Invoice 001 to client     income:job                     £-100.00      £-100.00
  2020-09-30 Invoice 002 to client     income:job                     £-200.00      £-300.00
  
  == Output VAT ==
  2020-07-01 Invoice 001 to client     liabilities:output-vat          £-20.00       £-20.00
  2020-09-30 Invoice 002 to client     liabilities:output-vat          £-60.00       £-80.00
  
  == Summary ==
  Total supplies on which we charged VAT: £300.00
  Expected output VAT: £60.00 (based on total supplies)
  Total output VAT: £80.00 (difference = £20.00)
  WARNING: Surprisingly large effect of rounding - missing VAT somewhere?
  VAT due on sales: £58.90 (flat-rate of 15.5% on £380.00)
  
  2020-12-05 VAT return for 2020-07-01 to 2020-09-30
          liabilities:output-vat          £    80.00
          liabilities:payable:vat         £   -58.90
          income:vat-flat-rate            £   -21.10
  Warnings issued. Not writing report.
  [1]

Forgot to charge VAT:

  $ get-report 2020-07-01 2020-09-30 << EOF
  > 2020-07-01 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         assets:receivable:invoices       £100.00  ; Gross total
  > 
  > 2020-08-01 Invoice 002 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > EOF
  Data for HMRC date range 2020-07-01 to 2020-09-30 (hledger period '2020-07-01 to 2020-10-01')
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  2020-07-01 Invoice 001 to client     income:job                     £-100.00      £-100.00
  2020-08-01 Invoice 002 to client     income:job                     £-100.00      £-200.00
  
  == Output VAT ==
  2020-08-01 Invoice 002 to client     liabilities:output-vat          £-20.00       £-20.00
  
  == Summary ==
  Total supplies on which we charged VAT: £200.00
  Expected output VAT: £40.00 (based on total supplies)
  Total output VAT: £20.00 (difference = £-20.00)
  WARNING: Surprisingly large effect of rounding - missing VAT somewhere?
  VAT due on sales: £34.10 (flat-rate of 15.5% on £220.00)
  
  2020-12-05 VAT return for 2020-07-01 to 2020-09-30
          liabilities:output-vat          £    20.00
          liabilities:payable:vat         £   -34.10
          income:vat-flat-rate            £    14.10
  Warnings issued. Not writing report.
  [1]

No reports found (excludes items before start date and after end date):

  $ get-report 2020-04-01 2020-06-30 << EOF
  > 2020-03-31 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         assets:receivable:invoices       £100.00  ; Gross total
  > 
  > 2020-07-01 Invoice 002 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         assets:receivable:invoices       £100.00  ; Gross total
  > EOF
  Data for HMRC date range 2020-04-01 to 2020-06-30 (hledger period '2020-04-01 to 2020-07-01')
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  WARNING: No VAT supplies found in period!
  
  == Output VAT ==
  WARNING: No VAT reports found in period!
  
  == Summary ==
  Total supplies on which we charged VAT: £0.00
  Expected output VAT: £0.00 (based on total supplies)
  Total output VAT: £0.00 (difference = £0.00)
  VAT due on sales: £0.00 (flat-rate of 15.5% on £0.00)
  
  2020-12-05 VAT return for 2020-04-01 to 2020-06-30
          liabilities:output-vat          £     0.00
          liabilities:payable:vat         £     0.00
          income:vat-flat-rate            £     0.00
  Warnings issued. Not writing report.
  [1]

Invalid period:

  $ get-report 2020-04-01 2020-03-31 << EOF
  > 2020-07-01 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         assets:receivable:invoices       £100.00  ; Gross total
  > EOF
  Data for HMRC date range 2020-04-01 to 2020-03-31 (hledger period '2020-04-01 to 2020-04-01')
  Invalid period!
  [1]

Not month-aligned:

  $ get-report 2020-07-02 2020-09-30 << EOF
  > 2020-07-01 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > 
  > 2020-09-30 Invoice 002 to client
  >         income:job                      -£200.00  ; VAT:20 (income tax charged on this)
  >         expenses:goods                     -£100.01  ; VAT:20 (not profit for income tax)
  >         liabilities:output-vat          -£ 60.00  ; VAT charged on the above
  >         assets:receivable:invoices       £360.01  ; Gross total
  > EOF
  Data for HMRC date range 2020-07-02 to 2020-09-30 (hledger period '2020-07-02 to 2020-10-01')
  WARNING: Period start is not the start of a month!
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  2020-09-30 Invoice 002 to client     income:job                     £-200.00      £-200.00
                                       expenses:goods                 £-100.01      £-300.01
  
  == Output VAT ==
  2020-09-30 Invoice 002 to client     liabilities:output-vat          £-60.00       £-60.00
  
  == Summary ==
  Total supplies on which we charged VAT: £300.01
  Expected output VAT: £60.00 (based on total supplies)
  Total output VAT: £60.00 (difference = £0.00)
  VAT due on sales: £55.80 (flat-rate of 15.5% on £360.01)
  
  2020-12-05 VAT return for 2020-07-02 to 2020-09-30
          liabilities:output-vat          £    60.00
          liabilities:payable:vat         £   -55.80
          income:vat-flat-rate            £    -4.20
  Warnings issued. Not writing report.
  [1]

Doesn't end with month:

  $ get-report 2020-01-01 2020-02-28 << EOF
  > 2020-07-01 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > EOF
  Data for HMRC date range 2020-01-01 to 2020-02-28 (hledger period '2020-01-01 to 2020-02-29')
  WARNING: Period end is not the end of a month!
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  WARNING: No VAT supplies found in period!
  
  == Output VAT ==
  WARNING: No VAT reports found in period!
  
  == Summary ==
  Total supplies on which we charged VAT: £0.00
  Expected output VAT: £0.00 (based on total supplies)
  Total output VAT: £0.00 (difference = £0.00)
  VAT due on sales: £0.00 (flat-rate of 15.5% on £0.00)
  
  2020-12-05 VAT return for 2020-01-01 to 2020-02-28
          liabilities:output-vat          £     0.00
          liabilities:payable:vat         £     0.00
          income:vat-flat-rate            £     0.00
  Warnings issued. Not writing report.
  [1]

Invalid VAT rate:

  $ get-report 2020-07-01 2020-09-30 << EOF
  > 2020-07-01 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:19 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > EOF
  Data for HMRC date range 2020-07-01 to 2020-09-30 (hledger period '2020-07-01 to 2020-10-01')
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  WARNING: No VAT supplies found in period!
  
  == Output VAT ==
  2020-07-01 Invoice 001 to client     liabilities:output-vat          £-20.00       £-20.00
  
  == Summary ==
  2020-07-01 Invoice 001 to client     income:job                     £-100.00      £-100.00
  Some items not at 20% VAT!!
  [1]

Bonus period ends:

  $ get-report 2021-07-01 2021-09-30 2>&1 << EOF \
  > | grep -v 'WARNING: Period has not yet ended - report is incomplete'
  > 2021-07-01 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > 
  > 2021-09-30 Invoice 002 to client
  >         income:job                      -£200.00  ; VAT:20 (income tax charged on this)
  >         expenses:goods                  -£100.01  ; VAT:20 (not profit for income tax)
  >         liabilities:output-vat          -£ 60.00  ; VAT charged on the above
  >         assets:receivable:invoices       £360.01  ; Gross total
  > EOF
  Data for HMRC date range 2021-07-01 to 2021-09-30 (hledger period '2021-07-01 to 2021-10-01')
  (flat-rate bonus period has ended)
  
  == Supplies ==
  2021-07-01 Invoice 001 to client     income:job                     £-100.00      £-100.00
  2021-09-30 Invoice 002 to client     income:job                     £-200.00      £-300.00
                                       expenses:goods                 £-100.01      £-400.01
  
  == Output VAT ==
  2021-07-01 Invoice 001 to client     liabilities:output-vat          £-20.00       £-20.00
  2021-09-30 Invoice 002 to client     liabilities:output-vat          £-60.00       £-80.00
  
  == Summary ==
  Total supplies on which we charged VAT: £400.01
  Expected output VAT: £80.00 (based on total supplies)
  Total output VAT: £80.00 (difference = £0.00)
  VAT due on sales: £79.20 (flat-rate of 16.5% on £480.01)
  
  2020-12-05 VAT return for 2021-07-01 to 2021-09-30
          liabilities:output-vat          £    80.00
          liabilities:payable:vat         £   -79.20
          income:vat-flat-rate            £    -0.80
  Warnings issued. Not writing report.

Invalid bonus period:

  $ get-report 2021-06-01 2021-09-30 2>&1 << EOF \
  > | grep -v 'WARNING: Period has not yet ended - report is incomplete'
  > 2021-07-01 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > EOF
  Data for HMRC date range 2021-06-01 to 2021-09-30 (hledger period '2021-06-01 to 2021-10-01')
  Flat-rate ended during the period!

Rounding errors:

  $ get-report 2020-07-01 2020-09-30 << EOF > report.json
  > 2020-07-01 Invoice 001 to client
  >         income:job                      -£100.02  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.02  ; Gross total
  > 
  > 2020-08-01 Invoice 002 to client
  >         income:job                      -£100.02  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.02  ; Gross total
  > EOF
  Data for HMRC date range 2020-07-01 to 2020-09-30 (hledger period '2020-07-01 to 2020-10-01')
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  2020-07-01 Invoice 001 to client     income:job                     £-100.02      £-100.02
  2020-08-01 Invoice 002 to client     income:job                     £-100.02      £-200.04
  
  == Output VAT ==
  2020-07-01 Invoice 001 to client     liabilities:output-vat          £-20.00       £-20.00
  2020-08-01 Invoice 002 to client     liabilities:output-vat          £-20.00       £-40.00
  
  == Summary ==
  Total supplies on which we charged VAT: £200.04
  Expected output VAT: £40.01 (based on total supplies)
  Total output VAT: £40.00 (difference = £-0.01)
  VAT due on sales: £37.21 (flat-rate of 15.5% on £240.04)
  
  2020-12-05 VAT return for 2020-07-01 to 2020-09-30
          liabilities:output-vat          £    40.00
          liabilities:payable:vat         £   -37.21
          income:vat-flat-rate            £    -2.79

  $ jq . < report.json
  {
    "periodStart": "2020-07-01",
    "periodEnd": "2020-09-30",
    "vatDueSales": 37.21,
    "vatDueAcquisitions": 0,
    "totalVatDue": 37.21,
    "vatReclaimedCurrPeriod": 0,
    "netVatDue": 37.21,
    "totalValueSalesExVAT": 240,
    "totalValuePurchasesExVAT": 0,
    "totalValueGoodsSuppliedExVAT": 0,
    "totalAcquisitionsExVAT": 0
  }

Ignore VAT returns:

  $ get-report 2020-07-01 2020-09-30 << EOF >/dev/null
  > 2020-06-01 Invoice 000 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > 
  > 2020-07-01 Invoice 001 to client
  >         income:job                      -£100.00  ; VAT:20 (income tax charged on this)
  >         liabilities:output-vat          -£ 20.00  ; VAT charged on the above
  >         assets:receivable:invoices       £120.00  ; Gross total
  > 
  > 2020-08-01 Submit VAT return
  >         liabilities:output-vat           £ 20.00  ; Move to payable
  >         liabilities:payable:vat          £-20.00
  > 
  > 2020-09-30 Invoice 002 to client
  >         income:job                      -£200.00  ; VAT:20 (income tax charged on this)
  >         expenses:goods                  -£100.01  ; VAT:20 (not profit for income tax)
  >         liabilities:output-vat          -£ 60.00  ; VAT charged on the above
  >         assets:receivable:invoices       £360.01  ; Gross total
  > EOF
  Data for HMRC date range 2020-07-01 to 2020-09-30 (hledger period '2020-07-01 to 2020-10-01')
  (flat-rate bonus applied; ends 2021-07-01)
  
  == Supplies ==
  2020-07-01 Invoice 001 to client     income:job                     £-100.00      £-100.00
  2020-09-30 Invoice 002 to client     income:job                     £-200.00      £-300.00
                                       expenses:goods                 £-100.01      £-400.01
  
  == Output VAT ==
  2020-07-01 Invoice 001 to client     liabilities:output-vat          £-20.00       £-20.00
  2020-09-30 Invoice 002 to client     liabilities:output-vat          £-60.00       £-80.00
  
  == Summary ==
  Total supplies on which we charged VAT: £400.01
  Expected output VAT: £80.00 (based on total supplies)
  Total output VAT: £80.00 (difference = £0.00)
  VAT due on sales: £74.40 (flat-rate of 15.5% on £480.01)
  
  2020-12-05 VAT return for 2020-07-01 to 2020-09-30
          liabilities:output-vat          £    80.00
          liabilities:payable:vat         £   -74.40
          income:vat-flat-rate            £    -5.60
