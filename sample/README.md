# Ejemplo de Uso del Módulo SES

Ejemplo funcional del módulo SES siguiendo el patrón PC-IAC-026. Todos los valores son **dummy** (`acme`, `example.com`, cuenta delegada `222222222222`); reemplázalos por los de tu proyecto.

**Caso de ejemplo:** la cuenta dueña verifica el dominio `example.com` con DKIM de 2048 bits y MAIL FROM `mail.example.com`. Envía los eventos BOUNCE y COMPLAINT a un topic SNS y autoriza al rol de una lambda de la cuenta `222222222222` a enviar **solo** como `no-reply@example.com`.

## 📋 Estructura del Ejemplo

```
sample/
├── README.md           # Este archivo
├── terraform.tfvars    # Configuración declarativa (datos dummy)
├── variables.tf        # Definición de variables
├── data.tf             # Data sources para ARN/IDs dinámicos
├── locals.tf           # Transformaciones y nombres finales
├── main.tf             # Invocación del módulo
├── outputs.tf          # Outputs del ejemplo
└── providers.tf        # Provider aws.principal, versiones y backend
```

## 🔄 Flujo de Datos (PC-IAC-026)

```
terraform.tfvars → variables.tf → data.tf → locals.tf → main.tf → módulo
    (config)        (tipos)     (consulta)  (transform)  (invoca)
```

### 1. `terraform.tfvars`
Configuración declarativa sin IDs de la cuenta:
- `use_sns_topic = true`: el ARN del topic se inyecta desde `data.tf`.
- `delegated_sender_key = "invoice-sender"`: el ARN del rol **no se escribe**. `locals.tf` lo arma a partir de `delegated_senders` con la convención del módulo IAM de somospragma (`role<path>{client}-{project}-{environment}-role-{service}-{application}-{functionality}`):
  `arn:aws:iam::222222222222:role/service-role/acme-billing-dev-role-lambda-billing-invoice-sender`. La cuenta delegada es externa y no se puede consultar con data sources.
- `common_tags` y `additional_tags` van con llaves y valores en minúscula.

### 2. `variables.tf`
Tipos y validaciones, incluido `common_tags` con las 5 etiquetas transversales mínimas en minúscula (`client`, `project`, `environment`, `owner`, `costcenter`).

### 3. `data.tf`
- `aws_partition.current`: partición para construir el ARN del rol delegado.
- `aws_caller_identity.current`: cuenta dueña de las identidades, se pasa como `account_id`.
- `aws_sns_topic.ses_events`: topic existente `acme-notif-dev-sns-ses-events`, creado con el módulo SNS de somospragma.

### 4. `locals.tf`
Construye los nombres finales (PC-IAC-025), el ARN del rol delegado y el ARN del topic SNS:

| Recurso | Nombre |
|---|---|
| Configuration set | `acme-notif-dev-ses-default` |
| Event destination | `acme-notif-dev-ses-events` |
| Política de envío | `acme-notif-dev-ses-main` |

### 5. `main.tf`
Solo invoca el módulo con `local.*`, en el orden de PC-IAC-013.

## 🏷️ Tags

El módulo no agrega tags propios. Cada recurso recibe:
- los tags transversales de `default_tags` del provider (`common_tags`);
- el tag `name` con el nombre del recurso (PC-IAC-004);
- los `additional_tags` de cada entrada.

## 🚀 Cómo Ejecutar

### Prerrequisitos

1. Rol de despliegue en la cuenta dueña, inyectado como `TF_VAR_deploy_role_arn`.
2. Bucket S3 de estado para el backend.
3. Topic SNS `{client}-{project}-{environment}-sns-ses-events` con una política que permita a `ses.amazonaws.com` publicar.
4. Partes del nombre del rol delegado en `delegated_senders`, según la convención del módulo IAM de somospragma.
5. Terraform >= 1.5.0.

### Pasos

```bash
export TF_VAR_deploy_role_arn="arn:aws:iam::<cuenta-duena>:role/<rol-de-despliegue>"

terraform init \
  -backend-config="bucket=<bucket-de-estado>" \
  -backend-config="key=ses/dev/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Para validar sin backend: `terraform init -backend=false && terraform validate`.

## 🌐 DNS

El módulo no crea DNS. Después del apply:

```bash
terraform output dns_records
```

Publica en la zona pública del dominio los 3 CNAME de DKIM, el MX y el TXT SPF del subdominio MAIL FROM, y evalúa el DMARC sugerido.

## ✅ Pasos fuera de Terraform

- **Sandbox:** cada cuenta que **envía** solicita producción, tanto la dueña como la delegada, porque el envío delegado cuenta contra la cuota y el sandbox de la cuenta delegada.
  ```bash
  aws sesv2 put-account-details --production-access-enabled \
    --mail-type TRANSACTIONAL --website-url https://example.com \
    --use-case-description "..." --contact-language ES
  ```
- **IAM en la cuenta delegada:** el rol necesita `ses:SendEmail`/`ses:SendRawEmail` sobre el ARN de la identidad (output `identity_arns`). Al enviar usa ese ARN como `FromEmailAddressIdentityArn` y una dirección de `allowed_from_addresses` como remitente.

## 🧹 Limpieza

La identidad tiene `prevent_destroy = true` (PC-IAC-010): `terraform destroy` falla a propósito. Destruir la identidad invalida los registros DKIM publicados, y al recrearla se generan tokens nuevos.
