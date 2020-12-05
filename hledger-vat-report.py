#!/usr/bin/env python3
import subprocess, sys, csv, io, decimal, json
from datetime import datetime, timedelta
from dateutil import relativedelta
D = decimal.Decimal

vat_rate = 20
flat_rate_without_bonus = 16.5          # Excluding first year bonus
flat_rate_bonus = 1
flat_rate_bonus_end_date = '2021-07-01' # First period start when bonus doesn't apply

warnings = 0
def note(x, *args): print(x, *args, file=sys.stderr)
def warn(x, *args):
    global warnings
    note('WARNING: ' + x, *args)
    warnings += 1
def error(x, *args):
    print(x, *args, file=sys.stderr)
    exit(1)

if len(sys.argv) != 3:
    note("Usage: %s START-INCLUSIVE END-INCLUSIVE" % sys.argv[0])
    note("e.g. %s 2020-07-01 2020-09-30" % sys.argv[0])
    exit(1)
periodStart, periodEndInclusive = sys.argv[1:]

def parse_date(x): return datetime.strptime(x, '%Y-%m-%d')
def show_date(x): return datetime.strftime(x, '%Y-%m-%d')

period_start = parse_date(periodStart)
period_end_excl = parse_date(periodEndInclusive) + timedelta(days=+1)
period = '{} to {}'.format(show_date(period_start), show_date(period_end_excl))
note("Data for HMRC date range %s to %s (hledger period '%s')" % (periodStart, periodEndInclusive, period))

if period_start >= period_end_excl:
    error('Invalid period!')
if datetime.today() < period_end_excl:
    warn('Period has not yet ended - report is incomplete')
if period_start.day != 1:
    warn('Period start is not the start of a month!')
if period_end_excl.day != 1:
    warn('Period end is not the end of a month!')

flat_rate_bonus_end_date = parse_date(flat_rate_bonus_end_date)
if period_start >= flat_rate_bonus_end_date:
    note("(flat-rate bonus period has ended)")
    flat_rate = flat_rate_without_bonus
elif period_end_excl >= flat_rate_bonus_end_date:
    error('Flat-rate ended during the period!')
else:
    note("(flat-rate bonus applied; ends %s)" % show_date(flat_rate_bonus_end_date))
    flat_rate = flat_rate_without_bonus - flat_rate_bonus

def money(x): return D(x.strip('£').replace(',', ''))

# https://www.gov.uk/hmrc-internal-manuals/vat-trader-records/vatrec12030
def round_to_pence(x): return x.quantize(D('1.00'), rounding = decimal.ROUND_HALF_UP)
assert round_to_pence(D('1.004')) == D('1.00')
assert round_to_pence(D('1.005')) == D('1.01')

# Presumably rounded the same way as for pence.
def round_to_pound(x): return x.quantize(D('1'), rounding = decimal.ROUND_HALF_UP).to_integral_exact()
assert round_to_pound(D('1.4')) == D('1')
assert round_to_pound(D('1.5')) == D('2')

# Run "hledger $args" twice; once with human-readable output to the console, and
# once to get CSV output as a dictionary.
def hledger(args):
    sys.stderr.flush()
    subprocess.check_call(["hledger"] + args, stdout = sys.stderr)
    vat_csv = subprocess.check_output(["hledger"] + args + ["-O", "csv"], encoding = 'utf-8')
    with io.StringIO(vat_csv) as f:
        data = list(csv.DictReader(f))
    return data

note("\n== Supplies ==")
supplies = hledger(["r", "-p", period, "tag:VAT=%s" % vat_rate])
if supplies:
    total_supplies_excl_vat = -money(supplies[-1]['total'])
else:
    total_supplies_excl_vat = D('0.00')
    warn('No VAT supplies found in period!')

note("\n== Output VAT ==")
vat_charged = hledger(["r", "-p", period, "liabilities:output-vat", "amt:<0"])
if vat_charged:
    total_output_vat = -money(vat_charged[-1]['total'])
else:
    total_output_vat = D('0.00')
    warn('No VAT reports found in period!')

# This just used as a sanity check that we counted everything, calculating the VAT due on the
# final total, rather than the total of the VAT we actually charged (which may differ due to rounding):
expected_output_vat = round_to_pence(total_supplies_excl_vat * D(vat_rate) / 100)

note("\n== Summary ==")
odd_supplies = hledger(["r", "-p", period, "tag:VAT", "not:tag:VAT=%s" % vat_rate])
if odd_supplies:
    note("Some items not at %s%% VAT!!" % vat_rate)
    exit(1)

note("Total supplies on which we charged VAT: £%s" % total_supplies_excl_vat)
note("Expected output VAT: £%s (based on total supplies)" % expected_output_vat)
difference_due_to_rounding = total_output_vat - expected_output_vat
note("Total output VAT: £%s (difference = £%s)" % (total_output_vat, difference_due_to_rounding))
if abs(difference_due_to_rounding) > D('0.10'):
    warn('Surprisingly large effect of rounding - missing VAT somewhere?')

# Enter the turnover that you applied your flat rate percentage to, including VAT.
totalValueSalesIncludingVAT = total_supplies_excl_vat + total_output_vat

# To calculate the VAT due under the Flat Rate Scheme, you must apply the flat
# rate percentage for your trade sector to the total of all your supplies,
# including VAT.
vatDueSales = round_to_pence(totalValueSalesIncludingVAT * D(flat_rate) / 100)
note("VAT due on sales: £%s (flat-rate of %s%% on £%s)" % (vatDueSales, flat_rate, totalValueSalesIncludingVAT))

vatDueAcquisitions = 0
totalVatDue = vatDueSales + vatDueAcquisitions          # Always just this sum

# If you use the Flat Rate Scheme you do not normally make a separate claim for input VAT.
vatReclaimedCurrPeriod = 0

netVatDue = abs(totalVatDue - vatReclaimedCurrPeriod)   # Always this difference
totalValueSalesIncludingVAT = round_to_pound(totalValueSalesIncludingVAT)   # Otherwise the API rejects it
totalValuePurchasesExVAT = 0
totalValueGoodsSuppliedExVAT = 0                        # (to other EC member states)
totalAcquisitionsExVAT = 0                              # (from other EC member states)

vat_report = {
  "periodStart": periodStart,
  "periodEnd": periodEndInclusive,
  "vatDueSales": vatDueSales,                                   # Box 1
  "vatDueAcquisitions": vatDueAcquisitions,                     # Box 2
  "totalVatDue": totalVatDue,                                   # Box 3
  "vatReclaimedCurrPeriod": vatReclaimedCurrPeriod,             # Box 4
  "netVatDue": netVatDue,                                       # Box 5
  "totalValueSalesExVAT": totalValueSalesIncludingVAT,          # Box 6 (inclusive of VAT for flat-rate, despite name!)
  "totalValuePurchasesExVAT": totalValuePurchasesExVAT,         # Box 7
  "totalValueGoodsSuppliedExVAT": totalValueGoodsSuppliedExVAT, # Box 8
  "totalAcquisitionsExVAT": totalAcquisitionsExVAT,             # Box 9
}

# Convert decimals to floats, checking we don't lose anything in the process
def handle_decimal(x):
    if isinstance(x, D):
        f = float(x)
        d = round_to_pence(D(f))
        assert (d == x), (d, x)
        return f
    else:
        return x

vat_report = { k: handle_decimal(v) for k, v in vat_report.items() }

if warnings == 0:
    json.dump(vat_report, sys.stdout)
else:
    note('Warnings issued. Not writing report.')
    exit(1)
