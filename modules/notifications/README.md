# Módulo `notifications`

Topic SNS + suscripciones por mail. Separado de `cicd` a propósito
(`estado-actual.md` §14 y §7): lo consumen la Fase 7 (CodePipeline vía
CodeStar Notifications) y la Fase 8 (alarmas de CloudWatch). Si viviera
dentro de `cicd`, la Fase 8 dependería de la Fase 7 sin ninguna razón real.

## Qué crea

- `aws_sns_topic.this`
- `aws_sns_topic_subscription.email` — uno por dirección en
  `var.subscription_emails` (`for_each` sobre un `toset`, no `count`).
- `aws_sns_topic_policy.this` — permite publicar a `codestar-notifications.amazonaws.com`
  (lo necesita `cicd`) y al resto de servicios de la misma cuenta (lo necesita
  `observability` en la Fase 8, aunque de hecho CloudWatch Alarms del mismo
  account ya puede publicar sin esto).

## Paso manual insalvable

Cada suscripción nace en estado `PendingConfirmation`. AWS manda un mail a
cada dirección con un link de confirmación — **si nadie lo clickea, el topic
nunca entrega nada**, aunque el `apply` haya salido perfecto. Confirmarlo es
parte del "Listo cuando" de la Fase 7 (`estado-actual.md` §14, paso 1).

Verificar el estado de las suscripciones:

```bash
aws sns list-subscriptions-by-topic --topic-arn <topic_arn>
```

`SubscriptionArn` en `"PendingConfirmation"` (string literal) = todavía no se
confirmó. Un ARN real = confirmado.

## Agregar un mail más adelante

Sumar el string a `var.subscription_emails` en `environments/dev/variables.tf`
(o `terraform.tfvars`) y aplicar. No hace falta tocar este módulo — es
exactamente el caso para el que está el `for_each`.

## Inputs / Outputs

Ver `variables.tf` y `outputs.tf`. `topic_arn` es lo que consumen `cicd`
(Fase 7) y, más adelante, `observability` (Fase 8).
