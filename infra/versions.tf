terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6, < 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0, < 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4, < 3.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Owner     = var.owner_tag
    }
  }
}
