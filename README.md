# Git‑HTTP Server in a Box

Dockerised **Nginx + fcgiwrap + `git‑http‑backend`** ready to serve private, token‑based repositories over HTTPS.

---

## 1. What this repository contains

| File / dir            | Purpose |
|-----------------------|---------|
| `Dockerfile`          | Builds a Debian‑slim image with Git, Nginx & fcgiwrap. |
| `docker/git.conf`     | Nginx vHost that proxies `/<40‑hex>.git` to the Git CGI. |
| `docker/entrypoint.sh`| Starts fcgiwrap (with a configurable pool) then Nginx. |
| **_not committed_**   | `/srv/git` runtime volume where all bare repos live. |

The image exposes **port 80** (HTTP). TLS is expected to be terminated by an external reverse‑proxy such as **Caddy**.

---

## 2. Quick start (local / VPS)

```bash
# build image
docker build -t git-http .

# create data volume
docker volume create git-data

# run
# maps host :3001 → container :80 (change host port as you wish)
docker run -d --name git-http \
  -p 3001:80 \
  -e FCGI_CHILDREN=4 \   # adjust for concurrency
  -v git-data:/srv/git \
  git-http
```

Test clone:

```bash
# manually create a repo inside the container for the demo
CID=$(docker ps -qf name=git-http)
TOKEN=$(openssl rand -hex 20)
docker exec -it "$CID" \
  bash -c "git init --bare /srv/git/$TOKEN.git && \
           git -C /srv/git/$TOKEN.git config http.receivepack true"

git clone http://localhost:3001/$TOKEN.git  demo
```

---

## 3. Reverse‑proxy with Caddy (production)

```caddyfile
git.codingblitz.com {
    @git path_regexp token ^/[0-9a-f]{40}\.git(/.*)?$
    reverse_proxy @git 127.0.0.1:3001
}
```
Caddy handles HTTPS automatically via Let’s Encrypt.

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

### 5.1 Cached template (recommended)

```bash
# once on the VPS
git clone --mirror https://github.com/owner/template.git \
              /srv/git-templates/template.git
```

In FastAPI:

```python
run(["git", "clone", "--bare", "/srv/git-templates/template.git", repo_path])
```

### 5.2 Clone‑on‑demand from GitHub

```python
run(["git", "clone", "--bare", "--depth=1", "--filter=blob:none", GITHUB_URL, repo_path])
```

---

## 6. Resource sizing

| Concurrency | RAM needed (repos ≤ 10 MiB) |
|-------------|-----------------------------|
| 20 clones   | ≈ 400 MiB |
| 100 clones  | ≈ 2 GiB  |

Adjust `FCGI_CHILDREN` and container `mem_limit` accordingly. Large pushes can consume up to 1 GiB per process during `pack‑objects`.

---

## 7. Security checklist

* Tokens are the *only* secret—generate at least 160 bits (40 hex chars).
* Revoke by deleting `/srv/git/<token>.git`.
* Restrict push if not needed: omit `http.receivepack true`.
* Put `/srv/git` on a separate filesystem or quota.
* Add hooks (`pre-receive`) to run CI or limit pack size.

---

## 8. License

MIT — see `LICENSE`.

