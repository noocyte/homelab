# Apps exposed through the tunnels (tunnel = "home" by default, or "cabin").
# Edit this file to add, change or remove an app; a PR shows the plan,
# merging applies it.
#
#   access = "family"  behind Cloudflare Access, with
#     tier = "app"     no login at home / at the cabin, family login
#                      elsewhere, 30-day session
#     tier = "admin"   admin login only, always (also at home), 24h session
#   access = "public"  no Access at all - must be written out explicitly
#
#   icon = name in github.com/homarr-labs/dashboard-icons, or a full URL

apps = [
  {
    key      = "teslamate"
    name     = "TeslaMate"
    hostname = "teslamate.torvmyrvegen20.net"
    service  = "http://192.168.0.240:4000"
    access   = "family"
    tier     = "app"
    icon     = "teslamate"
  },
  {
    key      = "loxone"
    name     = "Loxone"
    hostname = "loxone.torvmyrvegen20.net"
    service  = "http://192.168.0.102"
    access   = "family"
    tier     = "app"
    icon     = "loxone"
  },
  {
    key      = "grafana"
    name     = "Grafana"
    hostname = "grafana.torvmyrvegen20.net"
    service  = "http://192.168.0.240:3000"
    access   = "family"
    tier     = "app"
    icon     = "grafana"
  },
  {
    key      = "ha"
    name     = "Home Assistant"
    hostname = "ha.torvmyrvegen20.net"
    service  = "http://192.168.0.63:8123"
    access   = "family"
    tier     = "app"
    icon     = "home-assistant"
  },
  {
    key      = "pihole"
    name     = "Pi-hole"
    hostname = "pihole.torvmyrvegen20.net"
    service  = "http://192.168.0.240:8080"
    access   = "family"
    tier     = "admin"
    icon     = "pi-hole"
  },
  {
    key            = "crafty"
    name           = "Crafty"
    hostname       = "crafty.torvmyrvegen20.net"
    service        = "https://192.168.0.240:8443"
    access         = "family"
    tier           = "admin"
    icon           = "crafty-controller"
    origin_request = { no_tls_verify = true }
  },
  {
    key      = "trip"
    name     = "TRIP"
    hostname = "trip.famnygaard.com"
    service  = "http://192.168.0.240:8300"
    access   = "family"
    tier     = "app"
    icon     = "https://cdn.jsdelivr.net/gh/itskovacs/trip@main/src/public/favicon.png"
  },
  {
    key            = "proxmox"
    name           = "Proxmox"
    hostname       = "proxmox.torvmyrvegen20.net"
    service        = "https://192.168.0.107:8006"
    access         = "family"
    tier           = "admin"
    icon           = "proxmox"
    origin_request = { http2_origin = true, no_tls_verify = true }
  },
  {
    key      = "komodo"
    name     = "Komodo"
    hostname = "komodo.torvmyrvegen20.net"
    service  = "http://192.168.0.240:9120"
    access   = "family"
    tier     = "admin"
    icon     = "komodo"
  },
  {
    key      = "photos"
    name     = "Immich"
    hostname = "photos.famnygaard.com"
    service  = "http://192.168.0.52:2283"
    access   = "family"
    tier     = "app"
    icon     = "immich"
  },
  {
    key            = "cabin_ha"
    name           = "Home Assistant (hytta)"
    hostname       = "ha.fossanhagen38.com"
    service        = "http://homeassistant:8123"
    tunnel         = "cabin"
    access         = "family"
    tier           = "app"
    icon           = "home-assistant"
    origin_request = { no_tls_verify = true }
  },
]
