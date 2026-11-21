"""One-time helper: get a TikTok refresh token for the TIKTOK_REFRESH_TOKEN secret.
Run on your computer:  python tools/tiktok_auth.py <client_key> <client_secret> <redirect_uri>
"""
import sys
import urllib.parse
import requests

key, secret, redirect = sys.argv[1:4]
url = "https://www.tiktok.com/v2/auth/authorize/?" + urllib.parse.urlencode({
    "client_key": key, "response_type": "code", "scope": "user.info.basic,video.upload,video.publish",
    "redirect_uri": redirect, "state": "splitsol"})
print("1) Open this, log in as @splitsol and allow:\n", url)
code = input("2) Paste the full URL you were redirected to: ").strip()
code = urllib.parse.parse_qs(urllib.parse.urlparse(code).query).get("code", [code])[0]
r = requests.post("https://open.tiktokapis.com/v2/oauth/token/",
                  headers={"Content-Type": "application/x-www-form-urlencoded"},
                  data={"client_key": key, "client_secret": secret, "code": code,
                        "grant_type": "authorization_code", "redirect_uri": redirect})
j = r.json()
print("\nTIKTOK_REFRESH_TOKEN =", j.get("refresh_token") or j)
