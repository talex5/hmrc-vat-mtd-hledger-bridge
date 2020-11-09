# hmrc-vat-mtd-hledger-bridge

This repository contains some scripts I use to submit VAT returns to HMRC via the [MTD REST API][].
The values to report are taken from the [hledger][] accounting software.
These scripts are only intended for my use.
I am not an accountant and have no special expertise in this area.

As VAT returns only happen 4 times a year and I will inevitably have forgotten how it all works by
next time, I'll try to record what I've discovered so far and how it all works for my future self.

## Overview

Some businesses are required to register for VAT, which requires:

- Charging clients VAT (usually 20%) on sales ("supplies").
- Making regular VAT returns (typically 4 times a year).

The process is:

1. Find out the period covered by the next return.
2. Generate the return.
3. Submit the return.

This process is implemented by `main.py`, which calls other scripts to do the work.
These can be run manually to check everything is working before running the automated
script for the actual submission.

## Integration with hledger

A typical ledger file recording the invoices might look like this:

```ledger
2020-07-01 Invoice 001 to client
        income:job                      -£100.00  ; VAT:20 (income tax charged on this)
        liabilities:output-vat          -£ 20.00  ; VAT charged on the above
        assets:receivable:invoices       £120.00  ; Gross total

2020-09-30 Invoice 002 to client
        income:job                      -£200.00  ; VAT:20 (income tax charged on this)
	expenses:goods			-£100.01  ; VAT:20 (not profit for income tax)
        liabilities:output-vat          -£ 60.00  ; VAT charged on the above
        assets:receivable:invoices       £360.01  ; Gross total
```

The date is the *Tax point*, which can be either the invoice date or the end of the period being invoiced.
Every supply on which we charged VAT is tagged as `VAT:20`.
Each quarter we need to generate a VAT return from this data.

In the simplest case (the [flat-rate scheme][]), you charge 20% VAT on sales ("supplies") but
pay a slightly smaller amount to HMRC.
However, you can't claim back VAT on purchases (the lower rate accounts for this).

The `hledger-vat-report.py` script takes an HMRC date range (note: HMRC end dates are inclusive, unlike hledger end dates),
prints out a summary of what it did, and then produces a JSON document with the final results.
Testing on the example data above:

```
$ env LEDGER_FILE=example.hledger ./hledger-vat-report.py 2020-07-01 2020-09-30 > vat-return.json
Data for HMRC date range 2020-07-01 to 2020-09-30 (hledger period '2020-07-01 to 2020-10-01')
(flat-rate bonus applied; ends 2021-07-01)

== Supplies ==
2020/07/01 Invoice 001 to client     income:job                     £-100.00      £-100.00
2020/09/30 Invoice 002 to client     income:job                     £-200.00      £-300.00
                                     expenses:goods                 £-100.01      £-400.01

== Output VAT ==
2020/07/01 Invoice 001 to client     liabilities:output-vat          £-20.00       £-20.00
2020/09/30 Invoice 002 to client     liabilities:output-vat          £-60.00       £-80.00

== Summary ==
Total supplies on which we charged VAT: £400.01
Expected output VAT: £80.00 (based on total supplies)
Total output VAT: £80.00 (difference = £0.00)
VAT due on sales: £74.40 (flat-rate of 15.5% on £480.01)
```

On success, it will produce a JSON document:

```json
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
```

These numbers should match what you'd get from following the instructions at [VAT Notice 700/12][vat-form].
Note that for the flat-rate scheme, `totalValueSalesExVAT` ("box 6") is actually inclusive of VAT!!

> Box 6 total value of sales  
> Enter the turnover that you applied your flat rate percentage to, including VAT.

Note also that this field is an integer, so the value is rounded to the nearest pound.

This JSON document matches the format expected by the REST API, except that it gives the period
explicitly (instead of using the period key) and doesn't have the confirmation set yet.

There are some more examples in [tests/extraction.t](./tests/extraction.t), which can be run as a `cram3` test-case.
However, you need to use the supplied [tests/cram3-utf8](./tests/cram3-utf8) executable for this as the upstream one
doesn't support UTF-8 and so can't handle the `£` sign!

## Using the REST API

The `hmrc-api.py` file can be used to interact with the REST service.

Before starting, go to [developer.service.hmrc.gov.uk][add-app] to create a new application:
- Get the `client_id` and `client_secret` values from there.
- Add `http://localhost:7000` to the list of `Redirect URIs`.

To test this, [create a test user][].
This will produce a test `vrn` (VAT registration number) and a new user ID and password.
Enter those credentials in the test server when running the tests.

Create a configuration file with the various settings, e.g. save this as `test-config.json`:

```json
{
	"endpoint": "https://test-api.service.hmrc.gov.uk/",
	"client_id": "IIIIIIIIIIIIIIIIIIIIIIIIIIII",
	"client_secret": "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
	"vrn": "DDDDDDDDD",
	"device_id": "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
	"device_manufacturer": "ACME",
	"device_model": "123"
}
```

- `endpoint` should initially be set to the test endpoint, as shown.
- `client_id` and `client_secret` from creating the app.
- `vrn` is the value for the test user created above.
- `device_id` is a unique ID for the device (generate one with `python -c 'import uuid; print(uuid.uuid4())'`).
- `device_manufacturer` and `device_model` are for the [fraud prevention headers][].

With this, we can query for the test-user's VAT obligations.

```
$ ./hmrc-api.py test-config.json get-obligations > obligations.json
Please select "the window on the originating device" (size needed for fraud headers)
The web browser used to log in is probably a good choice.
Will save fraud headers:
{
  "Gov-Client-Connection-Method": "DESKTOP_APP_DIRECT",
  "Gov-Client-Device-ID": "...",
  "Gov-Client-User-IDs": "os=...",
  "Gov-Client-Timezone": "UTC+00:00",
  "Gov-Client-Local-IPs": "...",
  "Gov-Client-MAC-Addresses": "...",
  "Gov-Client-Screens": "width=...&height=...&scaling-factor=...&colour-depth=...",
  "Gov-Client-Window-Size": "width=...&height=...",
  "Gov-Client-User-Agent": "Linux/... (.../...)",
  "Gov-Client-Multi-Factor": "",
  "Gov-Vendor-Version": "TomsTaxes=1.0",
  "Gov-Vendor-License-IDs": ""
}
Please go to:

https://test-api.service.hmrc.gov.uk/oauth/authorize?response_type=code&client_id=...&redirect_uri=http%3A%2F%2Flocalhost%3A7000&scope=read%3Avat+write%3Avat&state=...

Awaiting network connection on port 7000...
Got connection
Saving token as hmrc-token.json
Got obligations for last 12 months (2019-11-11 to 2020-11-09)
```

Note that HMRC requires all kinds of private information to be sent in the fraud headers:
- Although the program shouldn't depend on the OS, it does require Linux in order to get the network configuration details.
- Although the program isn't a windowed application, it does depend on X in order to report e.g. the screen size,
  colour depth, scale factor, etc. It will also prompt you to click on Firefox so it can report the window size.

There is a transcript of a session in [tests/obligations.t](./tests/obligations.t), which can be run as a `cram3` test-case.

### Doing a test run

You can make a test run like this:

```
$ env LEDGER_FILE=example.hledger ./main.py test-config.json
Got obligations for last 12 months (2019-11-11 to 2020-11-09)
OBLIGATION: period 2017-01-01 to 2017-03-31 is due on 2017-05-07 (fulfilled)
OBLIGATION: period 2017-04-01 to 2017-06-30 is due on 2017-08-07 (OPEN)

Data for HMRC date range 2017-04-01 to 2017-06-30 (hledger period '2017-04-01 to 2017-07-01')
...
=== VAT return (2017-04-01 to 2017-06-30) ===
{
  "vatDueSales": 18.6,
  "vatDueAcquisitions": 0,
  "totalVatDue": 18.6,
  "vatReclaimedCurrPeriod": 0,
  "netVatDue": 18.6,
  "totalValueSalesExVAT": 120.0,
  "totalValuePurchasesExVAT": 0,
  "totalValueGoodsSuppliedExVAT": 0,
  "totalAcquisitionsExVAT": 0,
  "periodKey": "CENSORED"
}
===
When you submit this VAT information you are making a legal declaration that the information is true and complete.
A false declaration can result in prosecution.
Confirm (enter 'confirm' to continue)
```

Note that although we ask for obligations in the current year, the test server always returns data from 2017.
Also, once you've submitted the return it won't let you do it again.
But it will continue to list the test obligation as open.

There is a transcript of a session in [tests/full-run.t](./tests/full-run.t), which can be run as a `cram3` test-case.
That script creates a new test-user each time (it opens an extra Firefox tab with the new username and password).

### Making the real return

We need to get the app approved for production use, which requires hitting both endpoints 10 times.
Since the obligations one always returns the same data, this isn't very exciting.
However, you do get a different test user each time, so the payment details can vary.


[hledger]: https://hledger.org/
[flat-rate scheme]: https://www.gov.uk/vat-flat-rate-scheme
[vat-form]: https://www.gov.uk/guidance/how-to-fill-in-and-submit-your-vat-return-vat-notice-70012
[MTD REST API]: https://developer.service.hmrc.gov.uk/api-documentation/docs/api/service/vat-api/1.0
[add-app]: https://developer.service.hmrc.gov.uk/developer/applications
[create a test user]: https://developer.service.hmrc.gov.uk/api-test-user
[fraud prevention headers]: https://developer.service.hmrc.gov.uk/guides/fraud-prevention/connection-method/desktop-app-direct/
