# Variables del ejemplo (PC-IAC-002, PC-IAC-016, PC-IAC-024)

###########################################
### Variables de Gobernanza (PC-IAC-002) ###
###########################################

variable "client" {
  description = "Client name for resource naming"
  type        = string

  validation {
    condition     = length(var.client) > 0 && length(var.client) <= 10
    error_message = "Client name must be between 1 and 10 characters."
  }
}

variable "project" {
  description = "Project name for resource naming"
  type        = string

  validation {
    condition     = length(var.project) > 0 && length(var.project) <= 15
    error_message = "Project name must be between 1 and 15 characters."
  }
}

variable "environment" {
  description = "Environment where resources will be deployed"
  type        = string

  validation {
    condition     = contains(["dev", "qa", "stg", "pdn", "prod"], var.environment)
    error_message = "Environment must be one of: dev, qa, stg, pdn, prod."
  }
}

###########################################
######## Provider (PC-IAC-005) ############
###########################################

variable "region" {
  description = "AWS region for resource deployment"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region (e.g. us-east-1)."
  }
}

variable "deploy_role_arn" {
  description = "ARN of the IAM role assumed by the provider to deploy (least privilege). Inject it from the pipeline (TF_VAR_deploy_role_arn); do not commit it in tfvars."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.deploy_role_arn))
    error_message = "deploy_role_arn must be a valid IAM role ARN."
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources through provider default_tags (PC-IAC-004)"
  type        = map(string)

  validation {
    condition = alltrue([
      for tag in ["Client", "Project", "Environment", "Owner", "CostCenter"] :
      contains(keys(var.common_tags), tag)
    ])
    error_message = "common_tags must include: Client, Project, Environment, Owner, CostCenter."
  }
}

###########################################
######## Cross-account senders ############
###########################################

variable "delegated_senders" {
  description = "Map of delegated (cross-account) senders. locals.tf builds the principal ARN of the sending_authorization statements that reference delegated_sender_key."
  type = map(object({
    account_id = string
    role_name  = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.delegated_senders :
      can(regex("^[0-9]{12}$", v.account_id)) && length(v.role_name) > 0
    ])
    error_message = "delegated_senders.account_id must be a 12-digit AWS account ID and role_name cannot be empty."
  }
}

###########################################
######## Data sources (PC-IAC-011) ########
###########################################

variable "ses_events_sns_topic_key" {
  description = "Key of the existing SNS topic (created with the somospragma SNS module) that receives SES events. Looked up as {client}-{project}-{environment}-sns-{key}."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.ses_events_sns_topic_key))
    error_message = "ses_events_sns_topic_key must contain only lowercase letters, numbers, and hyphens."
  }
}

###########################################
############ SES variables ################
###########################################

variable "ses_identities_config" {
  description = "Map of SES identities for the example. Empty principals are injected from delegated_senders in locals.tf."
  type = map(object({
    identity                = string
    identity_type           = string
    dkim_signing_key_length = optional(string, "RSA_2048_BIT")
    configuration_set_key   = optional(string, "")
    mail_from = optional(object({
      domain                 = string
      behavior_on_mx_failure = optional(string, "USE_DEFAULT_VALUE")
    }))
    sending_authorization = optional(map(object({
      delegated_sender_key   = optional(string, "") # Key in delegated_senders (sample only)
      principals             = optional(list(string), [])
      actions                = optional(list(string), ["ses:SendEmail", "ses:SendRawEmail"])
      allowed_from_addresses = optional(list(string), [])
      source_accounts        = optional(list(string), [])
    })), {})
    functionality   = string
    additional_tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_identities_config : [
        for sid, s in v.sending_authorization :
        length(s.principals) > 0 || length(s.delegated_sender_key) > 0
      ]
    ]))
    error_message = "Each sending_authorization statement must define principals or delegated_sender_key."
  }
}

variable "ses_configuration_sets_config" {
  description = "Map of SES configuration sets for the example. sns_topic_arn = \"\" is injected from data.tf."
  type = map(object({
    tls_policy                 = optional(string, "REQUIRE")
    allow_optional_tls         = optional(bool, false)
    reputation_metrics_enabled = optional(bool, true)
    sending_enabled            = optional(bool, true)
    suppressed_reasons         = optional(list(string), ["BOUNCE", "COMPLAINT"])
    event_destinations = optional(map(object({
      enabled              = optional(bool, true)
      matching_event_types = list(string)
      use_sns_topic        = optional(bool, false) # Inject sns_topic_arn from data.tf (sample only)
      sns_topic_arn        = optional(string, "")
      event_bus_arn        = optional(string, "")
      cloudwatch_dimensions = optional(list(object({
        dimension_name          = string
        dimension_value_source  = string
        default_dimension_value = string
      })), [])
    })), {})
    functionality   = string
    additional_tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.ses_configuration_sets_config : length(v.functionality) > 0])
    error_message = "functionality cannot be empty."
  }
}
