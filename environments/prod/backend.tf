terraform {
  # Credentials come from AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.
  backend "s3" {
    bucket = "tfstate"
    key    = "0xc0/vault/prod.tfstate"
    region = "us-east-1"
    endpoints = {
      s3 = "https://s3.0xc0.cc"
    }
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
