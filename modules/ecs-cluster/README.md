# Módulo `ecs-cluster`

Cluster ECS en modo EC2, con su capacidad (ASG + capacity provider) y el
namespace de Cloud Map del que depende el service discovery.

## Por qué estas cosas viven juntas

El límite del módulo es el **ciclo de vida**, no el servicio de AWS. El ASG,
el launch template y el instance profile no tienen sentido por separado: se
crean, se cambian y se destruyen juntos.

El namespace de Cloud Map está acá y no en `ecs-service` porque es **uno solo
para todo el cluster**. Como `ecs-service` se invoca dos veces (frontend y
mysql), si el namespace viviera adentro la segunda invocación intentaría crear
un namespace duplicado.

## Uso

```hcl
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name_prefix        = local.name_prefix
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  instance_sg_id     = module.security_groups.cluster_sg_id
}
```

## Las cinco cosas que la consola hacía sola

Este módulo existe porque el wizard de la consola resuelve en silencio cinco
cosas que en Terraform son explícitas. Si falta alguna, el síntoma es confuso:

| # | Qué | Si falta |
|---|---|---|
| 1 | `user_data` con `ECS_CLUSTER=` | Las instancias arrancan sanas y **nunca aparecen en el cluster** |
| 2 | AMI por data source de SSM | Un `ami-xxxx` hardcodeado deja de existir en unos meses |
| 3 | `aws_iam_instance_profile` | Un rol IAM no se puede asociar a una EC2 directamente |
| 4 | El capacity provider son **3 recursos** | El wizard mostraba una pantalla |
| 5 | El log group de `awslogs` | (vive en `ecs-service`) la task falla con un error de permisos |

## Decisiones que conviene entender antes de tocar

**`min_size = 3` no es disponibilidad, es ENIs.** Con `awsvpc` cada task
consume una ENI de la instancia. Una `t3.small` tiene 3 en total y una es de
la propia instancia: **2 slots de task por instancia**, 6 en el cluster. En
régimen corren 3 tasks (2 frontend + 1 mysql) y durante un swap blue/green
son 5. Dato contraintuitivo: en la familia `t3`, subir de tamaño **no** da más
ENIs (`t3.small`, `t3.medium` y `t3.large` tienen 3). El colchón sale del
número de instancias, no de su tamaño.

Y hay un segundo motivo: el `managed_scaling` del capacity provider calcula
cuántas instancias hacen falta para las tasks actuales, y con 3 tasks
concluiría que alcanzan 2. `min_size` es lo que se lo impide.

**`managed_termination_protection` apagada.** Exige `protect_from_scale_in` en
el ASG (si no coinciden, el apply falla con un mensaje que no menciona la
relación). El problema real viene después: el `terraform destroy` de la Fase 9
se traba con instancias protegidas que hay que desproteger a mano. Para un lab
con prueba de reproducibilidad obligatoria, el costo supera al beneficio.

**Container Insights en `enabled`, no `enhanced`.** La versión enhanced cuesta
varias veces más y con dos servicios no aporta nada.

**El ASG se tagea a mano.** `aws_autoscaling_group` no expone `tags_all`, así
que **no hereda `default_tags` del provider**. Sin los bloques `tag`
generados desde `data.aws_default_tags`, el ASG y sus instancias serían los
únicos recursos del proyecto sin etiquetar. Es una limitación del recurso, no
una excepción a `CONVENCIONES.md` §3.

**`AmazonECSManaged` va sí o sí.** ECS lo agrega al ASG por su cuenta apenas
lo asocia a un capacity provider, tenga o no encendida la protección de
terminación. Si el tag no está declarado en el código, el `terraform plan`
posterior al apply propone borrarlo una y otra vez — un drift permanente que
rompe el `No changes` que pide el DoD.

**`nonsensitive()` sobre el AMI.** El provider marca como sensible el `value`
de `data.aws_ssm_parameter`, y el plan mostraría `(sensitive value)` en lugar
del AMI ID — justo el dato que hay que revisar en el diff cuando AWS publica
una imagen nueva. Un ID de AMI pública no es un secreto.

## Variables

| Nombre | Tipo | Default |
|---|---|---|
| `name_prefix` | `string` | — |
| `vpc_id` | `string` | — |
| `private_subnet_ids` | `list(string)` | — |
| `instance_sg_id` | `string` | — |
| `instance_type` | `string` | `"t3.small"` — con `validation` que rechaza los tipos de 2 ENIs |
| `min_size` / `desired_capacity` | `number` | `3` |
| `max_size` | `number` | `6` |
| `root_volume_size` | `number` | `30` |
| `namespace_name` | `string` | `"lab3.local"` |
| `container_insights` | `string` | `"enabled"` |
| `imds_hop_limit` | `number` | `2` |
| `managed_termination_protection` | `bool` | `false` |
| `capacity_provider_target` | `number` | `100` |
| `ecs_ami_ssm_parameter` | `string` | ruta AL2023 |

## Outputs

| Nombre | Lo consume |
|---|---|
| `cluster_id` / `cluster_name` / `cluster_arn` | `ecs-service` (×2), observabilidad |
| `capacity_provider_name` | `capacity_provider_strategy` de cada servicio |
| `namespace_id` / `namespace_arn` | `aws_service_discovery_service` de MySQL |
| `namespace_name` | `ssm-parameters`, para componer `DB_HOST = mysql.<namespace>` |
| `asg_name` | Alarmas de `CPUUtilization` de la Fase 8 |
| `instance_role_name` | Por si otro módulo necesita adjuntarle una policy |

## Verificación

```bash
# La prueba de que el user_data funcionó. Tiene que dar 3.
aws ecs describe-clusters --clusters lab3-lc-dev-cluster \
  --query 'clusters[0].registeredContainerInstancesCount'

# Si da 0: o el user_data no escribió ECS_CLUSTER, o falta la policy
# AmazonEC2ContainerServiceforEC2Role en el rol de instancia.
aws ecs list-container-instances --cluster lab3-lc-dev-cluster

# Session Manager, que es donde se debuggea lo anterior.
aws ssm start-session --target <instance-id>
```

## Lab vs. producción

| Acá | En producción |
|---|---|
| `managed_termination_protection` apagada | Encendida: matar una instancia con tasks vivas es un outage |
| Sin `instance_refresh` en el ASG | Con refresh, para que una AMI nueva se propague sola |
| `health_check_type = "EC2"` | `"ELB"` si las instancias sirvieran tráfico directo |
| Cluster sin capacidad Fargate | Un capacity provider Fargate para picos, sin gestionar EC2 |
