# Liga uma feature flag de conta para todo mundo, por migration de dados (#1181, #1399).
# - `padrao!`: muda o padrão das contas novas em ACCOUNT_LEVEL_FEATURE_DEFAULTS. Só o features.yml não basta: o
#   ConfigLoader do deploy roda com reconcile_only_new e não sobrescreve o valor já gravado. Sem a linha no banco, não
#   faz nada (o ConfigLoader a cria do features.yml). Sem o item na lista, ele entra com o valor pedido.
# - `ligar_em_todas!`: liga a flag em toda conta que ainda não tem, gravando só a coluna do bit (sem validação nem
#   callbacks do Account), para uma conta antiga com dado inválido não derrubar o deploy. Cada conta ligada vai ao log.
# Depois de usar, chame GlobalConfig.clear_cache. Mesmo efeito de 20250416182131_flip_chatwoot_v4_default_...rb.
module FeatureFlagRollout
  module_function

  def padrao!(feature, ligado)
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.blank?

    lista = Array(config.value)
    lista += [{ 'name' => feature }] if lista.none? { |item| item['name'] == feature }
    config.value = lista.map { |item| item['name'] == feature ? item.merge('enabled' => ligado) : item }
    config.save!
  end

  def ligar_em_todas!(feature, log_tag:)
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| ligar_na_conta(account, feature, log_tag) }
    end
  end

  def ligar_na_conta(account, feature, log_tag)
    return if account.feature_enabled?(feature)

    account.enable_features(feature)
    account.update_columns(account.changes_to_save.transform_values(&:last)) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.info("[#{log_tag}] conta=#{account.id} ligada")
  end
end
