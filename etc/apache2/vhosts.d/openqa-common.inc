# OpenQA settings for apache2. This file is meant to be shared
# between the http and the https vhosts.
#
DocumentRoot /usr/share/openqa/public

<Directory "/usr/share/openqa/public">
    AllowOverride None
    Require all granted
</Directory>

<Directory "/var/lib/openqa/share/factory">
    AllowOverride None
    Require all granted
</Directory>
Alias /assets "/var/lib/openqa/share/factory"

<Directory "/var/lib/openqa/images">
  Options SymLinksIfOwnerMatch
  AllowOverride None
  Require all granted

   # Use of ETag is discouraged when Last-Modified is present
  Header unset ETag
  FileETag None
  # RFC says only cache for 1 year
  ExpiresActive On
  ExpiresDefault "access plus 1 year"
</Directory>
Alias /image "/var/lib/openqa/images"

<Directory "/var/lib/os-autoinst/tests">
    AllowOverride None
    Require all granted
</Directory>

<Proxy *>
    Require all granted
</Proxy>

ProxyRequests Off
ProxyPreserveHost On

ProxyPass /robots.txt !
ProxyPass /favicon.ico !
ProxyPass /images !
ProxyPass /image !
ProxyPass /javascripts !
ProxyPass /stylesheets !
ProxyPass /assets !
ProxyPass /error !

#webSocket proxy pass to different port
ProxyPass "/api/v1/ws/" "ws://localhost:9527/ws/" keepalive=On

ProxyPass / http://localhost:9526/ keepalive=On
ProxyPassReverse / http://localhost:9526/

<If "%{HTTPS} == 'on'">
RequestHeader set X-Forwarded-HTTPS "1"
RequestHeader set X-Forwarded-Proto "https"
</If>
<Else>
RequestHeader set X-Forwarded-HTTPS "0"
RequestHeader set X-Forwarded-Proto "http"
</Else>

HostnameLookups Off
UseCanonicalName Off
ServerSignature On

# vim: syntax=apache
