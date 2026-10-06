provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # Único lugar donde se etiquetan los recursos. A mano solo va Name.
  default_tags {
    tags = {
      Project     = "charla-aws"
      Environment = var.environment
      Team        = "lucca-maxi"
      ManagedBy   = "terraform"
      Repo        = "charla_aws_terraform"
    }
  }
}
