HAProxy foward authentication against Hashicorp Vault(lua embedded)
===================================================

This works via taking a user defined cookie(or header) from the incoming
haproxy request and asking vault if the vault token contained there in is
valid for a given policy.

If it is valid, then the request is granted and flows through to the backend.
If it is not valid (either the token or the requested policy)
Then the request is redirected to a login link (via X-Redirect-URL)

Requirements
-----------------

* HAProxy 1.8.? (works on 1.8.8) or greater (www.haproxy.org)
* Lua 5.3 compiled in (maybe older versions work.. no clue)
* Hashicorp's Vault  (www.vaultproject.io)
* Luasocket compiled and in your path somewhere (https://github.com/diegonehab/luasocket)
* Some login page somewhere that sets a cookie with the vault token.

Configuration
------------------

see tests/haproxy.cfg for example.
You need to create a backend(in the example it is called hapvault)
that connects to your vault (i.e. server $VAULT_ADDR) basically.

In your frontend configuration you need to create 2 headers:
  http-request set-header X-Requesting-URL https%%3A//%[hdr("host")]%[url]
  http-request set-header X-Redirect-URL https://login.example.com/login

  X-Requesting-URL will be appended as ?service= to the X-Redirect-URL value
  if a bad authentication happens.

Example: if the token is bad or not included in the request
and the original request was: https://www.example.com/magic/fairy/beans
 then the user would get a 302 redirect to:
  https://login.example.com/login?service=https%3A//www.example.com/magic/fairy/beans

If you want it to be something other than service= change the .lua file.

Sadly I have no idea how to get a better copy of the full request url
out of HAProxy, if you have better, please let me know!

so now we have the frontend configured with the 2 headers we need.
and we have the backend for hapvault configured, so now in the backend you want protected add lines like this:

  http-request lua.hapvault hapvault vault-token default
  http-request redirect location %[var(txn.auth_redirect_location)]  if { var(txn.auth_redirect) -m bool }

the first http-request line can be broken down like this:

1. http-request keyword(HAProxy)
2. this http-request needs to use the hapvault.lua file.
3. use the backend named "hapvault"
4. the cookie/header named "vault-token" is what hapvault will look in for the token.
5. the vault token policy required to accept this request for this backend. "default" here.

The second http-request line can be broken down like this:

1. http-request keyword(HAProxy)
2. redirect this request
3. location of the redirect is:
4. the location to redirect to
5. CONDITIONAL -- only redirect if the following is true:
6. txn.auth_redirect is true

txn.auth_redirect comes from hapvault.  It's set if we need to redirect to the login page.

If you have vault LDAP auth configured correctly, then your policies are coming from your LDAP server as well, so you can allow requests based on LDAP groups.

There is a TON of debug information stuffed into hapvault.lua right now, some of
it may contain secret/valuable data , you have been warned.

Cookie/header format
---------------------------

The code *AS WRITTEN* assumes the cookie coming in has 2 parts in the value
USERNAME:VAULT_TOKEN
This is something specific to our implementation, but we like it.

If you do not want this, and want the value to be just the pure vault token, then edit hapvault.lua search for SETTING and you should see what you need to do.

basically you just comment out the next two code lines by prepending with --

see, easy peasy!

Now we should be all setup, and haproxy should start doing the right thing!

Flow of request
-------------------

HAProxy gets the request, and sends it into hapvault.

hapvault looks through the headers and cookies searching for the vault token.

If it's found, we create a subrequest asking vault via (/auth/token/lookup-self)

We then compare the policy we require against the policies vault told us are part of the token.

hapvault returns succesful or returns a redirect.

Variables hapvault returns to HAProxy
------------------------------------------------

* txn.auth_response_successful boolean, default false.
* txn.auth_redirect boolean, default true.
* txn.auth_response_code integer, the code returned by vault. default 0
* txn.auth_user the username attached to the token. default nil

3rd party code included in this repo
-------------------------------------------

* https://github.com/jiyinyiyong/json-lua
* https://github.com/cloudflare/lua-resty-cookie

Big thanks to: https://github.com/TimWolla/haproxy-auth-request/

Docs used for development
----------------------------------

* http://www.arpalert.org/src/haproxy-lua-api/1.8/index.html
* http://cbonte.github.io/haproxy-dconv/1.8/configuration.html#7.3.6
* https://www.vaultproject.io/api/auth/token/index.html