json.id resource.id
json.app_id resource.app_id
json.status resource.enabled?
json.inbox resource.inbox&.slice(:id, :name)
json.account_id resource.account_id
json.hook_type resource.hook_type

# Who connects the integration also sees how it is set up (#2027).
if Current.account_user&.permission_granted?('integration_manage')
  visible_properties = resource.app&.visible_properties || []
  settings = (resource.settings || {}).select { |key, _| visible_properties.include?(key.to_s) }

  json.settings settings
  json.reference_id resource.reference_id
end
