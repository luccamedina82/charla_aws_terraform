# Laboratorio 3 — Infraestructura como código

Una trivia en vivo (Trivia AWS Builders) corriendo en AWS con alta disponibilidad,
levantada entera con Terraform: red, cómputo, base de datos, balanceo, HTTPS y
despliegue automático. No se crea nada a mano desde la consola, salvo la hosted zone
`charla.tekforge.site` y la imagen `bootstrap`.

Este README da el panorama general. Cada módulo tiene su propio `README.md` con el
detalle.

**Equipo**: Lucca Medina y Maxi · **Región**: `us-east-1` · **Sitio**: `https://charla.tekforge.site`
**Repositorio de la aplicación**: [`charla_aws_app`](https://github.com/luccamedina82/charla_aws_app)

---

## Qué se levanta

```
                              Internet
                                 |
                            Route 53
                                 |
                    +------------v-------------+
                    |   Application Load       |   subredes públicas
                    |   Balancer               |   HTTPS 443, certificado de ACM
                    |   HTTP 80 -> 301         |
                    +------------+-------------+
                                 |
              +------------------+------------------+
              |                                     |
        +-----v------+                        +-----v------+
        |  frontend  |  us-east-1a            |  frontend  |  us-east-1b
        |  Node.js   |                        |  Node.js   |
        +-----+------+                        +-----+------+
              |                                     |
              +------------------+------------------+
                                 |
                        mysql.lab3.local
                                 |
                          +------v------+
                          |    MySQL    |            subredes privadas
                          +------+------+
                                 |
                          +------v------+
                          |     EFS     |   los datos sobreviven a la task
                          +-------------+
```

El tráfico entra por HTTPS, el balanceador lo reparte entre **dos copias de la
aplicación en zonas de disponibilidad distintas**, y esas copias hablan con una base de
datos MySQL que corre en un contenedor. Los datos de la base no viven adentro del
contenedor: viven en un disco de red (EFS). Si el contenedor muere, ECS levanta otro y
los datos siguen ahí.

La aplicación **nunca conoce la dirección IP de la base**. La busca por nombre
(`mysql.lab3.local`) a través de Cloud Map, el servicio de descubrimiento de AWS. Es la
diferencia entre que la base se reinicie sin que nadie lo note y una caída de dos horas.

Alrededor de eso hay dos circuitos más:

- **Despliegue automático**: un push al repositorio de la aplicación construye la imagen,
  la sube al registro y actualiza el servicio, sin que nadie toque nada.
- **Monitoreo**: un tablero con métricas de infraestructura y de negocio, y alarmas que
  avisan por mail.

---

## Cómo está organizado el repositorio

```
charla_aws_terraform/
├── backend/              El bucket donde vive el estado de Terraform
├── environments/dev/     El entorno: qué módulos se usan y con qué valores
├── modules/              Las piezas reutilizables, una por responsabilidad
├── docs/                 Runbook, decisiones y estado del proyecto
└── .github/workflows/    Validación automática en cada pull request
```

La separación tiene un motivo concreto en cada caso:

**`backend/` está aparte** porque resuelve un problema del huevo y la gallina:
Terraform guarda su estado en un bucket de S3, pero ese bucket también hay que crearlo
con Terraform. `backend/` se ejecuta una sola vez, con el estado en disco, y crea el
bucket que usa todo lo demás.

**`environments/` es la única capa que decide.** Ahí se elige qué módulos se invocan y
con qué valores. No contiene ni un solo recurso de AWS declarado directamente: si
hiciera falta uno, significa que falta un módulo.

**`modules/` no decide nada.** Cada módulo recibe parámetros y devuelve resultados. No
sabe en qué entorno está ni fija credenciales, que es lo que lo hace reutilizable.

**`docs/` es lo que hace el proyecto reproducible por otra persona.** El runbook está
escrito para seguirse al pie de la letra.

---

## Los módulos

Cada uno agrupa recursos que se crean, cambian y se destruyen juntos. El límite no es el
servicio de AWS, es el ciclo de vida.

| Módulo | Qué resuelve |
|---|---|
| `network` | La red privada: VPC, subredes en dos zonas, salida a internet |
| `security-groups` | Quién puede hablar con quién, en cadena y por referencia |
| `ecr` | El registro donde viven las imágenes de la aplicación |
| `ecs-cluster` | Las máquinas que ejecutan los contenedores, y su escalado |
| `efs` | El disco de red donde persisten los datos de MySQL |
| `ssm-parameters` | La configuración y las contraseñas, fuera del código |
| `ecs-service` | Cómo se ejecuta un contenedor. Se usa dos veces: MySQL y frontend |
| `alb` | El balanceador y el despliegue sin interrupciones |
| `acm` | El certificado de HTTPS y su validación |
| `dns` | El nombre público apuntando al balanceador |
| `notifications` | El canal por donde salen los avisos por mail |
| `cicd` | El pipeline que construye y despliega la aplicación |

Que `ecs-service` se invoque **dos veces** con configuraciones distintas —una base de
datos con disco persistente, un frontend detrás del balanceador— es la mejor prueba de
que los módulos están bien recortados.

---

## Los recursos que se crean

| Capa | Qué hay |
|---|---|
| Red | 1 VPC, 4 subredes en 2 zonas, gateway de internet, 1 NAT, tablas de ruteo |
| Seguridad | 5 grupos de seguridad encadenados, roles y políticas de IAM por servicio |
| Cómputo | 1 cluster ECS, 3 instancias EC2 en auto scaling, 2 servicios, 3 contenedores |
| Datos | 1 sistema de archivos EFS con punto de montaje por zona, 6 parámetros en SSM |
| Entrada | 1 balanceador, 2 grupos de destino, certificado de ACM, registro en Route 53 |
| Despliegue | Registro ECR, pipeline de 3 etapas, proyecto de build, bucket de artefactos |
| Monitoreo | 1 tablero, 6 alarmas, 1 tópico de notificaciones |

---

## Las decisiones que definen el proyecto

**La base de datos corre en un contenedor, no en RDS.** Lo pide la consigna. En
producción sería RDS Multi-AZ: replicación, backups y parches sin intervención. Acá el
equivalente se consigue combinando EFS para los datos y ECS para reponer el contenedor.

**Despliegue azul/verde.** Cuando sale una versión nueva, ECS levanta las copias nuevas
en paralelo con las viejas y solo mueve el tráfico cuando están sanas. Si algo falla, el
tráfico nunca llegó a moverse. Cuesta un segundo grupo de destino en el balanceador.

**Un solo NAT Gateway.** Lo correcto es uno por zona de disponibilidad. Se usa uno por
costo, y queda documentado como tal: es la pieza que en producción se duplicaría primero.

**Las contraseñas nunca están en el código ni en la definición del contenedor.** Viven
cifradas en Parameter Store, y lo que se guarda en la definición de la tarea es la
dirección del parámetro, no su valor. ECS lo resuelve al arrancar el contenedor.

**El estado de Terraform se bloquea sin DynamoDB.** S3 incorporó bloqueo nativo, así que
la tabla que históricamente hacía falta ya no existe. Requiere Terraform 1.11 o superior.

**Los módulos son propios, no de la comunidad.** Con una excepción evaluada y descartada
—la red, donde el módulo público es una opción razonable— el resto resuelve
particularidades de esta arquitectura que un módulo genérico obligaría a parchear desde
afuera. El razonamiento módulo por módulo está en
[`docs/decisiones-modulos.md`](docs/decisiones-modulos.md).

**Dos pasos son manuales, a propósito.** Subir la primera imagen al registro (sin imagen,
el servicio nunca arranca, y sin servicio no hay a dónde subirla) y autorizar la conexión
con GitHub (un permiso OAuth que no tiene API). Ambos están en el runbook.

---

## Cómo levantarlo

El procedimiento completo, en orden y con las verificaciones de cada paso, está en
**[`docs/runbook.md`](docs/runbook.md)**. En resumen:

```bash
# 1. El bucket del estado, una sola vez
terraform -chdir=backend init && terraform -chdir=backend apply

# 2. El entorno
terraform -chdir=environments/dev init
terraform -chdir=environments/dev plan
terraform -chdir=environments/dev apply
```

Entre medio va el push de la primera imagen. El runbook indica exactamente dónde.

Al terminar, `terraform output` devuelve la URL del sitio, el DNS del balanceador y el
enlace al tablero de métricas.

---

## Documentación

| Documento | Para qué |
|---|---|
| [`docs/runbook.md`](docs/runbook.md) | Levantar el entorno desde cero, y operarlo |
| [`docs/decisiones-modulos.md`](docs/decisiones-modulos.md) | Por qué cada módulo es propio |
| [`docs/estado-actual.md`](docs/estado-actual.md) | Estado real, verificaciones y trampas ya resueltas |
| [`CONVENCIONES.md`](CONVENCIONES.md) | Reglas de código, nombres y flujo de trabajo |
| [`PLAN-FASES.md`](PLAN-FASES.md) | Las diez fases y el criterio de cierre de cada una |
| `modules/*/README.md` | El detalle técnico de cada pieza |

---

## Qué cambiaría en producción

Cada módulo cierra con su propia tabla de esto. Lo transversal:

| Acá | En producción |
|---|---|
| MySQL en contenedor sobre EFS | RDS Multi-AZ, con backups automáticos |
| Un NAT Gateway | Uno por zona de disponibilidad |
| Dos zonas de disponibilidad | Tres, que es el mínimo para quórum |
| Umbrales de alarma estimados | Derivados de un objetivo de servicio acordado |
| Alarmas al mail | Guardias con escalamiento |
| Un solo entorno | `dev`, `staging` y `prod` con estados separados |
