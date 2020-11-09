#!/usr/bin/env python3
# The main program for making a VAT return.
# The steps are:
# 1. Get the obligations
# 2. Generate the return
# 3. Submit the return

import os, sys, subprocess, json, io
from datetime import datetime

my_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
rest_api = os.environ.get('HMRC_REST_API', None)
if rest_api == None: rest_api = os.path.join(my_dir, 'hmrc-api.py')
hledger_return = os.path.join(my_dir, 'hledger-vat-report.py')

def error(*x):
    print(*x, file=sys.stderr)
    exit(1)

def parse_date(x): return datetime.strptime(x, '%Y-%m-%d')
def show_date(x): return datetime.strftime(x, '%Y-%m-%d')

if len(sys.argv) != 2: error("usage: %s config.json" % sys.argv[0])
config_path, = sys.argv[1:]

obligations = json.loads(subprocess.check_output([rest_api, config_path, 'get-obligations'], input=""))['obligations']

oldest_open = None
for ob in obligations:
    status = ob['status']
    print("OBLIGATION: period {start} to {end} is due on {due} ({status})".format(
        start = ob['start'],
        end = ob['end'],
        due = ob['due'],
        status = ('OPEN' if status == 'O' else 'fulfilled' if status == 'F' else 'UNKNOWN: ' + status)
        ))
    if status == 'O':
        oldest_open = ob

if oldest_open is None:
    error("No open obligations!")

now = datetime.today()
if now <= parse_date(oldest_open['end']):
    print("Oldest open obligation period is not over yet (nothing to do)")
    sys.exit(0)

periodStart = oldest_open['start']
periodEnd = oldest_open['end']
periodKey = oldest_open['periodKey']
print()
sys.stdout.flush()
sys.stderr.flush()

vat_return = json.loads(subprocess.check_output([hledger_return, periodStart, periodEnd]))
assert (vat_return['periodStart'] == periodStart)
assert (vat_return['periodEnd'] == periodEnd)
del vat_return['periodStart']
del vat_return['periodEnd']
vat_return['periodKey'] = periodKey

# Note: HMRC requires that the periodKey not be displayed to the user
censored_copy = vat_return.copy()
censored_copy['periodKey'] = "CENSORED" if vat_return['periodKey'] != "CENSORED" else "HIDDEN"

print(f"\n=== VAT return ({periodStart} to {periodEnd}) ===")
print(json.dumps(censored_copy, indent=2))
print("===")
print("When you submit this VAT information you are making a legal declaration that the information is true and complete.")
print("A false declaration can result in prosecution.")
while True:
    if input("Confirm (enter 'confirm' to continue)") == "confirm": break
vat_return["finalised"] = True

results = subprocess.run([rest_api, config_path, 'submit-return'], check=True, input=json.dumps(vat_return), stdout=subprocess.PIPE, encoding='utf-8')
results = json.loads(results.stdout)

print("Submitted!")
print(json.dumps(results))
