# Changelog

Todos los cambios notables en este proyecto serán documentados en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es/1.0.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [Unreleased]

## [1.0.0] - 2026-11-20

### Added

- Identidades SES API v2 (`aws_sesv2_email_identity`) de tipo `DOMAIN` o `EMAIL` mediante `ses_identities_config`, con Easy DKIM (`RSA_2048_BIT` por defecto), configuration set por defecto opcional y `prevent_destroy`.
- MAIL FROM personalizado (`aws_sesv2_email_identity_mail_from_attributes`) para identidades `DOMAIN`, validado como subdominio de la identidad.
- Política de sending authorization por identidad (`aws_sesv2_email_identity_policy`) con statements como mapa por `Sid` y condiciones `ses:FromAddress` y `aws:SourceAccount`.
- Configuration sets (`aws_sesv2_configuration_set`) con TLS `REQUIRE` por defecto, métricas de reputación y supresión de `BOUNCE`/`COMPLAINT`.
- Destinos de eventos (`aws_sesv2_configuration_set_event_destination`) como mapa, hacia SNS, EventBridge (bus default) o CloudWatch.
- Variable transversal `account_id` para detectar principals de otra cuenta en `plan`.
- Nombres finales inyectables desde el Root (`configuration_set_name`, `event_destination_name`, `policy_name`) con límite de 28 caracteres.
- Outputs `identity_arns`, `identity_dkim_tokens`, `dns_records`, `configuration_set_names`, `configuration_set_arns` e `identity_policy_names`.
- Validaciones de seguridad (PC-IAC-020): sin comodines en principals, acciones ni remitentes; `allowed_from_addresses` obligatorio para principals de otra cuenta; `tls_policy = OPTIONAL` solo con `allow_optional_tls = true`.
- Pruebas automatizadas en `tests/` con provider mock (PC-IAC-018).
- Ejemplo `sample/` con identidad de dominio, MAIL FROM, eventos a SNS y envío delegado cross-account (PC-IAC-026).
