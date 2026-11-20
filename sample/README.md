# Ejemplo de Uso del Módulo SES

Ejemplo funcional del módulo SES siguiendo el patrón PC-IAC-026.

**Caso de uso:** la cuenta pragma-main (654767188854) verifica el dominio `pragma.com.co` con DKIM de 2048 bits y MAIL FROM `mail.pragma.com.co`. Envía los eventos BOUNCE y COMPLAINT a un topic SNS y autoriza al rol de la lambda license-processing de la cuenta 533267042257 a enviar **solo** como `licenciasgenial@pragma.com.co`.

## 📋 Estructura del Ejemplo

```
sample/
├── README.md           # Este archivo
├── terraform.tfvars    # Configuración declarativa
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
- `delegated_sender_key = "license-processing"`: el ARN del rol se arma en `locals.tf` a partir de `delegated_senders`. La cuenta 533267042257 es externa y no se puede consultar con data sources.

### 2. `variables.tf`
Tipos y validaciones, incluido `common_tags` con las 5 etiquetas transversales mínimas.

### 3. `data.tf`
- `aws_caller_identity.current`: cuenta dueña de las identidades, se pasa como `account_id`.
- `aws_sns_topic.ses_events`: topic existente `pragma-notif-pdn-sns-ses-events`, creado con el módulo SNS de somospragma.

### 4. `locals.tf`
Construye los nombres finales (PC-IAC-025), el ARN del rol delegado y el ARN del topic SNS:

| Recurso | Nombre |
|---|---|
| Configuration set | `pragma-notif-pdn-ses-default` |
| Event destination | `pragma-notif-pdn-ses-events` |
| Política de envío | `pragma-notif-pdn-ses-pragma` |

### 5. `main.tf`
Solo invoca el módulo con `local.*`, en el orden de PC-IAC-013.

## 🚀 Cómo Ejecutar

### Prerrequisitos

1. Rol de despliegue en la cuenta 654767188854, inyectado como `TF_VAR_deploy_role_arn`.
2. Bucket S3 de estado para el backend.
3. Topic SNS `pragma-notif-pdn-sns-ses-events` con una política que permita a `ses.amazonaws.com` publicar.
4. Nombre real del rol de la lambda en `delegated_senders["license-processing"].role_name`.
5. Terraform >= 1.5.0.

### Pasos

```bash
export TF_VAR_deploy_role_arn="arn:aws:iam::654767188854:role/<rol-de-despliegue>"

terraform init \
  -backend-config="bucket=<bucket-de-estado>" \
  -backend-config="key=ses/pdn/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Para validar sin backend: `terraform init -backend=false && terraform validate`.

## 🌐 DNS

La zona pública de `pragma.com.co` la gestiona el dominio de Networking/DNS. Después del apply:

```bash
terraform output dns_records
```

Publica allí los 3 CNAME de DKIM, el MX y el TXT SPF de `mail.pragma.com.co`, y evalúa el DMARC sugerido.

## ✅ Pasos fuera de Terraform

- **Sandbox:** cada cuenta que **envía** solicita producción: la 654767188854 y también la 533267042257, porque el envío delegado cuenta contra la cuota y el sandbox de la cuenta delegada.
  ```bash
  aws sesv2 put-account-details --production-access-enabled \
    --mail-type TRANSACTIONAL --website-url https://pragma.com.co \
    --use-case-description "..." --contact-language ES
  ```
- **IAM en la cuenta 533267042257:** el rol de la lambda necesita `ses:SendEmail`/`ses:SendRawEmail` sobre `arn:aws:ses:us-east-1:654767188854:identity/pragma.com.co`. Al enviar usa ese ARN como `FromEmailAddressIdentityArn` y `licenciasgenial@pragma.com.co` como remitente.

## 🧹 Limpieza

La identidad tiene `prevent_destroy = true` (PC-IAC-010): `terraform destroy` falla a propósito. Destruir la identidad invalida los registros DKIM publicados, y al recrearla se generan tokens nuevos.
