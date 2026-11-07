require Rails.root.join('lib/feature_flag_rollout')

# #2667 — conta nova nasce com as 27 funções que o Rodrigo liberou para todas as contas em 07/11/2026. Liga só o
# padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS): as contas existentes já foram ligadas pela Orquestração e
# não são tocadas. Mudar o features.yml não basta, porque o ConfigLoader do deploy roda com reconcile_only_new e
# preserva o `enabled` gravado. O como está em lib/feature_flag_rollout.rb. A chave autonomia_agents_ao_receber_passagem
# (internal_attributes, não é flag) nasce pelo Autonomia::AccountProvisioningDefaults. Ficam de fora, por decisão do
# Rodrigo, `customer_base` e `instagram_assisted_onboarding` (a migration não as toca).
#
# Com a configuração gravada, o `up` confere que as 27 ficaram ligadas e falha se alguma não ficou (por exemplo, valor
# que não é lista, que o padrao! não regrava): a migration não termina "com sucesso" sem ter ligado nada. Sem a linha
# no banco (instalação nova), não há o que conferir: o ConfigLoader a cria do features.yml, já com as 27 ligadas.
class ContaNovaNasceComAsFlagsDeNovembro < ActiveRecord::Migration[7.2]
  FEATURES = %w[
    agente_diz_quando_nao_sabe
    agentes_enviar_local_e_contato
    agentes_pedir_localizacao
    agentes_painel_desempenho
    anuncios_login_unico
    automacao_editor
    automacao_fundacao
    automacao_gatilhos
    automacao_ia
    automacao_mensagens
    automacao_motor
    contato_relacao
    crm_ia_duvida_vira_sugestao
    crm_ia_nome_provisorio
    crm_lista_acao
    funcoes_guiadas
    ia_previa_de_link
    leitura_no_celular
    meta_ads_comentarios_facebook
    meta_ads_comentarios_ia
    meta_ads_comentarios_instagram
    meta_ads_comentarios_privado_facebook
    meta_ads_criar
    meta_ads_formularios
    meta_ads_organico
    seus_posts
    seus_posts_comentarios
  ].freeze

  def up
    FEATURES.each { |feature| FeatureFlagRollout.padrao!(feature, true) }
    GlobalConfig.clear_cache
    conferir_ligadas!
  end

  # Volta só o padrão das contas novas. Nenhuma conta é desligada.
  def down
    FEATURES.each { |feature| FeatureFlagRollout.padrao!(feature, false) }
    GlobalConfig.clear_cache
  end

  private

  def conferir_ligadas!
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.nil?

    lista = config.value.is_a?(Array) ? config.value : []
    ligadas = lista.select { |item| item['enabled'] == true }.pluck('name')
    faltando = FEATURES - ligadas
    return if faltando.empty?

    raise "ACCOUNT_LEVEL_FEATURE_DEFAULTS sem as flags ligadas: #{faltando.join(', ')}"
  end
end
