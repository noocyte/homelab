locals {
  account_id = "4f02188557b4bf21d237feb6eaf4a940"
  tunnels = {
    home  = "338d43a8-bf5f-4033-b58f-3d28c333cb21" # "Hjemme"
    cabin = "7b46b6f7-4d5d-4cd1-90ad-e625a2bb9769" # "homeassistant", Cloudflared add-on on the cabin's HA
  }

  zones = {
    "torvmyrvegen20.net" = "fa12857d3a971efda0532903f25360ba"
    "famnygaard.com"     = "445df082415c92bbe6ceda4de0295dc4"
    "fossanhagen38.com"  = "87f01f50703dadaaf2da82cc3a04e6bc"
  }

  # Zero Trust list "At Home" (home IP), managed in the dashboard.
  home_ip_list_id = "978a91ff-797a-44cd-8f77-785c3848b719"

  apps        = { for a in var.apps : a.key => a }
  icon_cdn    = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png"
  family_apps = { for k, a in local.apps : k => a if a.access == "family" }
}

# --- Tunnel routes ---------------------------------------------------------

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "tunnel" {
  for_each = local.tunnels

  account_id = local.account_id
  tunnel_id  = each.value

  config = {
    ingress = concat(
      [for a in var.apps : {
        hostname       = a.hostname
        service        = a.service
        origin_request = a.origin_request
      } if a.tunnel == each.key],
      [{ service = "http_status:404" }],
    )
  }
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared_config.home
  to   = cloudflare_zero_trust_tunnel_cloudflared_config.tunnel["home"]
}

# --- DNS -------------------------------------------------------------------

resource "cloudflare_dns_record" "app" {
  for_each = local.apps

  zone_id = one([for z, id in local.zones : id if endswith(each.value.hostname, ".${z}")])
  name    = each.value.hostname
  type    = "CNAME"
  content = "${local.tunnels[each.value.tunnel]}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# --- Access ----------------------------------------------------------------

resource "cloudflare_zero_trust_access_policy" "at_home" {
  account_id       = local.account_id
  name             = "At Home"
  decision         = "bypass"
  session_duration = "24h"
  include          = [{ ip_list = { id = local.home_ip_list_id } }]
}

resource "cloudflare_zero_trust_access_policy" "at_cabin" {
  account_id       = local.account_id
  name             = "At Cabin"
  decision         = "bypass"
  session_duration = "24h"
  include          = [{ ip = { ip = "${var.cabin_ip}/32" } }]
}

resource "cloudflare_zero_trust_access_policy" "admins" {
  account_id       = local.account_id
  name             = "Admins"
  decision         = "allow"
  session_duration = "24h"
  include          = [for e in var.admin_emails : { email = { email = e } }]
}

resource "cloudflare_zero_trust_access_policy" "family" {
  account_id       = local.account_id
  name             = "Familien"
  decision         = "allow"
  session_duration = "24h"
  include          = [for e in var.family_emails : { email = { email = e } }]
}

resource "cloudflare_zero_trust_access_application" "app" {
  for_each = local.family_apps

  account_id                 = local.account_id
  name                       = each.value.name
  type                       = "self_hosted"
  domain                     = each.value.hostname
  destinations               = [{ type = "public", uri = each.value.hostname }]
  session_duration           = each.value.tier == "admin" ? "24h" : "730h"
  app_launcher_visible       = true
  auto_redirect_to_identity  = false
  enable_binding_cookie      = false
  http_only_cookie_attribute = true
  options_preflight_bypass   = false
  skip_interstitial          = true
  logo_url                   = startswith(each.value.icon, "https://") ? each.value.icon : "${local.icon_cdn}/${each.value.icon}.png"

  # admin: admin emails only, no bypass. app: bypass at home (and at the
  # cabin for cabin apps), family emails elsewhere.
  policies = each.value.tier == "admin" ? [
    { id = cloudflare_zero_trust_access_policy.admins.id, precedence = 1 },
    ] : [for i, p in concat(
      each.value.tunnel == "cabin" ? [cloudflare_zero_trust_access_policy.at_cabin.id] : [],
      [cloudflare_zero_trust_access_policy.at_home.id, cloudflare_zero_trust_access_policy.family.id],
  ) : { id = p, precedence = i + 1 }]
}

resource "cloudflare_zero_trust_access_application" "launcher" {
  account_id                = local.account_id
  name                      = "App Launcher"
  type                      = "app_launcher"
  session_duration          = "24h"
  auto_redirect_to_identity = false

  policies = [
    { id = cloudflare_zero_trust_access_policy.family.id, precedence = 1 },
    { id = cloudflare_zero_trust_access_policy.at_home.id, precedence = 2 },
  ]
}
