#!/usr/bin/env python3

from requests_oauthlib import OAuth2Session
from oauthlib.oauth2.rfc6749.errors import TokenExpiredError
from oauthlib.oauth2 import BackendApplicationClient
import socket, sys, json, os, subprocess, time
from datetime import datetime, timedelta
from urllib import parse
import requests

def note(x, *args): print(x, *args, file=sys.stderr)
def parse_date(x): return datetime.strptime(x, '%Y-%m-%d')
def show_date(x): return datetime.strftime(x, '%Y-%m-%d')

def usage():
    note('Usage: hmrc-api.py config.json [get-obligations|submit-return]')
    exit(1)

if len(sys.argv) != 3: usage()
config_path, op, = sys.argv[1:]

config_dir = os.path.dirname(config_path)
token_path = os.path.join(config_dir, 'hmrc-token.json')

with open(config_path) as s:
    config = json.load(s)
api = config['endpoint']
vrn = config['vrn']
client_id = config['client_id']
client_secret = config['client_secret']
dev_id = config['device_id']
dev_manu = config['device_manufacturer']
dev_model = config['device_model']

def get_fraud_headers():
    def show_timezone(tm):
        m = tm.tm_gmtoff / 60
        return 'UTC+%02d:%02d' % (m / 60, m % 60)

    local_ips = []
    mac_addresses = []
    results = subprocess.check_output(['ip', 'address', 'show', 'up'], encoding='utf-8')
    for line in results.split('\n'):
        if line.startswith('    inet ') or line.startswith('    inet6 '):
            addr = line.split()[1].split('/')[0]
            if addr not in ('127.0.0.1', '::1'):
                local_ips.append(addr)
        if line.startswith('    link/ether '):
            mac_addresses.append(line.split()[1])

    scale = float(subprocess.check_output(['gsettings', 'get', 'org.gnome.desktop.interface', 'text-scaling-factor']))

    screens = []
    last_dim = None
    results = subprocess.check_output(['xdpyinfo'], encoding='utf-8')
    for line in results.split('\n'):
        if line.startswith('  dimensions:'):
            last_dim = line.split()[1].split('x')
        if line.startswith('  depth of root window:'):
            width, height = last_dim
            depth = int(line.split(':')[1].split()[0])
            descr = f'width={width}&height={height}&scaling-factor={scale:.1f}&colour-depth={depth}'
            screens.append(descr)
            last_dim = None
    assert screens, "No screens returned by xdpyinfo!"

    window_size = os.environ.get('THE_WINDOW_SIZE', None)
    if window_size is None:
        note('Please select "the window on the originating device" (size needed for fraud headers)')
        note('The web browser used to log in is probably a good choice.')
        results = subprocess.check_output(['xwininfo'], encoding='utf-8')
        width = None
        height = None
        for line in results.split('\n'):
            line = line.split()
            #print(line)
            if not line: continue
            if line[0] == 'Width:': width = int(line[1])
            elif line[0] == 'Height:': height = int(line[1])
        assert width and height, 'Missing window size'
        window_size = f'width={width:d}&height={height:d}'

    os_name = subprocess.check_output(['uname', '-s']).strip()
    os_version = subprocess.check_output(['uname', '-r']).strip()
    user_agent = f'{parse.quote(os_name)}/{parse.quote(os_version)} ({parse.quote(dev_manu)}/{parse.quote(dev_model)})'

    return {
        'Gov-Client-Connection-Method': 'DESKTOP_APP_DIRECT',
        'Gov-Client-Device-ID': dev_id,
        'Gov-Client-User-IDs': 'os=%d' % (os.getuid ()),
        'Gov-Client-Timezone': show_timezone(time.localtime()),
        'Gov-Client-Local-IPs': ','.join(parse.quote(x) for x in local_ips),
        'Gov-Client-MAC-Addresses': ','.join(parse.quote(x) for x in mac_addresses),
        'Gov-Client-Screens': ','.join(screens),
        'Gov-Client-Window-Size': window_size,
        'Gov-Client-User-Agent': user_agent,
        'Gov-Client-Multi-Factor': '',
        'Gov-Vendor-Version': 'TomsTaxes=1.0',
        'Gov-Vendor-License-IDs': '',
    }

redirect_port = 7000
redirect_uri = 'http://localhost:%d' % redirect_port

def save_token(token):
    note("Saving token as %s" % token_path)
    with open(token_path, 'w') as s:
        json.dump(token, s)

def load_token():
    if os.path.exists(token_path):
        with open(token_path) as s:
            return json.load(s)
    else:
        return None

# Run a server on redirect_port. Ask the user to grant us access. Collect the response
# and get the actual token.
def do_oauth():
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    server.bind(('', redirect_port))
    server.listen(5)

    scope = ['read:vat', 'write:vat']
    oauth = OAuth2Session(client_id, redirect_uri=redirect_uri, scope=scope)

    authorization_url, state = oauth.authorization_url(api + "oauth/authorize")

    note('Please go to:\n\n%s\n' % authorization_url)
    subprocess.check_call(['xdg-open', authorization_url])

    note('Awaiting network connection on port %d...' % redirect_port)
    conn, _ = server.accept()
    note('Got connection')
    request_line = conn.makefile().readline()
    #note('GOT:', request_line)
    get, path, _version = request_line.split(' ')
    assert (get == 'GET')
    authorization_response = 'https://localhost/' + path
    #note(authorization_response)

    conn.sendall(b'HTTP/1.0 200 OK\r\ncontent-type: text/plain\r\n\r\nOK!')
    conn.close()
    server.close()

    return oauth.fetch_token(
        api + "oauth/token",
        authorization_response=authorization_response,
        include_client_id = True,
        client_id=client_id,
        client_secret=client_secret)

token = load_token()

def get_oauth():
    global token
    if token is None:
        fraud_headers = get_fraud_headers()
        note('Will save fraud headers:\n%s' % (json.dumps(fraud_headers, indent=2)))
        token = do_oauth()
        token['fraud_headers'] = fraud_headers
        save_token(token)
    fraud_headers = token['fraud_headers']
    oauth = OAuth2Session(client_id, token=token)
    token = None    # If we get called again, it's because the token expired.
    return oauth, fraud_headers

def check_response(r):
    if r.ok: return r
    else:
        note("REST API call returned an error")
        note("URL:", r.url)
        note("Status code:", r.status_code)
        note("Headers:", r.headers)
        note("Body:", r.text)
        r.raise_for_status()
        assert False

def get_obligations():
    now = datetime.today()
    last_year = show_date(now - timedelta(weeks=52))
    now = show_date(now)

    while True:
        oauth, fraud_headers = get_oauth()
        headers = {
            'Accept': 'application/vnd.hmrc.1.0+json',
        }
        headers.update(fraud_headers)
        try:
            r = oauth.get(api + "organisations/vat/{vrn}/obligations".format(vrn = vrn),
                    params = {'from': last_year, 'to': now },
                    headers = headers)
        except TokenExpiredError:
            note("Token expired")
            continue
        else:
            check_response(r)
            json.dump(r.json(), sys.stdout)
            note("Got obligations for last 12 months (%s to %s)" % (last_year, now))
            return

def submit_return():
    vat_return = json.load(sys.stdin)
    assert "finalised" in vat_return, 'Return not finalised!'
    oauth, fraud_headers = get_oauth()
    headers = {
        'Accept': 'application/vnd.hmrc.1.0+json',
        'Content-Type': 'application/json',
    }
    headers.update(fraud_headers)
    r = oauth.post(api + '/organisations/vat/{vrn}/returns'.format(vrn = vrn), headers = headers, data = json.dumps((vat_return)))
    check_response(r)
    json.dump(r.json(), sys.stdout)
    note("Done")

def create_test_user():
    client = BackendApplicationClient(client_id=client_id)
    oauth = OAuth2Session(client=client)
    token = oauth.fetch_token(token_url=api+'/oauth/token', include_client_id=True, client_id=client_id, client_secret=client_secret)
    headers = {
        'Accept': 'application/vnd.hmrc.1.0+json',
        'Content-Type': 'application/json',
    }
    request = { "serviceNames": [ "mtd-vat" ] }
    r = oauth.post(api + '/create-test-user/individuals', headers = headers, data = json.dumps(request))
    check_response(r)
    json.dump(r.json(), sys.stdout)
    note("Done")

def fraud_prevention():
    client = BackendApplicationClient(client_id=client_id)
    oauth = OAuth2Session(client=client)
    token = oauth.fetch_token(token_url=api+'/oauth/token', include_client_id=True, client_id=client_id, client_secret=client_secret)
    headers = {
        'Accept': 'application/vnd.hmrc.1.0+json',
    }
    fraud_headers = get_fraud_headers()
    note('Sending fraud headers:\n' + json.dumps(fraud_headers, indent=2))
    headers.update(fraud_headers)
    r = oauth.get(api + '/test/fraud-prevention-headers/validate', headers = headers)
    check_response(r)
    json.dump(r.json(), sys.stdout)
    note("Done")

if op == 'get-obligations': get_obligations()
elif op == 'submit-return': submit_return()
elif op == 'create-test-user': create_test_user()
elif op == 'fraud-prevention': fraud_prevention()
else: usage()
