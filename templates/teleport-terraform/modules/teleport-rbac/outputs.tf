output "role_names" {
  description = "Map of logical name to Teleport role name for all managed roles"
  value = {
    base_user            = teleport_role.base_user.metadata.name
    dev_access           = teleport_role.dev_access.metadata.name
    dev_auto_access      = teleport_role.dev_auto_access.metadata.name
    platform_dev_access  = teleport_role.platform_dev_access.metadata.name
    prod_readonly_access = teleport_role.prod_readonly_access.metadata.name
    prod_access          = teleport_role.prod_access.metadata.name
    prod_auto_access     = teleport_role.prod_auto_access.metadata.name
    dev_requester        = teleport_role.dev_requester.metadata.name
    senior_dev_requester = teleport_role.senior_dev_requester.metadata.name
    prod_requester       = teleport_role.prod_requester.metadata.name
    dev_reviewer         = teleport_role.dev_reviewer.metadata.name
    prod_reviewer        = teleport_role.prod_reviewer.metadata.name
  }
}
