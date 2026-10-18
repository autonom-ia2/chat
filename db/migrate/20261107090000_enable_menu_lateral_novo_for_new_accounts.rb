# Contas novas nascem com o menu lateral novo (#1617). Mudar `enabled` no features.yml não basta: o ConfigLoader só
# acrescenta flags novas ao ACCOUNT_LEVEL_FEATURE_DEFAULTS (reconcile_only_new), e esta já está lá desligada. Mesmo
# padrão do Chatwoot em 20260409091202_enable_assignment_v2_for_new_accounts.rb. Só dado de configuração; contas
# existentes não mudam (já foram ligadas pela Orquestração em 18/10/2026).
class EnableMenuLateralNovoForNewAccounts < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    features = config.value
    feature = features.find { |f| f['name'] == 'menu_lateral_novo' }
    return if feature.blank?

    feature['enabled'] = true
    config.update!(value: features)
    GlobalConfig.clear_cache
  end

  def down
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    features = config.value
    feature = features.find { |f| f['name'] == 'menu_lateral_novo' }
    return if feature.blank?

    feature['enabled'] = false
    config.update!(value: features)
    GlobalConfig.clear_cache
  end
end
