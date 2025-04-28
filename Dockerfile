FROM debian:12-slim

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git nginx fcgiwrap spawn-fcgi ca-certificates vim && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create repository directory with proper permissions
RUN mkdir -p /srv/git && \
    chown www-data:www-data /srv/git && \
    chmod 2775 /srv/git

# Copy configuration files
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/create-repo.sh /usr/local/bin/create-repo.sh
COPY docker/delete-repo.sh /usr/local/bin/delete-repo.sh

# Ensure scripts are executable
RUN chmod +x /entrypoint.sh && \
    chmod +x /usr/local/bin/create-repo.sh

RUN chmod +x /usr/local/bin/delete-repo.sh

# Environment variables
ENV FCGI_CHILDREN=4 \
    GIT_PROJECT_ROOT=/srv/git \
    GIT_HTTP_EXPORT_ALL=1

# Expose HTTP port
EXPOSE 80

# Define volumes for Git repositories and templates
VOLUME ["/srv/git", "/srv/git-templates"]

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
