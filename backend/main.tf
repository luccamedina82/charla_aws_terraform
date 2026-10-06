data "aws_caller_identity" "current" {}

locals {
  # El nombre de un bucket S3 es único en todo AWS: el account ID evita
  # colisiones con cualquier otra cuenta.
  bucket_name = "${var.bucket_prefix}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  # false a propósito: si quedan objetos, el destroy falla en vez de
  # borrar el state de dev en silencio. Ver docs/decisiones-modulos.md
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encriptación en reposo: el state guarda en texto plano todo lo que
# Terraform lee, incluida la password de MySQL que resuelve desde SSM.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloquea cualquier acceso público — el state es información sensible.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
