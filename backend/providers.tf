provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "lab3-iac"
      Team      = "lucca-christian"
      ManagedBy = "terraform"
      Repo      = "lab3-iac-lc"
      Component = "backend"
    }
  }
}
