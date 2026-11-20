# cloudops-ref-repo-aws-ses-terraform

Módulo de referencia de Terraform para **Amazon SES (API v2)**. Crea identidades de envío (dominio o correo) con Easy DKIM, MAIL FROM personalizado, políticas de *sending authorization* para envío cross-account y configuration sets con TLS obligatorio y destinos de eventos (SNS, EventBridge o CloudWatch). Expone los registros DNS que se deben publicar en la zona pública del dominio.

Cumple las 26 reglas de gobernanza PC-IAC de Pragma (MCP `sopp-cloudops-ai`).

## Recursos creados

| Recurso | Cantidad | Nombre |
|---|---|---|
| `aws_sesv2_email_identity` | 1 por entrada de `ses_identities_config` | El dominio o correo real (sin prefijo) |
| `aws_sesv2_email_identity_mail_from_attributes` | 1 por identidad DOMAIN con `mail_from` | n/a |
| `aws_sesv2_email_identity_policy` | 1 por identidad con `sending_authorization` | `{client}-{project}-{environment}-ses-{identity_key}` |
| `aws_sesv2_configuration_set` | 1 por entrada de `ses_configuration_sets_config` | `{client}-{project}-{environment}-ses-{key}` |
| `aws_sesv2_configuration_set_event_destination` | 1 por entrada de `event_destinations` | `{client}-{project}-{environment}-ses-{destination_key}` |

Los nombres pueden llegar ya construidos desde el Root (`configuration_set_name`, `event_destination_name`, `policy_name`) según PC-IAC-025; si vienen vacíos, el módulo los construye en `locals.tf` con el mismo patrón. En ambos casos el nombre final debe tener **máximo 28 caracteres** (PC-IAC-003).

**Fuera del alcance (PC-IAC-023):** registros DNS (Route 53 u otro proveedor), roles y políticas IAM, topics SNS, recursos de nivel cuenta (`aws_sesv2_account_suppression_attributes`, `aws_sesv2_account_vdm_attributes`), receipt rules, dedicated IP pools y templates.

## Requisitos

| Nombre | Versión |
|---|---|
| Terraform | >= 1.5.0 (`optional()` con defaults, preconditions, `endswith()`) |
| hashicorp/aws | >= 6.0.0 (recursos `aws_sesv2_*` y atributo `region`) |

El módulo **no declara provider**: lo recibe desde el Root mediante el alias `aws.project` (PC-IAC-005).

## Uso

```hcl
module "ses" {
  # A. Fuente del módulo (PC-IAC-015)
  source = "git::https://github.com/somospragma/cloudops-ref-repo-aws-ses-terraform.git?ref=v1.0.0"

  # B. Providers (PC-IAC-005)
  providers = {
    aws.project = aws.principal
  }

  # C. Variables de Gobernanza (PC-IAC-003)
  client      = var.client
  project     = var.project
  environment = var.environment

  # D. Variables Transversales (PC-IAC-011)
  account_id = data.aws_caller_identity.current.account_id

  # E. Configuración transformada desde locals (PC-IAC-021, PC-IAC-026)
  ses_identities_config         = local.ses_identities_config_transformed
  ses_configuration_sets_config = local.ses_configuration_sets_config_transformed
}
```

Configuración de ejemplo, ya transformada en `locals.tf` del Root (ver `sample/`):

```hcl
ses_identities_config = {
  "pragma" = {
    identity              = "pragma.com.co"
    identity_type         = "DOMAIN"
    configuration_set_key = "default"
    policy_name           = "pragma-notif-pdn-ses-pragma"
    mail_from             = { domain = "mail.pragma.com.co" }
    sending_authorization = {
      "AllowLicenseProcessingLambda" = {
        principals             = ["arn:aws:iam::533267042257:role/<rol-de-la-lambda>"]
        allowed_from_addresses = ["licenciasgenial@pragma.com.co"]
      }
    }
    functionality = "transactional-email"
  }
}

ses_configuration_sets_config = {
  "default" = {
    configuration_set_name = "pragma-notif-pdn-ses-default"
    event_destinations = {
      "events" = {
        event_destination_name = "pragma-notif-pdn-ses-events"
        matching_event_types   = ["BOUNCE", "COMPLAINT"]
        sns_topic_arn          = "<ARN desde data.aws_sns_topic>"
      }
    }
    functionality = "transactional-email"
  }
}
```

## Inputs

### Variables de gobernanza (PC-IAC-002)

| Nombre | Tipo | Requerido | Validación |
|---|---|---|---|
| `client` | `string` | Sí | 1-10 caracteres, `^[a-z0-9-]+$` |
| `project` | `string` | Sí | 1-15 caracteres, `^[a-z0-9-]+$` |
| `environment` | `string` | Sí | `dev`, `qa`, `stg`, `pdn`, `prod` |

### Variables transversales

| Nombre | Tipo | Requerido | Descripción |
|---|---|---|---|
| `account_id` | `string` | Sí | Cuenta dueña de las identidades (12 dígitos). Se usa para detectar principals de otra cuenta en `plan`. |

### `ses_identities_config` (`map(object)`, default `{}`)

La key del mapa (`^[a-z0-9-]+$`, máximo 20 caracteres) nombra la política y los outputs.

| Atributo | Tipo | Default | Descripción |
|---|---|---|---|
| `identity` | `string` | n/a | Dominio (`pragma.com.co`) o correo (`user@pragma.com.co`). Se valida el formato según `identity_type`. |
| `identity_type` | `string` | n/a | `DOMAIN` o `EMAIL`. |
| `dkim_signing_key_length` | `string` | `RSA_2048_BIT` | Easy DKIM, solo DOMAIN. `RSA_1024_BIT` o `RSA_2048_BIT`. |
| `configuration_set_key` | `string` | `""` | Key de `ses_configuration_sets_config` usada por defecto. Debe existir. |
| `policy_name` | `string` | `""` | Nombre final de la política inyectado por el Root (máximo 28). |
| `mail_from` | `object` | `null` | `{ domain, behavior_on_mx_failure = "USE_DEFAULT_VALUE" }`. Solo DOMAIN; `domain` debe ser subdominio de `identity`. |
| `sending_authorization` | `map(object)` | `{}` | Statements de envío delegado; la key es el `Sid` (alfanumérico). Ver tabla siguiente. |
| `functionality` | `string` | n/a | Tag `Functionality`. |
| `additional_tags` | `map(string)` | `{}` | Tags propios de la identidad. |

`sending_authorization[<Sid>]`:

| Atributo | Tipo | Default | Descripción |
|---|---|---|---|
| `principals` | `list(string)` | n/a | ARN de cuenta (`arn:aws:iam::<id>:root`) o de rol (`arn:aws:iam::<id>:role/<nombre>`). No se permite `*`. |
| `actions` | `list(string)` | `["ses:SendEmail", "ses:SendRawEmail"]` | Subconjunto de acciones de envío de SES. No se permiten comodines. |
| `allowed_from_addresses` | `list(string)` | `[]` | Condición `StringEquals ses:FromAddress`. Direcciones explícitas del dominio, sin comodines. **Obligatoria si algún principal no pertenece a `account_id`.** |
| `source_accounts` | `list(string)` | `[]` | Condición `StringEquals aws:SourceAccount`. Ver [Decisiones de diseño](#decisiones-de-diseño). |

### `ses_configuration_sets_config` (`map(object)`, default `{}`)

| Atributo | Tipo | Default | Descripción |
|---|---|---|---|
| `configuration_set_name` | `string` | `""` | Nombre final inyectado por el Root (máximo 28). |
| `tls_policy` | `string` | `REQUIRE` | `REQUIRE` u `OPTIONAL`. `OPTIONAL` exige `allow_optional_tls = true`. |
| `allow_optional_tls` | `bool` | `false` | Flag explícito para permitir TLS opcional. |
| `reputation_metrics_enabled` | `bool` | `true` | Métricas de reputación. |
| `sending_enabled` | `bool` | `true` | Habilita el envío con el configuration set. |
| `suppressed_reasons` | `list(string)` | `["BOUNCE", "COMPLAINT"]` | Razones de supresión. |
| `event_destinations` | `map(object)` | `{}` | Ver tabla siguiente. |
| `functionality` | `string` | n/a | Tag `Functionality`. |
| `additional_tags` | `map(string)` | `{}` | Tags propios. |

`event_destinations[<key>]`, con exactamente uno de `sns_topic_arn`, `event_bus_arn` o `cloudwatch_dimensions`:

| Atributo | Tipo | Default | Descripción |
|---|---|---|---|
| `event_destination_name` | `string` | `""` | Nombre final inyectado por el Root (máximo 28). |
| `enabled` | `bool` | `true` | Habilita el destino. |
| `matching_event_types` | `list(string)` | n/a | `SEND`, `REJECT`, `BOUNCE`, `COMPLAINT`, `DELIVERY`, `OPEN`, `CLICK`, `RENDERING_FAILURE`, `DELIVERY_DELAY`, `SUBSCRIPTION`. |
| `sns_topic_arn` | `string` | `""` | ARN del topic SNS. |
| `event_bus_arn` | `string` | `""` | ARN del bus **default** de EventBridge (único soportado por SES). |
| `cloudwatch_dimensions` | `list(object)` | `[]` | `{ dimension_name, dimension_value_source (MESSAGE_TAG \| EMAIL_HEADER \| LINK_TAG), default_dimension_value }`. |

## Outputs

| Nombre | Descripción |
|---|---|
| `identity_arns` | Mapa `identity_key => ARN` de la identidad. |
| `identity_dkim_tokens` | Mapa `identity_key => [tokens]` de Easy DKIM (solo DOMAIN). |
| `dns_records` | Mapa `identity_key => [{ name, type, ttl, value }]`: 3 CNAME de DKIM, MX y TXT SPF de MAIL FROM y un DMARC sugerido. Lista vacía para EMAIL. |
| `configuration_set_names` | Mapa `key => nombre` del configuration set. |
| `configuration_set_arns` | Mapa `key => ARN` del configuration set. |
| `identity_policy_names` | Mapa `identity_key => nombre` de la política de sending authorization. |

Formato de `dns_records` para `pragma.com.co` con MAIL FROM `mail.pragma.com.co` en `us-east-1`:

| name | type | value |
|---|---|---|
| `<token>._domainkey.pragma.com.co` (x3) | CNAME | `<token>.dkim.amazonses.com` |
| `mail.pragma.com.co` | MX | `10 feedback-smtp.us-east-1.amazonses.com` |
| `mail.pragma.com.co` | TXT | `v=spf1 include:amazonses.com ~all` |
| `_dmarc.pragma.com.co` | TXT | `v=DMARC1; p=none;` (sugerido) |

## Qué queda fuera del módulo

- **Salida del sandbox.** No es Terraform. La solicita **cada cuenta que envía** con `aws sesv2 put-account-details --production-access-enabled ...` o un caso a AWS Support. Mientras la cuenta esté en sandbox solo puede enviar a direcciones verificadas.
- **Cuota y sandbox en envío cross-account.** Con sending authorization el correo cuenta contra la cuota de envío, la reputación y el estado de sandbox de la **cuenta que envía** (la delegada), no de la dueña de la identidad. La cuenta delegada debe salir de su propio sandbox, y su rol necesita permisos IAM `ses:SendEmail`/`ses:SendRawEmail` sobre el ARN de la identidad.
- **DNS.** Publica el output `dns_records` en la zona pública del dominio desde el dominio de Networking/DNS, que puede estar en otra cuenta (PC-IAC-022, PC-IAC-023).
- **DMARC.** El módulo solo lo sugiere; la política DMARC del dominio la decide su dueño. Empieza con `p=none` y un `rua`, y sube a `quarantine`/`reject` cuando DKIM y SPF estén alineados.
- **Tags transversales.** `Client`, `Project`, `Environment`, `Owner` y `CostCenter` llegan por `default_tags` del provider en el Root (PC-IAC-004).

## Cumplimiento PC-IAC

| Regla | Implementación |
|---|---|
| PC-IAC-001 | 10 archivos raíz y `sample/` con los 8 archivos del patrón PC-IAC-026. |
| PC-IAC-002 / 024 | Toda variable con `type`, `description` y `validation`; colecciones `map(object)` con `optional()` y `default = {}`. |
| PC-IAC-003 / 025 | `{client}-{project}-{environment}-ses-{key}` de máximo 28 caracteres; el Root puede inyectar el nombre final. La identidad conserva su nombre real. |
| PC-IAC-004 / 012 | `Name` explícito + `local.base_module_tags` + `additional_tags`; tags transversales por `default_tags`. |
| PC-IAC-005 / 006 | Sin bloque provider; `configuration_aliases = [aws.project]`; `provider = aws.project` en cada recurso. |
| PC-IAC-007 / 014 | Outputs granulares como mapas por key; bloques `dynamic` para destinos y dimensiones. |
| PC-IAC-009 / 010 / 012 | Strings opcionales con `""` y `length() ? :`; `flatten()` + mapa para `for_each`; `prevent_destroy` en la identidad. |
| PC-IAC-011 / 023 | Sin data sources; solo recursos intrínsecos a SES (sin DNS, IAM ni SNS). |
| PC-IAC-018 | `tests/ses_module.tftest.hcl` (25 pruebas con provider mock). |
| PC-IAC-020 | TLS `REQUIRE`, DKIM 2048, sin comodines en principals, acciones ni remitentes, `ses:FromAddress` obligatorio en cross-account, supresión de BOUNCE/COMPLAINT. |

## Decisiones de diseño

- **Cross-account en `plan`.** El Root inyecta `account_id` (desde `data.aws_caller_identity`). Una precondition de la política falla en `plan` si un statement tiene principals de otra cuenta y no restringe `ses:FromAddress`.
- **`source_accounts` (`aws:SourceAccount`).** AWS solo incluye esta clave cuando un **servicio** de AWS llama a nombre de un recurso. Si un rol IAM llama a `SendEmail` directamente (por ejemplo una Lambda), la clave no existe y la condición deniega el envío. Úsala solo en integraciones servicio a servicio; para roles, el ARN del principal ya fija la cuenta. El sample no la usa.
- **`prevent_destroy` en la identidad (PC-IAC-010).** Recrear la identidad genera tokens DKIM nuevos, rompe el DNS publicado y pierde la verificación. Para eliminarla hay que quitar el bloque en una rama del módulo.
- **Region del MX.** El registro MX de MAIL FROM usa el atributo `region` de la identidad (provider 6.x), sin data sources.
- **Sin Route 53 (PC-IAC-023).** El DNS pertenece a otro dominio de infraestructura; el módulo entrega `dns_records` listo para publicar.

## Pruebas y validación (PC-IAC-018)

```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform test        # tests/ con provider mock
cd sample && terraform init -backend=false && terraform validate
checkov -d . --framework terraform
```
