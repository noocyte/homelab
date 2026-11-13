variable "apps" {
  description = "Apps exposed through the tunnels. Order = order of each tunnel's ingress rules."
  type = list(object({
    key      = string
    name     = string
    hostname = string
    service  = string
    tunnel   = optional(string, "home") # "home" (Hjemme) or "cabin" (homeassistant, at the cabin)
    # "family": behind Access. "public": no Access app. Must be written out;
    # there is no default.
    access = string
    # Family apps only:
    #   "app"   - bypass at home (and at the cabin for cabin apps), family
    #             emails elsewhere, 30-day session
    #   "admin" - admin emails only, login always (also at home), 24h session
    tier = optional(string)
    # dashboard-icons name (github.com/homarr-labs/dashboard-icons), e.g.
    # "grafana", or a full https:// URL for apps that aren't in that set.
    icon = optional(string)
    origin_request = optional(object({
      no_tls_verify    = optional(bool)
      http2_origin     = optional(bool)
      http_host_header = optional(string)
    }))
  }))

  validation {
    condition     = alltrue([for a in var.apps : contains(["family", "public"], a.access)])
    error_message = "Every app needs access = \"family\" or \"public\"."
  }
  validation {
    condition     = alltrue([for a in var.apps : a.access != "family" || (contains(["app", "admin"], coalesce(a.tier, "-")) && a.icon != null)])
    error_message = "Family apps need tier = \"app\" or \"admin\", and an icon."
  }
  validation {
    condition     = length(distinct([for a in var.apps : a.hostname])) == length(var.apps) && length(distinct([for a in var.apps : a.key])) == length(var.apps)
    error_message = "App keys and hostnames must be unique."
  }
  validation {
    condition     = alltrue([for a in var.apps : contains(["home", "cabin"], a.tunnel)])
    error_message = "tunnel must be \"home\" or \"cabin\"."
  }
  validation {
    condition     = alltrue([for a in var.apps : endswith(a.hostname, ".torvmyrvegen20.net") || endswith(a.hostname, ".famnygaard.com") || endswith(a.hostname, ".fossanhagen38.com")])
    error_message = "Hostnames must be in torvmyrvegen20.net, famnygaard.com or fossanhagen38.com (the zones this config manages)."
  }
}

variable "family_emails" {
  description = "Emails allowed by the Familien policy. Secret: TF_VAR_family_emails (JSON list), never in git."
  type        = list(string)
  sensitive   = true
}

variable "cabin_ip" {
  description = "The cabin's public IPv4 address (\"At Cabin\" bypass). Secret: TF_VAR_cabin_ip, not in git."
  type        = string
  sensitive   = true
}

variable "admin_emails" {
  description = "Emails allowed by the Admins policy (tier = \"admin\"). Secret: TF_VAR_admin_emails (JSON list), never in git."
  type        = list(string)
  sensitive   = true
}
