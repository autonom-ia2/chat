# #1181 — a jornada nova de Agentes (`autonomia_agents_journey`) passa a ser o padrão.
# Em 12/10/2026 o bit foi ligado em todas as contas ativas por psql (backup no comentário da #1181). Esta migration:
# 1. liga o padrão de contas novas em ACCOUNT_LEVEL_FEATURE_DEFAULTS — o ConfigLoader roda com reconcile_only_new e
#    não sobrescreve o `enabled: false` já gravado no banco, só o features.yml não basta;
# 2. liga em toda conta que ainda não tiver (cobre conta criada entre o psql e o deploy);
# 3. limpa o cache do GlobalConfig.
# Mesmo padrão de 20250416182131_flip_chatwoot_v4_default_feature_flag_installation_config.rb.
class LigarJornadaDeAgentesPorPadrao < ActiveRecord::Migration[7.2]
  FEATURE = 'autonomia_agents_journey'.freeze

  def up
    padrao(true)
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each do |account|
        next if account.feature_enabled?(FEATURE)

        # save! e não enable_features!: conta que não salva para a migration com o nome dela, em vez de ficar de fora calada.
        account.enable_features(FEATURE)
        account.save!
      end
    end
    GlobalConfig.clear_cache
  end

  # Volta só o padrão das contas novas. As contas existentes seguem como estão: voltar uma conta é restaurar o valor
  # dela do backup da #1181.
  def down
    padrao(false)
    GlobalConfig.clear_cache
  end

  private

  # Sem a linha no banco não há o que mudar: o ConfigLoader do deploy a cria do features.yml, que já diz enabled: true.
  # Sem o item da jornada na lista, ele entra com o valor pedido.
  def padrao(ligado)
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.blank?

    lista = Array(config.value)
    lista += [{ 'name' => FEATURE }] if lista.none? { |feature| feature['name'] == FEATURE }
    config.value = lista.map { |feature| feature['name'] == FEATURE ? feature.merge('enabled' => ligado) : feature }
    config.save!
  end
end
