FROM debian:12-slim

# — dependencias —
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git nginx fcgiwrap spawn-fcgi ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# — configuración —
COPY docker/git.conf       /etc/nginx/conf.d/git.conf
COPY docker/entrypoint.sh  /entrypoint.sh
RUN chmod +x /entrypoint.sh

# — directorio de repos —
RUN mkdir -p /srv/git && chown www-data:www-data /srv/git

# — variables —
ENV FCGI_CHILDREN=4 \
    GIT_PROJECT_ROOT=/srv/git \
    GIT_HTTP_EXPORT_ALL=1

EXPOSE 80
VOLUME ["/srv/git"]        
ENTRYPOINT ["/entrypoint.sh"]
