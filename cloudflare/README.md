# Cloudflare (tunnel routes, DNS, Access) as code

OpenTofu manages the home tunnel **"Hjemme"**: its ingress routes, the
`CNAME` records in `torvmyrvegen20.net` / `famnygaard.com` that point to it,
and the Access apps + the two policies ("At Home" bypass, "Familien").

**Add, change or remove an app: edit `apps.auto.tfvars`, open a PR.**
Every app must say `access = "family"` (behind Access) or `access = "public"`
(no Access). There is no default, so a route can't be added unprotected by
accident. The PR gets a comment with the plan; merging to `main` applies it
(`.github/workflows/cloudflare.yml`, GitHub environment `cloudflare`).

Not managed here: the tunnel itself (its secret/token stays in Komodo, stack
`cloudflared`), the Zero Trust list "At Home" (the home IP), other DNS records
(mail, Nabu Casa, Minecraft), and the cabin's tunnel (`ha.fossanhagen38.com`,
run by the Cloudflared add-on on the cabin's Home Assistant).

## Secrets (GitHub → Settings → Secrets and variables → Actions)

| Secret | What |
|---|---|
| `CLOUDFLARE_API_TOKEN` | API token `homelab-opentofu`: Account - Cloudflare Tunnel Edit, Access: Apps and Policies Edit, Access: Organizations, Identity Providers, and Groups Read, Account Settings Read; Zone (the two zones) - DNS Edit, Zone Edit |
| `CLOUDFLARE_FAMILY_EMAILS` | JSON list of the "Familien" emails, e.g. `["a@example.com","b@example.com"]`. Never in git: the repo is public. |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | R2 API token, Object Read & Write on bucket `homelab-tofu-state` (holds the state) |

## Running it locally

```sh
cd cloudflare
set -a; . ~/.config/homelab/cloudflare.env; set +a   # CLOUDFLARE_API_TOKEN + R2 keys
export AWS_ENDPOINT_URL_S3=https://4f02188557b4bf21d237feb6eaf4a940.r2.cloudflarestorage.com
export TF_VAR_family_emails='["..."]'
tofu init && tofu plan
```

`imports.tf` took over the pre-existing resources (2026-11-13, plan showed
24 to import, 0 to change). It can be deleted after the first apply.
