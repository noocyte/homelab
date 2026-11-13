# One-time import of the resources that existed before OpenTofu managed

# them (2026-11-13). Can be deleted after the first successful apply.



import {
  to = cloudflare_zero_trust_access_application.app["teslamate"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/4ec85871-c9ef-4158-ac00-f113c140e85f"
}

import {
  to = cloudflare_dns_record.app["teslamate"]
  id = "fa12857d3a971efda0532903f25360ba/f334f90d21dcecbe1efec3089fe9c429"
}

import {
  to = cloudflare_zero_trust_access_application.app["loxone"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/d3375e0d-d609-457c-aaf7-b30ddb7694e9"
}

import {
  to = cloudflare_dns_record.app["loxone"]
  id = "fa12857d3a971efda0532903f25360ba/332c06a84fc46aebb10a071668db04f5"
}

import {
  to = cloudflare_zero_trust_access_application.app["grafana"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/8becb4c0-c8f2-42bc-b7c0-769276cbfe74"
}

import {
  to = cloudflare_dns_record.app["grafana"]
  id = "fa12857d3a971efda0532903f25360ba/ede3097c364e59f58efa851a2a51d35c"
}

import {
  to = cloudflare_zero_trust_access_application.app["ha"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/9c4568aa-b484-4548-9c61-e73fad211877"
}

import {
  to = cloudflare_dns_record.app["ha"]
  id = "fa12857d3a971efda0532903f25360ba/6c24ed927f98897caf28aedb6abe8c68"
}

import {
  to = cloudflare_zero_trust_access_application.app["pihole"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/6c5a0f84-9e73-498f-b33c-c56bc2e9c05c"
}

import {
  to = cloudflare_dns_record.app["pihole"]
  id = "fa12857d3a971efda0532903f25360ba/498084c6f24177bd446d6752d8b27598"
}

import {
  to = cloudflare_zero_trust_access_application.app["crafty"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/29dfa2c4-3038-4b2d-934e-4b99e8906aa1"
}

import {
  to = cloudflare_dns_record.app["crafty"]
  id = "fa12857d3a971efda0532903f25360ba/aab9a4ab4adcaa9489dfed66f6029e1e"
}

import {
  to = cloudflare_zero_trust_access_application.app["trip"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/c0ab1d3d-7cda-4793-a55e-6a504dc53b0e"
}

import {
  to = cloudflare_dns_record.app["trip"]
  id = "445df082415c92bbe6ceda4de0295dc4/791543ede06f32329e0b434cc73a5c04"
}

import {
  to = cloudflare_zero_trust_access_application.app["proxmox"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/1e0f05ee-e761-4637-8d6e-ae04851de69c"
}

import {
  to = cloudflare_dns_record.app["proxmox"]
  id = "fa12857d3a971efda0532903f25360ba/69954d7192d5d78c48854e3d1141f44a"
}

import {
  to = cloudflare_zero_trust_access_application.app["komodo"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/36bf868d-cd02-4cb2-9bd0-757e9ad8096e"
}

import {
  to = cloudflare_dns_record.app["komodo"]
  id = "fa12857d3a971efda0532903f25360ba/cdcb2c28192047e02af9f6b3f5458d99"
}

import {
  to = cloudflare_zero_trust_access_application.app["photos"]
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/6b184b4e-c5f3-4399-8458-7fa5a73803b0"
}

import {
  to = cloudflare_dns_record.app["photos"]
  id = "445df082415c92bbe6ceda4de0295dc4/cb07074cb89ecfa4aa673e941b7c6b88"
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared_config.home
  id = "4f02188557b4bf21d237feb6eaf4a940/338d43a8-bf5f-4033-b58f-3d28c333cb21"
}

import {
  to = cloudflare_zero_trust_access_policy.at_home
  id = "4f02188557b4bf21d237feb6eaf4a940/defd2be8-5c4e-4ae8-987f-b624bc99231f"
}

import {
  to = cloudflare_zero_trust_access_policy.family
  id = "4f02188557b4bf21d237feb6eaf4a940/8fdaa88b-9813-4676-bddd-377a1be4b850"
}

import {
  to = cloudflare_zero_trust_access_application.launcher
  id = "accounts/4f02188557b4bf21d237feb6eaf4a940/41c91e69-b6bd-404c-af76-0c572d7dbc0c"
}
