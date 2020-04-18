terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "foxnet"

    workspaces {
      name = "bootstrap-google"
    }
  }
}
