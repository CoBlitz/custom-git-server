#!/bin/bash
set -e

# Ensure repository directory has correct ownership
chown www-data:www-data /srv/git
chmod 2775 /srv/git

# Fix ownership of any existing repositories
# find /srv/git -type d -name "*.git" -exec chown -R www-data:www-data {} \;

# Start FastCGI wrapper with configured number of children
spawn-fcgi -s /run/fcgiwrap.sock -F "${FCGI_CHILDREN}" \
           -u www-data -g www-data /usr/sbin/fcgiwrap

# Start Nginx in foreground
exec nginx -g "daemon off;"
