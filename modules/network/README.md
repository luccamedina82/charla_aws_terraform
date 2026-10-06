# Módulo `network`

La VPC y su ruteo: dos AZs, una capa pública con salida directa a internet y una
privada que sale por NAT. Todo lo demás del entorno vive adentro de esto.

```
                       internet
                           │
                          IGW
                           │
                      [ public-rt ]
                     /             \
   public-subnet-a (us-east-1a)   public-subnet-b (us-east-1b)
   10.0.1.0/24                    10.0.2.0/24
        │
       NAT
        │
                     [ private-rt ]
                     /             \
  private-subnet-a (us-east-1a)   private-subnet-b (us-east-1b)
  10.0.3.0/24                     10.0.4.0/24
```

Las dos subnets privadas comparten `private-rt`, y esa route table apunta al único
NAT, que está en `public_a`. Por eso el tráfico saliente de `private_b` cruza de AZ.

El ALB vive en las públicas. Las instancias del cluster y todas las tasks viven en
las privadas: no tienen IP pública y salen a internet solo por el NAT.

## Qué crea

| Recurso | Cantidad | Nota |
|---|---|---|
| `aws_vpc.this` | 1 | `enable_dns_hostnames` y `enable_dns_support` en `true` |
| `aws_subnet.public_a` / `public_b` | 2 | `map_public_ip_on_launch = true` |
| `aws_subnet.private_a` / `private_b` | 2 | sin IP pública |
| `aws_internet_gateway.this` | 1 | |
| `aws_eip.nat` + `aws_nat_gateway.this` | 1 + 1 | en `public_a` |
| `aws_route_table.public` / `private` | 2 | `0.0.0.0/0` → IGW y → NAT |
| `aws_route_table_association` | 4 | una por subnet |

Las dos flags de DNS de la VPC no son decorativas: **sin ellas Cloud Map no
resuelve**, y `mysql.lab3.local` es la pieza que sostiene toda la Fase 4.

## Uso

```hcl
module "network" {
  source = "../../modules/network"

  name_prefix = local.name_prefix
}
```

Los cinco CIDR tienen default y el entorno `dev` no pisa ninguno.

## Decisiones

### Un solo NAT Gateway

El NAT vive en `public_a` y las **dos** subnets privadas comparten la misma
`private-rt`. Es una decisión de costo: en `us-east-1` un NAT Gateway son ~32 USD/mes
de base (0,045 USD/hora) más lo que se factura por GB procesado. Uno por AZ, que es lo
correcto, duplica esa base.

Se paga en dos monedas:

- **Transferencia inter-AZ.** Todo lo saliente de `private_b` cruza a la AZ `a` para
  llegar al NAT. Suma latencia y se factura por GB.
- **Es un SPOF.** Si cae la AZ `a`, las tasks de `private_b` siguen vivas y siguen
  sirviendo tráfico del ALB, pero pierden la salida a internet: no bajan imágenes de
  ECR ni resuelven parámetros de SSM. Un deploy en ese momento no arranca.

En producción: un NAT por AZ y una route table privada por AZ.

### Subnets declaradas una por una, sin `for_each`

Son cuatro recursos `aws_subnet` casi idénticos. `CONVENCIONES` §2.6 pide `for_each`
con mapas, pero esa regla apunta a **`count` sobre listas de recursos repetidos**, por
el reindexado que destruye recursos al insertar uno en el medio. Acá no hay `count` ni
lista: son cuatro recursos con nombre propio, cada uno con su CIDR y su rol.

El mapa que haría falta para unificarlos tendría que llevar CIDR, índice de AZ y si es
pública o no, y después reconstruir las dos route tables desde ahí. Para cuatro subnets
fijas es más maquinaria de la que ahorra.

**Dónde se paga**: en `outputs.tf`, que aplana a mano lo que `for_each` daría solo.

```hcl
value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
```

Agregar una tercera AZ toca tres archivos —`main.tf`, `variables.tf` y `outputs.tf`—
contra una entrada en un mapa. Con dos AZs el costo es cero; de tres para arriba, el
`for_each` se justifica y este módulo habría que reescribirlo.

### Las AZs salen de un data source, indexadas por posición

```hcl
availability_zone = data.aws_availability_zones.available.names[0]
```

Nada de `"us-east-1a"` escrito a mano: el módulo funciona en cualquier región con dos
AZs o más. La lista viene ordenada alfabéticamente, así que `[0]` y `[1]` son estables
mientras las dos primeras AZ de la región estén disponibles.

⚠️ **El filtro es `state = "available"`.** Si al momento del `apply` la primera AZ está
degradada, sale de la lista, los índices se corren y `names[0]` pasa a ser otra AZ.
`availability_zone` es un campo **inmutable** de `aws_subnet`: Terraform no lo
actualiza, destruye la subnet y la recrea — y con ella se va todo lo que tenga una ENI
adentro. Probabilidad baja, impacto total.

Es un riesgo de *creación*, no de régimen: una vez aplicado, el estado guarda el nombre
resuelto. Aparece al levantar desde cero, o sea en la Fase 9. La versión robusta fija
las AZ por variable explícita, o usa `aws_availability_zone` por `zone_id` (que sí es
estable por cuenta) en lugar del nombre.

### Por qué propio y no `terraform-aws-modules/vpc/aws`

Está en [`docs/decisiones-modulos.md`](../../docs/decisiones-modulos.md), fila
`network`. Resumen: el módulo de la comunidad trae features que no usamos y mapear sus
variables cuesta más que mantener estos 140 renglones.

## Variables y outputs

| Variable | Tipo | Default |
|---|---|---|
| `name_prefix` | `string` | — |
| `vpc_cidr` | `string` | `10.0.0.0/16` |
| `public_a_subnet_cidr` | `string` | `10.0.1.0/24` |
| `public_b_subnet_cidr` | `string` | `10.0.2.0/24` |
| `private_a_subnet_cidr` | `string` | `10.0.3.0/24` |
| `private_b_subnet_cidr` | `string` | `10.0.4.0/24` |

| Output | Contenido |
|---|---|
| `vpc_id` | ID de la VPC. Lo consume `security-groups`, `alb` y `efs` |
| `public_subnet_ids` | Lista de 2. Lo consume el ALB |
| `private_subnet_ids` | Lista de 2. Lo consumen el ASG, las tasks y los mount targets del EFS |

## Lab vs. producción

| Acá | En producción |
|---|---|
| 1 NAT Gateway compartido | Uno por AZ, con su route table privada |
| 2 AZs | 3, que es el mínimo para quórum en la mayoría de los servicios |
| Sin VPC endpoints | Endpoints de ECR, S3, SSM y Logs: menos tráfico por NAT, menos costo y no dependen de internet |
| Sin VPC Flow Logs | Flow logs a CloudWatch o S3, para auditoría e investigación de incidentes |
| AZs por índice del data source | AZs fijadas explícitamente, o por `zone_id` |
