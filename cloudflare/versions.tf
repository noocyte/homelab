terraform {
  required_version = ">= 1.9"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.29"
    }
  }

  # State in Cloudflare R2 (S3 API). Credentials and endpoint come from the
  # environment: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
  # AWS_ENDPOINT_URL_S3=https://<account_id>.r2.cloudflarestorage.com
  backend "s3" {
    bucket                      = "homelab-tofu-state"
    key                         = "cloudflare/terraform.tfstate"
    region                      = "auto"
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}

# CLOUDFLARE_API_TOKEN from the environment.
provider "cloudflare" {}
