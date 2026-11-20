# Transformaciones del ejemplo (PC-IAC-026, PC-IAC-025, PC-IAC-009)
locals {
  # Prefijo de gobernanza para el ejemplo (PC-IAC-025)
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  # ARN de los roles delegados según la convención del módulo IAM de somospragma:
  # role<path>{client}-{project}-{environment}-role-{service}-{application}-{functionality}
  delegated_sender_role_arns = {
    for key, sender in var.delegated_senders :
    key => "arn:${data.aws_partition.current.partition}:iam::${sender.account_id}:role${sender.path}${join("-", [sender.client, sender.project, sender.environment, "role", sender.service, sender.application, sender.functionality])}"
  }

  # Identidades: nombre final de la política (PC-IAC-025) y ARN del rol delegado (PC-IAC-009)
  ses_identities_config_transformed = {
    for key, config in var.ses_identities_config : key => merge(config, {
      policy_name = "${local.governance_prefix}-ses-${key}"
      sending_authorization = {
        for sid, statement in config.sending_authorization : sid => {
          principals             = length(statement.principals) > 0 ? statement.principals : [local.delegated_sender_role_arns[statement.delegated_sender_key]]
          actions                = statement.actions
          allowed_from_addresses = statement.allowed_from_addresses
          source_accounts        = statement.source_accounts
        }
      }
    })
  }

  # Configuration sets: nombres finales (PC-IAC-025) e inyección del ARN del topic SNS (PC-IAC-009)
  ses_configuration_sets_config_transformed = {
    for key, config in var.ses_configuration_sets_config : key => merge(config, {
      configuration_set_name = "${local.governance_prefix}-ses-${key}"
      event_destinations = {
        for dest_key, destination in config.event_destinations : dest_key => {
          event_destination_name = "${local.governance_prefix}-ses-${dest_key}"
          enabled                = destination.enabled
          matching_event_types   = destination.matching_event_types
          sns_topic_arn          = destination.use_sns_topic && length(destination.sns_topic_arn) == 0 ? data.aws_sns_topic.ses_events.arn : destination.sns_topic_arn
          event_bus_arn          = destination.event_bus_arn
          cloudwatch_dimensions  = destination.cloudwatch_dimensions
        }
      }
    })
  }
}
