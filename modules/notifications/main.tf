resource "aws_sns_topic" "this" {
  name = "${var.name_prefix}-alerts"

  tags = {
    Name = "${var.name_prefix}-alerts"
  }
}

# Un subscription resource por email. Agregar un mail más adelante es sumar un
# elemento a var.subscription_emails y aplicar — no hace falta tocar este módulo.
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.subscription_emails)

  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = each.value
}

# CodePipeline no publica directo al topic: lo hace vía CodeStar Notifications
# (aws_codestarnotifications_notification_rule en el módulo cicd), que corre
# bajo el principal de servicio codestar-notifications.amazonaws.com. Sin este
# permiso explícito en la resource policy del topic, la notification rule
# queda creada pero nunca entrega nada — falla en silencio.
data "aws_iam_policy_document" "topic_policy" {
  count = var.allow_codestar_notifications ? 1 : 0

  statement {
    sid    = "AllowCodestarNotificationsPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codestar-notifications.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this.arn]
  }

  # CloudWatch Alarms (Fase 8) publica desde el mismo account: por default el
  # principal de la cuenta ya puede publicar sin necesidad de una statement
  # explícita, así que no hace falta agregar nada más acá para esa fase.
  statement {
    sid    = "AllowAccountRootPublish"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "this" {
  count = var.allow_codestar_notifications ? 1 : 0

  arn    = aws_sns_topic.this.arn
  policy = data.aws_iam_policy_document.topic_policy[0].json
}
