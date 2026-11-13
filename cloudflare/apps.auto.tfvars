# Apps exposed through the home tunnel ("Hjemme"). Edit this file to add,
# change or remove an app; a PR shows the plan, merging applies it.
#
#   access = "family"  behind Cloudflare Access (no login from home,
#                      family emails elsewhere)
#   access = "public"  no Access at all - must be written out explicitly

apps = [
  {
    key       = "teslamate"
    name      = "Teslamate"
    hostname  = "teslamate.torvmyrvegen20.net"
    service   = "http://192.168.0.240:4000"
    access    = "family"
    session   = "730h"
    logo      = "https://docs.teslamate.org/img/logo.svg"
    http_only = true
  },
  {
    key            = "loxone"
    name           = "Loxone"
    hostname       = "loxone.torvmyrvegen20.net"
    service        = "http://192.168.0.102"
    access         = "family"
    session        = "730h"
    logo           = "https://www.loxone.com/enen/wp-content/uploads/sites/3/2020/07/ic-house.png"
    http_only      = true
    origin_request = {}
  },
  {
    key       = "grafana"
    name      = "Grafana"
    hostname  = "grafana.torvmyrvegen20.net"
    service   = "http://192.168.0.240:3000"
    access    = "family"
    session   = "730h"
    logo      = "https://www.clipartmax.com/png/small/450-4503037_grafana-prometheus-grafana-logo.png"
    http_only = true
  },
  {
    key               = "ha"
    name              = "Home Assistant"
    hostname          = "ha.torvmyrvegen20.net"
    service           = "http://192.168.0.63:8123"
    access            = "family"
    session           = "730h"
    logo              = "https://upload.wikimedia.org/wikipedia/commons/thumb/6/6e/Home_Assistant_Logo.svg/1200px-Home_Assistant_Logo.svg.png"
    http_only         = true
    skip_interstitial = true
    origin_request    = { http_host_header = "" }
  },
  {
    key       = "pihole"
    name      = "PiHole"
    hostname  = "pihole.torvmyrvegen20.net"
    service   = "http://192.168.0.240:8080"
    access    = "family"
    logo      = "https://banner2.cleanpng.com/20180724/wwt/kisspng-pi-hole-orange-pi-armbian-openshift-clip-art-5b56c42921b764.4342493115324129691381.jpg"
    http_only = true
  },
  {
    key            = "crafty"
    name           = "crafty"
    hostname       = "crafty.torvmyrvegen20.net"
    service        = "https://192.168.0.240:8443"
    access         = "family"
    origin_request = { no_tls_verify = true }
  },
  {
    key      = "trip"
    name     = "trip"
    hostname = "trip.famnygaard.com"
    service  = "http://192.168.0.240:8300"
    access   = "family"
  },
  {
    key            = "proxmox"
    name           = "proxmox"
    hostname       = "proxmox.torvmyrvegen20.net"
    service        = "https://192.168.0.107:8006"
    access         = "family"
    origin_request = { http2_origin = true, no_tls_verify = true }
  },
  {
    key      = "komodo"
    name     = "komodo"
    hostname = "komodo.torvmyrvegen20.net"
    service  = "http://192.168.0.240:9120"
    access   = "family"
  },
  {
    key      = "photos"
    name     = "photos"
    hostname = "photos.famnygaard.com"
    service  = "http://192.168.0.52:2283"
    access   = "family"
    session  = "730h"
  },
]
