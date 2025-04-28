# Git‑HTTP Server in a Box

Dockerised **Nginx + fcgiwrap + `git‑http‑backend`** ready to serve private, token‑based repositories over HTTPS.

---

## 1. What this repository contains

| File / dir            | Purpose |
|-----------------------|---------|
| `Dockerfile`          | Builds a Debian‑slim image with Git, Nginx & fcgiwrap. |
| `docker/nginx.conf`   | Nginx configuration that proxies `/<40‑hex>.git` to the Git CGI. |
| `docker/entrypoint.sh`| Starts fcgiwrap (with a configurable pool) then Nginx. |
| `docker/create-repo.sh`| Helper script to create new git repositories. |
| **_not committed_**   | `/srv/git` runtime volume where all bare repos live. |

The image exposes **port 80** (HTTP). TLS is expected to be terminated by an external reverse‑proxy such as **Caddy**.

---

## 2. Quick start (local / VPS)

```bash
# build image
docker build -t git-server .

# create required volumes
docker volume create git-data       # for repositories
docker volume create git-templates  # for template repositories

# run
# maps host :3001 → container :80 (change host port as you wish)
docker run -d --name git-server \
  -p 3001:80 \
  -e FCGI_CHILDREN=4 \   # adjust for concurrency
  -v git-data:/srv/git \
  -v git-templates:/srv/git-templates \
  git-server
```

Test clone:

```bash
# manually create a repo inside the container for the demo
CID=$(docker ps -qf name=git-server)
TOKEN=$(openssl rand -hex 20)
docker exec -it "$CID" \
  bash -c "git init --bare /srv/git/$TOKEN.git && \
           git -C /srv/git/$TOKEN.git config http.receivepack true"

git clone http://localhost:3001/$TOKEN.git demo
```

Alternatively, use the included helper script:

```bash
# Create a new repository with a randomly generated token
docker exec -it git-server create-repo.sh

# Or specify your own token
docker exec -it git-server create-repo.sh your-custom-token
```

---

## 3. Reverse‑proxy with Caddy (production)

```caddyfile
git.codingblitz.com {
    @git path_regexp token ^/[0-9a-f]{40}\.git(/.*)?$
    reverse_proxy @git 127.0.0.1:3001
}
```
Caddy handles HTTPS automatically via Let's Encrypt.

---

## 4. Creating repositories from a separate FastAPI service

```python
# settings.py
VPS_HOST = "git.codingblitz.com"
SSH_KEY  = "~/.ssh/git-vps"      # key restricted to git init commands
REPO_DIR = "/srv/git"

# create_repo.py
import paramiko, secrets, pathlib, textwrap

def create_repo():
    token = secrets.token_hex(20)
    cmd = textwrap.dedent(f"""
        git init --bare {REPO_DIR}/{token}.git && \
        git -C {REPO_DIR}/{token}.git config http.receivepack true
    """)
    ssh = paramiko.SSHClient(); ssh.load_system_host_keys()
    ssh.connect(VPS_HOST, username="git", key_filename=SSH_KEY)
    ssh.exec_command(cmd); ssh.close()
    return f"https://{VPS_HOST}/{token}.git"
```

If FastAPI eventually runs **inside the same VPS**, simply share the `git-data` volume between both containers and run `git init` locally—no SSH needed.

---

## 5. Using repository templates

Repository templates allow you to create new repositories with predefined structure, files, and commit history. This is particularly useful for standardizing project setups across your organization.

### 5.1 Setting up a dedicated templates volume

It's recommended to store your templates in a separate volume from your active repositories:

```bash
# Create a dedicated volume for templates
docker volume create git-templates

# Run with both volumes mounted
docker run -d --name git-server \
  -p 3001:80 \
  -e FCGI_CHILDREN=4 \
  -v git-data:/srv/git \
  -v git-templates:/srv/git-templates \
  git-server
```

This separation provides several benefits:
- Prevents accidental deletion or modification of templates
- Allows independent backup strategies
- Improves organization and clarity
- Enhances security by isolating template content
- Enables different performance optimizations for each volume

### 5.2 Cached template (recommended)

This approach maintains a local mirror of your template repository, which significantly improves creation speed and reduces external dependencies.

```bash
# Connect to the container
docker exec -it git-server bash

# Create templates directory if it doesn't exist
mkdir -p /srv/git-templates

# Clone a template repository
git clone --mirror https://github.com/owner/template.git \
              /srv/git-templates/template.git

# Keep template updated (can be scheduled with cron)
cd /srv/git-templates/template.git && git fetch --all
```

In FastAPI when both containers share the templates volume:

```python
# Fast local clone from cached template
run(["git", "clone", "--bare", "/srv/git-templates/template.git", repo_path])

# Customize the new repository
run(["git", "-C", repo_path, "config", "http.receivepack", "true"])
```

If your FastAPI service runs on a different system, you have two options:

1. Mount the same git-templates volume in both containers:
```yaml
# In docker-compose.yml
services:
  git-server:
    volumes:
      - git-data:/srv/git
      - git-templates:/srv/git-templates
  
  api-service:
    volumes:
      - git-templates:/srv/git-templates  # Share templates volume
```

2. Create a script to copy templates as needed:
```python
# In FastAPI service
def create_repo_from_template(template_name, token):
    # First, check if template exists locally or needs to be copied
    template_path = f"/path/to/local/templates/{template_name}.git"
    if not os.path.exists(template_path):
        # Copy from git server using SSH/SCP
        subprocess.run([
            "scp", "-r", 
            f"git@server:/srv/git-templates/{template_name}.git", 
            template_path
        ])
    
    # Then create the repo using the local template
    repo_path = f"/srv/git/{token}.git"
    run(["git", "clone", "--bare", template_path, repo_path])
```

Benefits of cached templates:
- Works offline without external dependencies
- Much faster repository creation (milliseconds vs. seconds)
- Can version control your templates locally
- Reduces load on GitHub/GitLab servers

### 5.2 Clone‑on‑demand from GitHub

For cases where you need the latest template version or have many rarely-used templates:

```python
# Clone optimization flags:
# --bare: No working directory, just Git data
# --depth=1: Shallow clone (only latest commit)
# --filter=blob:none: Don't fetch file contents until needed
run(["git", "clone", "--bare", "--depth=1", "--filter=blob:none", GITHUB_URL, repo_path])

# You can also apply specific customizations after cloning
run(["git", "-C", repo_path, "config", "core.bare", "true"])
```

This approach ensures you always get the latest template version but depends on external service availability and network connectivity.

---

## 6. Resource sizing

### Memory Requirements

| Concurrency | RAM needed (repos ≤ 10 MiB) |
|-------------|-----------------------------|
| 20 clones   | ≈ 400 MiB |
| 100 clones  | ≈ 2 GiB  |

### FCGI_CHILDREN Configuration

The `FCGI_CHILDREN` environment variable controls the number of FastCGI worker processes that handle Git HTTP requests. This setting directly impacts performance and resource usage:

```bash
# Example configurations for different workloads
docker run -d --name git-server -p 3001:80 -v git-data:/srv/git \
  -e FCGI_CHILDREN=4 \   # Default: Good for development/small deployments
  git-server

# For medium workloads (10-20 concurrent users)
docker run -d --name git-server -p 3001:80 -v git-data:/srv/git \
  -e FCGI_CHILDREN=8 \   # Medium: 8 workers
  git-server

# For high-traffic servers (50+ concurrent users)
docker run -d --name git-server -p 3001:80 -v git-data:/srv/git \
  -e FCGI_CHILDREN=16 \  # High: 16 workers
  --memory=4g \          # Memory limit
  git-server
```

**Choosing the optimal FCGI_CHILDREN value:**

- **Too low**: Requests will queue up, leading to slow response times during peak usage
- **Too high**: Excessive memory consumption and potential system instability
- **Rule of thumb**: Set to approximately 2× the number of CPU cores for balanced performance
- **Memory usage**: Each worker consumes about 20-50 MiB base memory, plus additional memory proportional to repository size and operation complexity

For large repositories or busy servers, consider also adjusting these related settings:
- Nginx worker connections (`worker_connections` in nginx.conf)
- FastCGI timeouts (`fastcgi_read_timeout` in nginx.conf)
- Container memory limits as shown above

Large pushes can consume up to 1 GiB per process during `pack‑objects` operations, so plan your resource allocation accordingly.

---

## 7. Repository Management

### Creating Repositories

You can create repositories using the included helper script:

```bash
# Create a new repository with a randomly generated token
docker exec -it git-server create-repo.sh

# Or specify your own token
docker exec -it git-server create-repo.sh your-custom-token
```

### Deleting Repositories

To remove a repository, you simply need to delete its directory from the `/srv/git` volume:

```bash
# Delete a repository by its token
docker exec -it git-server rm -rf /srv/git/YOUR_TOKEN.git

# Example with confirmation and success message
docker exec -it git-server bash -c '
if [ -d "/srv/git/$1.git" ]; then
  rm -rf "/srv/git/$1.git" && 
  echo "Repository $1.git deleted successfully"
else
  echo "Repository $1.git not found"
fi
' _ YOUR_TOKEN
```

You can also create a simple helper script similar to `create-repo.sh`:
You can then use this script just like the create script:

```bash
docker exec -it git-server delete-repo.sh YOUR_TOKEN
```

### Listing Repositories

To list all available repositories:

```bash
docker exec -it git-server find /srv/git -type d -name "*.git" -maxdepth 1 | sed 's|/srv/git/||g' | sed 's|\.git$||g'
```

This command shows all repository tokens without the `.git` suffix.

---

## 8. Security checklist

* Tokens are the *only* secret—generate at least 160 bits (40 hex chars).
* Revoke by deleting `/srv/git/<token>.git`.
* Restrict push if not needed: omit `http.receivepack true`.
* Put `/srv/git` on a separate filesystem or quota.
* Add hooks (`pre-receive`) to run CI or limit pack size.

---

## 9. License

MIT — see `LICENSE`.
