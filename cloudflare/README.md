# Cloudflare (tunnel routes, DNS, Access) as code

OpenTofu manages two tunnels: **"Hjemme"** (home, `cloudflared` stack on the
docker host) and **"homeassistant"** (the cabin, Cloudflared add-on on the
cabin's Home Assistant, in token mode). For both: the ingress routes, their
`CNAME` records (`torvmyrvegen20.net`, `famnygaard.com`, `fossanhagen38.com`),
the Access apps and the policies "At Home" (bypass, home IP list), "At Cabin"
(bypass, cabin IP) and "Familien". Home apps use At Home + Familien; cabin
apps use At Cabin + At Home + Familien.

**Add, change or remove an app: edit `apps.auto.tfvars`, open a PR.**
Every app must say `access = "family"` (behind Access) or `access = "public"`
(no Access). There is no default, so a route can't be added unprotected by
accident. The PR gets a comment with the plan; merging to `main` applies it
(`.github/workflows/cloudflare.yml`, GitHub environment `cloudflare`).

Not managed here: the tunnels themselves (their tokens live in Komodo, stack
`cloudflared`, and in the cabin add-on's settings), the Zero Trust list
"At Home" (the home IP), and other DNS records (mail, Nabu Casa, Minecraft).

## Secrets (GitHub → Settings → Secrets and variables → Actions)

| Secret | What |
|---|---|
| `CLOUDFLARE_API_TOKEN` | API token `homelab-opentofu`: Account - Cloudflare Tunnel Edit, Access: Apps and Policies Edit, Access: Organizations, Identity Providers, and Groups Read, Account Settings Read; Zone (torvmyrvegen20.net, famnygaard.com, fossanhagen38.com) - DNS Edit, Zone Edit |
| `CLOUDFLARE_CABIN_IP` | The cabin's public IPv4 (no `/32`). If it changes, the cabin just gets the family login until this is updated. |
| `CLOUDFLARE_FAMILY_EMAILS` | JSON list of the "Familien" emails, e.g. `["a@example.com","b@example.com"]`. Never in git: the repo is public. |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | R2 API token, Object Read & Write on bucket `homelab-tofu-state` (holds the state) |

## Running it locally

```sh
cd cloudflare
set -a; . ~/.config/homelab/cloudflare.env; set +a   # CLOUDFLARE_API_TOKEN + R2 keys
export AWS_ENDPOINT_URL_S3=https://4f02188557b4bf21d237feb6eaf4a940.r2.cloudflarestorage.com
export TF_VAR_family_emails='["..."]' TF_VAR_cabin_ip=...
tofu init && tofu plan
```
