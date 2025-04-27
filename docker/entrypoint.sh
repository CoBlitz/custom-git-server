#!/bin/bash
set -e

# 1. socket FastCGI con N hijos
spawn-fcgi -s /run/fcgiwrap.sock -F "${FCGI_CHILDREN}" \
           -u www-data -g www-data /usr/sbin/fcgiwrap

# 2. Nginx en primer plano
exec nginx -g "daemon off;"
