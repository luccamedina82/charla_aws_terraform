resource "aws_efs_file_system" "this" {
  encrypted = true

  tags = {
    Name = "${var.name_prefix}-efs"
  }
}

# Un mount target por AZ, según piden PLAN-FASES.md (Fase 4) y CONVENCIONES.md.
resource "aws_efs_mount_target" "this" {
  for_each = toset(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [var.efs_sg_id]
}

# Access point dedicado a mysql. uid/gid 999 porque la imagen oficial
# mysql:8.4 (base Debian) corre el proceso como usuario "mysql", uid/gid 999.
# Si el sizing o la imagen de MySQL cambian, verificar este valor primero:
#   docker run --rm public.ecr.aws/docker/library/mysql:8.4 id mysql
resource "aws_efs_access_point" "this" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 999
    gid = 999
  }

  root_directory {
    path = "/mysql"

    creation_info {
      owner_uid   = 999
      owner_gid   = 999
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.name_prefix}-efs-ap-mysql"
  }
}
