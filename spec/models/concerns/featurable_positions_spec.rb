# frozen_string_literal: true

require 'rails_helper'

# Upgrade Chatwoot 4.19.1 (#3119). A posição de cada flag na sua coluna é gravada no banco (um bit por flag). Mover,
# reordenar ou apagar uma flag liga ou desliga outra em toda conta. Este spec trava a ordem de todas: flag nova
# entra só no fim da última coluna, e quem a acrescentar acrescenta o nome aqui também.
RSpec.describe Featurable do
  posicoes = {
    'feature_flags' => %w[
      inbound_emails channel_email channel_facebook conversation_unread_counts
      ip_lookup disable_branding email_continuity_on_api_channel help_center
      agent_bots macros agent_management team_management
      inbox_management labels custom_attributes automations
      canned_responses integrations voice_recorder report_rollup
      channel_website campaigns reports crm
      auto_resolve_conversations custom_reply_email custom_reply_domain audit_logs
      custom_tools message_reply_to branded_email_templates inbox_view
      sla help_center_embedding_search linear_integration captain_integration
      custom_roles chatwoot_v4 captain_v1_action_classifier contact_chatwoot_support_team
      shopify_integration search_with_gin channel_instagram crm_integration
      channel_voice notion_integration captain_integration_v2 whatsapp_embedded_signup
      whatsapp_campaign crm_v2 assignment_v2 captain_document_auto_sync
      advanced_search saml advanced_search_indexing reply_mailer_migration
      unread_count_for_filters companies channel_tiktok csat_review_notes
      captain_tasks conversation_required_attributes advanced_assignment
    ],
    'feature_flags_ext_1' => %w[
      whatsapp_manual_transfer data_import api_and_webhooks whatsapp_reconfigure
      whatsapp_embedded_signup_inbox_creation delayed_automations audit_log_ip_address relationships_attributes
      relationships_company_media relationships_navigation instagram_assisted_onboarding meta_ads_hub
      email_template_import autonomia_agents_journey crm_booking_v2 customer_base
      whatsapp_templates_journey crm_configurar_caixas campaign_open_window_text whatsapp_templates_ai
      nova_conversa_tela followup_template_real_values crm_lembretes_v2 crm_calendario_ouro
      whatsapp_campaign_products menu_lateral_novo horario_unico_caixa crm_outro_canal
      crm_mensagem_marcada crm_avaliar_toda_mensagem memoria_ia conversa_cara_do_canal
      whatsapp_hybrid_recovery etiquetas_do_whatsapp whatsapp_rich_native tela_inicial_resumo
      email_autoria conversa_email_nova whatsapp_agenda_do_contato email_lido_sincronizado
      crm_numeros_lentes contato_pelo_email crm_assunto_na_etapa email_enviados
      anuncios_sem_login crm_ia_arquiva_lixo crm_ia_avalia_mensagem_equipe hibrido_foto_do_contato
      convite_da_reuniao crm_metas crm_numeros_equipe ficar_com_a_conversa_ao_enviar
      crm_ia_fatos_da_conversa crm_ia_assunto_encerrado crm_ia_fecha_card crm_ia_leitor_de_midia
      conversa_instagram crm_arquivados painel_contato_enxuto agente_so_informa
      meta_ads_gestao crm_ia_nome_provisorio crm_ia_duvida_vira_sugestao
    ],
    'feature_flags_ext_2' => %w[
      contato_relacao crm_numeros_origens lista_quem_espera agentes_painel_desempenho
      meta_ads_organico leitura_no_celular meta_ads_formularios meta_ads_comentarios_instagram
      meta_ads_criar seus_posts campanhas_publico_por_conversa meta_ads_comentarios_facebook
      crm_lista_acao funcoes_guiadas seus_posts_comentarios meta_ads_comentarios_ia
      agente_diz_quando_nao_sabe ia_previa_de_link agentes_pedir_localizacao automacao_fundacao
      automacao_motor automacao_editor automacao_mensagens automacao_ia
      agentes_enviar_local_e_contato automacao_gatilhos meta_ads_comentarios_privado_facebook anuncios_login_unico
      prospeccao_nova rag_corte_por_estrutura agente_ferramentas_delegadas agente_ferramenta_em_segundo_plano
      instagram_login_unico agente_material_primeiro agente_usa_o_trecho rag_busca_hibrida
      agente_ferramentas_prontas agente_ferramentas_prontas_consultas agente_ferramentas_prontas_vitrine agente_ferramentas_prontas_construtor
      agente_ferramentas_prontas_lote2 automacao_porta agente_ferramentas_prontas_bases agente_ferramentas_prontas_premium
      relacionamentos_novo agente_ferramentas_prontas_ip_proprio automacao_passos_novos automacao_no_crm
      carteira_seguros agente_modelos_seguro captain_classifier conversation_monitors
      campaign_analytics company_enrichment stripe_integration mobile_voice_push
      auto_translate copilot_workflows shopify_custom_apps captain_mcp_servers
    ]
  }.freeze

  posicoes.each do |coluna, nomes|
    it "keeps every flag of #{coluna} at its recorded position" do
      mapa = described_class.feature_flag_mappings_for(described_class::FEATURE_LIST)[coluna]
      expect(mapa).to eq(nomes.each_with_index.to_h { |nome, indice| [indice + 1, :"feature_#{nome}"] })
    end
  end

  it 'keeps feature_flags_ext_3 empty until an extension column is needed' do
    expect(described_class.feature_flag_mappings_for(described_class::FEATURE_LIST)['feature_flags_ext_3']).to eq({})
  end

  it 'brings the flags of the upstream 4.19.1 and 4.20.1 turned off' do
    novas = %w[captain_classifier conversation_monitors campaign_analytics company_enrichment stripe_integration
               mobile_voice_push auto_translate copilot_workflows shopify_custom_apps captain_mcp_servers]
    ligadas = described_class::FEATURE_LIST.select { |flag| novas.include?(flag['name']) && flag['enabled'] }
    expect(ligadas).to be_empty
  end
end
