locals {
  # Load the policy JSON document from the repo
  policy_doc = jsondecode(file(var.policy_definition_file))

  policy_display_name = try(local.policy_doc.displayName, "Custom Policy")
  policy_description  = try(local.policy_doc.description, null)
  policy_mode         = try(local.policy_doc.mode, "Indexed")
  policy_metadata     = try(local.policy_doc.metadata, {})
  policy_parameters_schema = try(local.policy_doc.parameters, {})
  policy_rule_obj     = try(local.policy_doc.policyRule, {})

  # Derive a stable definition name (Azure resource name) if one isn't provided
  derived_definition_name = substr(
    trim(replace(lower(regexreplace(local.policy_display_name, "[^0-9a-zA-Z-]+", "-")), "--", "-"), "-"),
    0,
    64
  )

  policy_definition_name = coalesce(var.policy_definition_name, local.derived_definition_name)

  # Management group *name* required by azurerm_policy_definition management_group_name argument
  definition_mg_name = element(
    split("/", element(var.management_group_ids, 0)),
    length(split("/", element(var.management_group_ids, 0))) - 1
  )

  # Build assignment parameters:
  # - start with user-provided parameters
  # - if the policy JSON defines an 'effect' parameter, set it from var.policy_effect
  assignment_parameters = merge(
    var.policy_parameters,
    contains(keys(local.policy_parameters_schema), "effect") ? { effect = var.policy_effect } : {}
  )
}
