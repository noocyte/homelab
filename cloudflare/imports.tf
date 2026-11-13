# One-time import of the cabin's existing DNS record (2026-11-13).
# Can be deleted after the first successful apply.

import {
  to = cloudflare_dns_record.app["cabin_ha"]
  id = "87f01f50703dadaaf2da82cc3a04e6bc/79d69d6aaa66efac12df155a600ae888"
}
