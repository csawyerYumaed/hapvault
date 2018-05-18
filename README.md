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
* Hashicorp's Vault  (www.vaultproject.io) served over HTTPS
* Luasocket compiled and in your path somewhere (https://github.com/diegonehab/luasocket)
* Some login page somewhere that sets a cookie with the vault token.

Configuration
------------------

See tests/haproxy.cfg for example. instructions for that in tests/README
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

So now we have the frontend configured with the 2 headers we need.
and we have the backend for hapvault configured, so now in the backend you want protected add lines like this:

  http-request lua.hapvault hapvault vault-token default
  http-request redirect location %[var(txn.auth_redirect_location)]  if { var(txn.auth_redirect) -m bool }

The first http-request line can be broken down like this:

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

It will try to magically create an email address for the username, if possible based on the mount path.
This probably isn't useful to most of you, but it is for us.  It should not affect anyone with the mount path of 'ldap' as it will skip over this. see get_email function for details.

Security Considerations
-----------------------------

Your login system(not included here) can on vault login create a new reduced
token, with policies that basically do nothing other than set policy names for
this code.  Also when creating new tokens , you can set their timeout to be
under the default of 32 days as well.  These would both be good practice to
implement in your login system.

One could also make them wrapped, and give them a limited # of uses, but
that would be hard to predict. If you go down this route, I would be curious
how it works out for you.

Also you should set your cookies to be HttpOnly and Secure and set the domain
and path accordingly.
For more information see:
https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies

The Hashicorp Vault web UI uses localStorage instead of cookies, but I
believe the only way to use local Storage is with Javascript, which is sad.
They don't even use SessionStorage, which seems weird, but plain
localStorage.

Regardless, if you want to use sessionStorage, you can
with this code, just send the token as a header.

More information about localStorage vs Cookies is available here:
https://stackoverflow.com/questions/3220660/local-storage-vs-cookies#3220802

Better security suggestions and code changes are very welcome.

VAULT SSL
----------------

 If you really can't be bothered to host your vault over SSL, you can edit hapvault.lua, change the request_url value to http://
and change the:
   create = create_sock_ssl,
to:
   create = create_sock,
Doing this is a bad idea. But useful for testing against a local vault.

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