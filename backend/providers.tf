provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "charla-aws"
      Team      = "lucca-maxi"
      ManagedBy = "terraform"
      Repo      = "charla_aws_terraform"
      Component = "backend"
    }
  }
}
