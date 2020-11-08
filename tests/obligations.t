For testing, fix the window size reported in the fraud header:

  $ export THE_WINDOW_SIZE='width=640&height=480'

Get the test-user's VAT obligations.
Note that the test API always returns results from 2017, even though we asked for the last 12 months'
worth, and the test user wasn't even registered for VAT back then.

  $ "$TESTDIR/../hmrc-api.py" ~/.config/hmrc-vat/test-config.json get-obligations > obligations.json
  Got obligations for last 12 months (* to *) (glob)

  $ jq . < obligations.json
  {
    "obligations": [
      {
        "periodKey": "18A1",
        "start": "2017-01-01",
        "end": "2017-03-31",
        "due": "2017-05-07",
        "status": "F",
        "received": "2017-05-06"
      },
      {
        "periodKey": "18A2",
        "start": "2017-04-01",
        "end": "2017-06-30",
        "due": "2017-08-07",
        "status": "O"
      }
    ]
  }
