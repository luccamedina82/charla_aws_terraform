# ---------------------------------------------------------------------------
# Security Groups
# Cadena: internet -> alb(443) -> frontend(80) -> mysql(3306) -> efs(2049)
# Reglas como recursos separados (aws_vpc_security_group_*_rule), nunca inline.
# ---------------------------------------------------------------------------

# SG 1: ALB — recibe HTTPS desde internet
resource "aws_security_group" "alb_sg" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Firewall del ALB - HTTPS desde internet"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_from_internet" {
  security_group_id = aws_security_group.alb_sg.id
  description       = "HTTPS desde internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb_sg.id
  description       = "HTTP desde internet - solo para redirigir a HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all_outbound" {
  security_group_id = aws_security_group.alb_sg.id
  description       = "Todo el trafico saliente"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# SG 2: Frontend — recibe trafico de app solo desde el ALB
resource "aws_security_group" "frontend_sg" {
  name        = "${var.name_prefix}-frontend-sg"
  description = "Firewall del frontend - puerto 80 desde el ALB"
  vpc_id      = var.vpc_id
  tags = {
    Name = "${var.name_prefix}-frontend-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend_sg.id
  description                  = "App (8080) desde el ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_vpc_security_group_egress_rule" "frontend_all_outbound" {
  security_group_id = aws_security_group.frontend_sg.id
  description       = "Todo el trafico saliente"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# SG 3: MySQL — recibe trafico solo desde el frontend
resource "aws_security_group" "mysql_sg" {
  name        = "${var.name_prefix}-mysql-sg"
  description = "Firewall de MySQL - puerto 3306 desde el frontend"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-mysql-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_frontend" {
  security_group_id            = aws_security_group.mysql_sg.id
  description                  = "MySQL (3306) desde el frontend"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.frontend_sg.id
}

resource "aws_vpc_security_group_egress_rule" "mysql_all_outbound" {
  security_group_id = aws_security_group.mysql_sg.id
  description       = "Todo el trafico saliente"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# SG 4: EFS — recibe trafico NFS solo desde MySQL
resource "aws_security_group" "efs_sg" {
  name        = "${var.name_prefix}-efs-sg"
  description = "Firewall de EFS - puerto 2049 desde MySQL"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-efs-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_mysql" {
  security_group_id            = aws_security_group.efs_sg.id
  description                  = "NFS (2049) desde MySQL"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.mysql_sg.id
}

resource "aws_vpc_security_group_egress_rule" "efs_all_outbound" {
  security_group_id = aws_security_group.efs_sg.id
  description       = "Todo el trafico saliente"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# SG 5: instancias del cluster ECS — sin inbound (queda así a propósito)
resource "aws_security_group" "cluster_sg" {
  name        = "${var.name_prefix}-cluster-sg"
  description = "Firewall de las instancias del cluster ECS - sin inbound"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-cluster-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "cluster_all_outbound" {
  security_group_id = aws_security_group.cluster_sg.id
  description       = "Todo el trafico saliente"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
