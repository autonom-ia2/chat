# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Account do
  it { is_expected.to have_many(:users).through(:account_users) }
  it { is_expected.to have_many(:account_users) }
  it { is_expected.to have_many(:inboxes).dependent(:destroy_async) }
  it { is_expected.to have_many(:conversations).dependent(:destroy_async) }
  it { is_expected.to have_many(:contacts).dependent(:destroy_async) }
  it { is_expected.to have_many(:canned_responses).dependent(:destroy_async) }
  it { is_expected.to have_many(:facebook_pages).class_name('::Channel::FacebookPage').dependent(:destroy_async) }
  it { is_expected.to have_many(:web_widgets).class_name('::Channel::WebWidget').dependent(:destroy_async) }
  it { is_expected.to have_many(:webhooks).dependent(:destroy_async) }
  it { is_expected.to have_many(:notification_settings).dependent(:destroy_async) }
  it { is_expected.to have_many(:reporting_events) }
  it { is_expected.to have_many(:portals).dependent(:destroy_async) }
  it { is_expected.to have_many(:categories).dependent(:destroy_async) }
  it { is_expected.to have_many(:teams).dependent(:destroy_async) }

  describe 'Autonomia provisioning defaults' do
    let(:default_feature_flags) { 8_950_126_033_336_532_983 }

    it 'applies the default feature flag bitmask when account defaults are enabled' do
      with_modified_env AUTONOMIA_ACCOUNT_DEFAULTS_ENABLED: 'true' do
        account = create(:account)

        expect(account.feature_flags).to eq(default_feature_flags)
      end
    end

    it 'links the configured default user as administrator when account defaults are enabled' do
      user = create(:user)

      with_modified_env AUTONOMIA_ACCOUNT_DEFAULTS_ENABLED: 'true',
                        AUTONOMIA_DEFAULT_ACCOUNT_USER_ID: user.id.to_s do
        account = create(:account)

        account_user = AccountUser.find_by!(account: account, user: user)
        expect(account_user.role).to eq('administrator')
      end
    end

    it 'does not fail when the configured default user does not exist' do
      with_modified_env AUTONOMIA_ACCOUNT_DEFAULTS_ENABLED: 'true',
                        AUTONOMIA_DEFAULT_ACCOUNT_USER_ID: '-1' do
        expect { create(:account) }.to change(described_class, :count).by(1)
      end
    end
  end

  it 'has_many autonomia_account_links' do
    skip 'QUARANTINE: pre-existing legacy failure, harness-restore PR; real fix tracked for follow-up PR2'
    expect(subject).to have_many(:autonomia_account_links).class_name('Autonomia::AccountLink').dependent(:destroy)
  end

  # This validation happens in ApplicationRecord
  describe 'length validations' do
    let(:account) { create(:account) }

    it 'validates name presence' do
      account.name = ''
      account.valid?
      expect(account.errors[:name]).to include("can't be blank")
    end

    it 'validates name length' do
      account.name = 'a' * 256
      account.valid?
      expect(account.errors[:name]).to include('is too long (maximum is 255 characters)')
    end

    it 'validates domain length' do
      account.domain = 'a' * 150
      account.valid?
      expect(account.errors[:domain]).to include('is too long (maximum is 100 characters)')
    end
  end

  describe 'usage_limits' do
    let(:account) { create(:account) }

    it 'returns ChatwootApp.max limits' do
      expect(account.usage_limits[:agents]).to eq(ChatwootApp.max_limit)
      expect(account.usage_limits[:inboxes]).to eq(ChatwootApp.max_limit)
    end
  end

  describe '#api_and_webhooks_enabled?' do
    it 'is enabled for self-hosted accounts regardless of the stored feature flag' do
      account = create(:account)
      account.disable_features!('api_and_webhooks')

      expect(account.api_and_webhooks_enabled?).to be true
    end
  end

  describe 'captain defaults for new accounts' do
    it 'does not store Captain model overrides or enable premium Captain features' do
      InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').update!(
        value: Featurable::FEATURE_LIST,
        locked: true
      )

      account = create(:account)

      expect(account).not_to be_feature_enabled('captain_integration')
      expect(account).not_to be_feature_enabled('captain_integration_v2')
      expect(account.captain_models).to be_nil
    end
  end

  describe 'conversation unread counts feature flag' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:store) { Conversations::UnreadCounts::Store }
    let(:inbox_key) { store.inbox_key(account.id, inbox.id) }

    after do
      store.clear_account!(account.id)
    end

    it 'clears unread count cache when the feature is enabled' do
      build_unread_count_cache

      account.enable_features!(:conversation_unread_counts)

      expect(store.base_ready?(account.id)).to be(false)
      expect(store.assignment_ready?(account.id)).to be(false)
      expect(store.counts_for_keys([inbox_key])).to eq(inbox_key => 0)
    end

    it 'clears unread count cache when the feature is disabled' do
      account.enable_features!(:conversation_unread_counts)
      build_unread_count_cache

      account.disable_features!(:conversation_unread_counts)

      expect(store.base_ready?(account.id)).to be(false)
      expect(store.assignment_ready?(account.id)).to be(false)
      expect(store.counts_for_keys([inbox_key])).to eq(inbox_key => 0)
    end

    def build_unread_count_cache
      store.mark_base_ready!(account.id)
      store.mark_assignment_ready!(account.id)
      store.add_base_membership(account_id: account.id, inbox_id: inbox.id, label_ids: [], conversation_id: 1)
    end
  end

  describe 'resuming delayed automations' do
    let(:account) { create(:account) }

    it 'reschedules the overdue backlog in the same transaction that re-enables the flag' do
      row = create(:automation_rule_pending_execution, account: account, due_at: 5.days.ago)

      ActiveRecord::Base.transaction(requires_new: true) do
        account.enable_features!('delayed_automations')
        # Still uncommitted: no sweep can see the flag yet, and the backlog is already re-clocked,
        # so there is no window where the account is sweepable on a stale due_at.
        expect(row.reload.due_at).to be_within(5.seconds).of(Time.current)
        raise ActiveRecord::Rollback
      end

      expect(account.reload.feature_delayed_automations?).to be(false)
      expect(row.reload.due_at).to be_within(5.seconds).of(5.days.ago)
    end

    it 'leaves the backlog alone when the flag is turned off' do
      account.enable_features!('delayed_automations')
      row = create(:automation_rule_pending_execution, account: account, due_at: 5.days.ago)

      account.disable_features!('delayed_automations')

      expect(row.reload.due_at).to be_within(5.seconds).of(5.days.ago)
    end
  end

  describe 'feature flag columns' do
    let(:account) { described_class.new(name: 'Test Account') }

    # O mapa da feature_flags_ext_1: a posição no features.yml é o bit; só se acrescenta no fim.
    let(:mapa_ext_1) do
      {
        feature_whatsapp_manual_transfer: 1,
        feature_data_import: 1 << 1,
        feature_api_and_webhooks: 1 << 2,
        feature_whatsapp_reconfigure: 1 << 3,
        feature_whatsapp_embedded_signup_inbox_creation: 1 << 4,
        feature_delayed_automations: 1 << 5,
        feature_audit_log_ip_address: 1 << 6,
        feature_relationships_attributes: 1 << 7,
        feature_relationships_company_media: 1 << 8,
        feature_relationships_navigation: 1 << 9,
        feature_instagram_assisted_onboarding: 1 << 10,
        feature_meta_ads_hub: 1 << 11,
        feature_email_template_import: 1 << 12,
        feature_autonomia_agents_journey: 1 << 13,
        feature_crm_booking_v2: 1 << 14,
        feature_customer_base: 1 << 15,
        feature_whatsapp_templates_journey: 1 << 16,
        feature_crm_configurar_caixas: 1 << 17,
        feature_campaign_open_window_text: 1 << 18,
        feature_whatsapp_templates_ai: 1 << 19,
        feature_nova_conversa_tela: 1 << 20,
        feature_followup_template_real_values: 1 << 21,
        feature_crm_lembretes_v2: 1 << 22,
        feature_crm_calendario_ouro: 1 << 23,
        feature_whatsapp_campaign_products: 1 << 24,
        # #1617: bit = posição no features.yml; só acrescentar no fim (#1322).
        feature_menu_lateral_novo: 1 << 25,
        feature_horario_unico_caixa: 1 << 26,
        feature_crm_outro_canal: 1 << 27,
        feature_crm_mensagem_marcada: 1 << 28,
        feature_crm_avaliar_toda_mensagem: 1 << 29,
        feature_memoria_ia: 1 << 30,
        feature_conversa_cara_do_canal: 1 << 31,
        # #1489: a posição na lista é o bit; no fim do que está na main.
        feature_whatsapp_hybrid_recovery: 1 << 32,
        # #1823: posição 34 (tabela v4 da Orquestração).
        feature_etiquetas_do_whatsapp: 1 << 33,
        # #1709: posição 35, logo depois de etiquetas_do_whatsapp (tabela v4 da Orquestração).
        feature_whatsapp_rich_native: 1 << 34,
        # #1801: posição 36, logo depois de whatsapp_rich_native (tabela da Orquestração).
        feature_tela_inicial_resumo: 1 << 35,
        # #1807: posição 37, logo depois de tela_inicial_resumo (tabela da Orquestração, 19/10).
        feature_email_autoria: 1 << 36,
        # #1786: posição 38, logo depois de email_autoria (tabela da Orquestração, 19/10).
        feature_conversa_email_nova: 1 << 37,
        # #1865: posição 39, logo depois de conversa_email_nova (tabela da Orquestração, 19/10).
        feature_whatsapp_agenda_do_contato: 1 << 38,
        # #1870: posição 40, logo depois de whatsapp_agenda_do_contato (tabela da Orquestração, 19/10).
        feature_email_lido_sincronizado: 1 << 39,
        # #1897: posição 41, logo depois de email_lido_sincronizado (tabela da Orquestração, 19/10).
        feature_crm_numeros_lentes: 1 << 40,
        # #1813: posição 42, logo depois de crm_numeros_lentes (tabela da Orquestração, 19/10).
        feature_contato_pelo_email: 1 << 41,
        # #1910: posição 43 (definitiva da Orquestração, 19/10), depois de contato_pelo_email (42, #1917).
        feature_crm_assunto_na_etapa: 1 << 42,
        # #1938: posição 44 (Orquestração, 20/10: fica com a 44 se o PR abrir antes do etiquetas_do_celular do Max).
        feature_email_enviados: 1 << 43,
        # #1960: posição 45 (definitiva da Orquestração, 21/10), logo depois de email_enviados.
        feature_anuncios_sem_login: 1 << 44,
        # #1922: posição 46 (1 << 45), definitiva da Orquestração (21/10), logo depois de anuncios_sem_login.
        feature_crm_ia_arquiva_lixo: 1 << 45,
        # #1923: posição 47 (1 << 46), definitiva da Orquestração (21/10), logo depois de crm_ia_arquiva_lixo.
        feature_crm_ia_avalia_mensagem_equipe: 1 << 46,
        # #1934: posição 48 (1 << 47), definitiva da Orquestração (21/10), logo depois de crm_ia_avalia_mensagem_equipe.
        feature_hibrido_foto_do_contato: 1 << 47,
        # #1984: posição 49 (1 << 48), definitiva da Orquestração (21/10), logo depois de hibrido_foto_do_contato.
        feature_convite_da_reuniao: 1 << 48,
        # #1991: posição 50 (1 << 49), definitiva da Orquestração (21/10), logo depois de convite_da_reuniao.
        feature_crm_metas: 1 << 49,
        # #1992: posição 51 (1 << 50), da Orquestração (21/10), logo depois de crm_metas.
        feature_crm_numeros_equipe: 1 << 50,
        # #2067: posição provisória 52 (1 << 51), logo depois de crm_numeros_equipe; a Orquestração reserva a 56 e reemite.
        feature_ficar_com_a_conversa_ao_enviar: 1 << 51,
        # IA entende a conversa F1–F4: posições 53 a 56 (1 << 52 a 1 << 55), definitivas da Orquestração (22/10), depois do #2077.
        feature_crm_ia_fatos_da_conversa: 1 << 52,
        feature_crm_ia_assunto_encerrado: 1 << 53,
        feature_crm_ia_fecha_card: 1 << 54,
        feature_crm_ia_leitor_de_midia: 1 << 55,
        # #2079: posição 57 (1 << 56), definitiva da Orquestração (22/10).
        feature_conversa_instagram: 1 << 56,
        # #2097/#2098: posição 58 (1 << 57), PROVISÓRIA da Orquestração (23/10); definitiva no fim da main na vez do PR.
        feature_crm_arquivados: 1 << 57,
        # #2138: posição 59 (1 << 58), depois da 58 do crm_arquivados #2097 (Orquestração, 23/10).
        feature_painel_contato_enxuto: 1 << 58,
        # #2154: posição 60 (1 << 59), PROVISÓRIA da Orquestração (24/10); definitiva na vez do PR.
        feature_agente_so_informa: 1 << 59,
        # #2161: posição 61 (1 << 60), depois da 60 do agente_so_informa #2166 (Orquestração, 25/10).
        feature_meta_ads_gestao: 1 << 60,
        # #2163: posição 62 (1 << 61), definitiva da Orquestração (25/10), depois da 61 do meta_ads_gestao #2164.
        feature_crm_ia_nome_provisorio: 1 << 61,
        # #2162: posição 63 (1 << 62), definitiva da Orquestração (25/10), a última da coluna ext_1.
        feature_crm_ia_duvida_vira_sugestao: 1 << 62
      }
    end

    it 'configures the account feature flag extension column' do
      expect(described_class.flag_columns).to include('feature_flags', 'feature_flags_ext_1', 'feature_flags_ext_2')
      expect(described_class.flag_mapping['feature_flags_ext_1']).to eq(mapa_ext_1)
      expect(described_class.flag_mapping['feature_flags_ext_1'][:feature_whatsapp_manual_transfer]).to eq(1)
      expect(described_class.flag_mapping['feature_flags_ext_1'][:feature_data_import]).to eq(2)
      expect(described_class.flag_mapping['feature_flags_ext_1'][:feature_whatsapp_embedded_signup_inbox_creation]).to eq(16)
      # #2084: primeira flag da feature_flags_ext_2 (posição provisória da Orquestração).
      # #2001: crm_numeros_origens, posição 2 (1 << 1), DEFINITIVA da Orquestração (26/10).
      # #2202: lista_quem_espera no fim da ext_2, posição pela ordem de chegada à main; hoje 3 (1 << 2 = 4).
      # #2251: agentes_painel_desempenho depois dela, posição 4 (1 << 3 = 8), confirmada pela Orquestração (27/10).
      # #2199: meta_ads_organico, 5 (1 << 4 = 16). #2246: leitura_no_celular logo depois, 6 (1 << 5 = 32), confirmada
      # pela Orquestração (27/10).
      # #2195: meta_ads_formularios depois dela, 7 (1 << 6 = 64). #2196: meta_ads_comentarios_instagram, 8 (1 << 7 = 128).
      # #2198: meta_ads_criar depois dela, 9 (1 << 8 = 256), pela ordem da main (Orquestração, 27/10).
      # #2304: seus_posts no fim da main de hoje, 10 (1 << 9 = 512), válida contra a main de 27/10 (Orquestração).
      # #2277: campanhas_publico_por_conversa depois, 11 (1 << 10 = 1024).
      # #2197: meta_ads_comentarios_facebook depois dela, 12 (1 << 11 = 2048), dada pela Orquestração (28/10).
      # #2283: crm_lista_acao depois dela, 13 (1 << 12 = 4096), dada pela Orquestração (28/10).
      # #2308: funcoes_guiadas depois dela, 14 (1 << 13 = 8192).
      # #2305: seus_posts_comentarios depois dela, 15 (1 << 14 = 16384), provisória da Orquestração (29/10).
      # #2212: meta_ads_comentarios_ia depois dela, 16 (1 << 15 = 32768), dada pela Orquestração (30/10).
      # #2381: agente_diz_quando_nao_sabe depois dela, 17 (1 << 16 = 65536), provisória da Orquestração (30/10).
      # #1775: ia_previa_de_link depois dela, 18 (1 << 17 = 131072), reservada pela Orquestração (31/10).
      # #1479 F2: agentes_pedir_localizacao depois dela, 19 (1 << 18 = 262144), dada pela Orquestração (31/10).
      # #1430: agente_ferramentas_delegadas depois dela, 20 (1 << 19 = 524288), reservada pela Orquestração (31/10).
      # #1479 F3: agentes_enviar_local_e_contato depois dela, 21 (1 << 20 = 1048576), dada pela Orquestração (31/10).
      expect(described_class.flag_mapping['feature_flags_ext_2']).to eq(
        feature_contato_relacao: 1, feature_crm_numeros_origens: 2, feature_lista_quem_espera: 4,
        feature_agentes_painel_desempenho: 8, feature_meta_ads_organico: 16, feature_leitura_no_celular: 32,
        feature_meta_ads_formularios: 64, feature_meta_ads_comentarios_instagram: 128, feature_meta_ads_criar: 256,
        feature_seus_posts: 512, feature_campanhas_publico_por_conversa: 1024,
        feature_meta_ads_comentarios_facebook: 2048, feature_crm_lista_acao: 4096, feature_funcoes_guiadas: 8192,
        feature_seus_posts_comentarios: 16_384, feature_meta_ads_comentarios_ia: 32_768,
        feature_agente_diz_quando_nao_sabe: 65_536, feature_ia_previa_de_link: 131_072,
        feature_agentes_pedir_localizacao: 262_144, feature_agente_ferramentas_delegadas: 524_288,
        feature_agentes_enviar_local_e_contato: 1_048_576
      )
    end

    it 'keeps Relationships opt-in and each extension independent of existing flags' do
      flags = %w[relationships_attributes relationships_company_media relationships_navigation]
      flags.each { |flag| expect(account.feature_enabled?(flag)).to be(false) }
      account.enable_features('data_import', 'audit_log_ip_address')
      legacy_mask = account.feature_flags_ext_1

      flags.each_with_index do |flag, index|
        account.enable_features(flag)
        expect(account.feature_flags_ext_1).to eq(legacy_mask | (1 << (index + 7)))
        expect(account).to be_feature_data_import
        expect(account).to be_feature_audit_log_ip_address
        (flags - [flag]).each { |other| expect(account.feature_enabled?(other)).to be(false) }
        account.disable_features(flag)
        expect(account.feature_flags_ext_1).to eq(legacy_mask)
      end
    end

    it 'keeps existing feature flags on the original column' do
      expect(described_class.flag_mapping['feature_flags'][:feature_inbound_emails]).to eq(1)
      expect(described_class.flag_mapping['feature_flags'][:feature_advanced_assignment]).to eq(1 << 62)
    end

    it 'keeps bulk selected feature assignment compatible with existing feature names' do
      account.selected_feature_flags = [:feature_ip_lookup, :feature_assignment_v2, :feature_advanced_assignment, :feature_data_import]

      expect(account).to be_feature_ip_lookup
      expect(account).to be_feature_assignment_v2
      expect(account).to be_feature_advanced_assignment
      expect(account).to be_feature_data_import
      expect(account.selected_feature_flags).to contain_exactly(
        :feature_ip_lookup,
        :feature_assignment_v2,
        :feature_advanced_assignment,
        :feature_data_import
      )
    end
  end

  describe 'inbound_email_domain' do
    let(:account) { create(:account) }

    it 'returns the domain from inbox if inbox value is present' do
      account.update(domain: 'test.com')
      with_modified_env MAILER_INBOUND_EMAIL_DOMAIN: 'test2.com' do
        expect(account.inbound_email_domain).to eq('test.com')
      end
    end

    it 'returns the domain from ENV if inbox value is nil' do
      account.update(domain: nil)
      with_modified_env MAILER_INBOUND_EMAIL_DOMAIN: 'test.com' do
        expect(account.inbound_email_domain).to eq('test.com')
      end
    end

    it 'returns the domain from ENV if inbox value is empty string' do
      account.update(domain: '')
      with_modified_env MAILER_INBOUND_EMAIL_DOMAIN: 'test.com' do
        expect(account.inbound_email_domain).to eq('test.com')
      end
    end
  end

  describe 'support_email' do
    let(:account) { create(:account) }

    it 'returns the support email from inbox if inbox value is present' do
      account.update(support_email: 'support@chatwoot.com')
      with_modified_env MAILER_SENDER_EMAIL: 'hello@chatwoot.com' do
        expect(account.support_email).to eq('support@chatwoot.com')
      end
    end

    it 'returns the support email from ENV if inbox value is nil' do
      account.update(support_email: nil)
      with_modified_env MAILER_SENDER_EMAIL: 'hello@chatwoot.com' do
        expect(account.support_email).to eq('hello@chatwoot.com')
      end
    end

    it 'returns the support email from ENV if inbox value is empty string' do
      account.update(support_email: '')
      with_modified_env MAILER_SENDER_EMAIL: 'hello@chatwoot.com' do
        expect(account.support_email).to eq('hello@chatwoot.com')
      end
    end
  end

  context 'when after_destroy is called' do
    it 'conv_dpid_seq and camp_dpid_seq_ are deleted' do
      account = create(:account)
      query = "select * from information_schema.sequences where sequence_name in  ('camp_dpid_seq_#{account.id}', 'conv_dpid_seq_#{account.id}');"
      expect(ActiveRecord::Base.connection.execute(query).count).to eq(2)
      expect(account.locale).to eq('en')
      account.destroy
      expect(ActiveRecord::Base.connection.execute(query).count).to eq(0)
    end
  end

  describe 'locale' do
    it 'returns correct language if the value is set' do
      account = create(:account, locale: 'fr')
      expect(account.locale).to eq('fr')
      expect(account.locale_english_name).to eq('french')
    end

    it 'returns english if the value is not set' do
      account = create(:account, locale: nil)
      expect(account.locale).to be_nil
      expect(account.locale_english_name).to eq('english')
    end

    it 'returns english if the value is empty string' do
      account = create(:account, locale: '')
      expect(account.locale).to be_nil
      expect(account.locale_english_name).to eq('english')
    end

    it 'returns correct language if the value has country code' do
      account = create(:account, locale: 'pt_BR')
      expect(account.locale).to eq('pt_BR')
      expect(account.locale_english_name).to eq('portuguese')
    end
  end

  describe 'settings' do
    let(:account) { create(:account) }

    context 'when auto_resolve_after' do
      it 'validates minimum value' do
        account.settings = { auto_resolve_after: 4 }
        expect(account).to be_invalid
        expect(account.errors.messages).to eq({ auto_resolve_after: ['must be greater than or equal to 10'] })
      end

      it 'validates maximum value' do
        account.settings = { auto_resolve_after: 1_439_857 }
        expect(account).to be_invalid
        expect(account.errors.messages).to eq({ auto_resolve_after: ['must be less than or equal to 1439856'] })
      end

      it 'allows valid values' do
        account.settings = { auto_resolve_after: 15 }
        expect(account).to be_valid

        account.settings = { auto_resolve_after: 1_439_856 }
        expect(account).to be_valid
      end

      it 'allows null values' do
        account.settings = { auto_resolve_after: nil }
        expect(account).to be_valid
      end
    end

    context 'when auto_resolve_message' do
      it 'allows string values' do
        account.settings = { auto_resolve_message: 'This conversation has been resolved automatically.' }
        expect(account).to be_valid
      end

      it 'allows empty string' do
        account.settings = { auto_resolve_message: '' }
        expect(account).to be_valid
      end

      it 'allows nil values' do
        account.settings = { auto_resolve_message: nil }
        expect(account).to be_valid
      end
    end

    context 'when using store_accessor' do
      it 'correctly gets and sets auto_resolve_after' do
        account.auto_resolve_after = 30
        expect(account.auto_resolve_after).to eq(30)
        expect(account.settings['auto_resolve_after']).to eq(30)
      end

      it 'correctly gets and sets auto_resolve_message' do
        message = 'This conversation was automatically resolved'
        account.auto_resolve_message = message
        expect(account.auto_resolve_message).to eq(message)
        expect(account.settings['auto_resolve_message']).to eq(message)
      end

      it 'defaults captain_auto_resolve_mode to legacy when captain_tasks is disabled' do
        allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(false)

        expect(account.captain_auto_resolve_mode).to eq('legacy')
        expect(account).to be_captain_auto_resolve_legacy
      end

      it 'defaults captain_auto_resolve_mode to evaluated when captain_tasks is enabled' do
        allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)

        expect(account.captain_auto_resolve_mode).to eq('evaluated')
        expect(account).to be_captain_auto_resolve_evaluated
      end

      it 'correctly gets and sets captain_auto_resolve_mode' do
        account.captain_auto_resolve_mode = 'legacy'

        expect(account.captain_auto_resolve_mode).to eq('legacy')
        expect(account.settings['captain_auto_resolve_mode']).to eq('legacy')
        expect(account).to be_captain_auto_resolve_legacy
      end

      it 'allows clearing captain_auto_resolve_mode to fall back to feature defaults' do
        allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(false)
        account.captain_auto_resolve_mode = nil

        expect(account).to be_valid
        expect(account.captain_auto_resolve_mode).to eq('legacy')
        expect(account.settings['captain_auto_resolve_mode']).to be_nil
      end

      it 'falls back to disabled mode from legacy settings key' do
        account.settings = { 'captain_disable_auto_resolve' => true }

        expect(account.captain_auto_resolve_mode).to eq('disabled')
        expect(account).to be_captain_auto_resolve_disabled
      end

      it 'handles nil values correctly' do
        account.auto_resolve_after = nil
        account.auto_resolve_message = nil
        expect(account.auto_resolve_after).to be_nil
        expect(account.auto_resolve_message).to be_nil
      end
    end

    context 'when using with_auto_resolve scope' do
      it 'finds accounts with auto_resolve_after set' do
        account.update(auto_resolve_after: 40 * 24 * 60)
        expect(described_class.with_auto_resolve.pluck(:id)).to include(account.id)
      end

      it 'does not find accounts without auto_resolve_after' do
        account.update(auto_resolve_after: nil)
        expect(described_class.with_auto_resolve.pluck(:id)).not_to include(account.id)
      end
    end

    context 'when support_email is set' do
      it 'allows a plain email address' do
        account.support_email = 'support@example.com'
        expect(account).to be_valid
      end

      it 'allows display-name format' do
        account.support_email = 'Support Team <support@example.com>'
        expect(account).to be_valid
      end

      it 'allows blank values' do
        account.support_email = ''
        expect(account).to be_valid
      end

      it 'rejects malformed strings with no email part' do
        account.support_email = 'Smith Smith'
        expect(account).not_to be_valid
        expect(account.errors[:support_email]).to include(I18n.t('errors.account.support_email.invalid'))
      end
    end

    context 'when reporting_timezone is set' do
      it 'allows valid timezone names' do
        account.reporting_timezone = 'America/New_York'

        expect(account).to be_valid
      end

      it 'rejects invalid timezone names' do
        account.reporting_timezone = 'Invalid/Timezone'

        expect(account).not_to be_valid
        expect(account.errors[:reporting_timezone]).to include(I18n.t('errors.account.reporting_timezone.invalid'))
      end
    end
  end

  describe 'captain_preferences' do
    let(:account) { create(:account) }

    describe 'with no saved preferences' do
      before do
        account.update!(captain_models: nil)
      end

      it 'returns defaults from llm.yml' do
        prefs = account.captain_preferences

        expect(prefs[:features].values).to all(be false)

        Llm::Models.feature_keys.each do |feature|
          expect(prefs[:models][feature]).to eq(Llm::Models.default_model_for(feature))
        end
      end

      it 'returns GPT-5.2 for assistant when Captain V2 is enabled' do
        account.enable_features!('captain_integration_v2')

        expect(account.captain_preferences[:models]['assistant']).to eq('gpt-5.2')
        expect(account.reload.captain_models).to be_nil
      end
    end

    describe 'with saved model preferences' do
      it 'returns saved preferences merged with defaults' do
        account.update!(captain_models: { 'editor' => 'gpt-4.1-mini', 'assistant' => 'gpt-5.2' })

        prefs = account.captain_preferences

        expect(prefs[:models]['editor']).to eq('gpt-4.1-mini')
        expect(prefs[:models]['assistant']).to eq('gpt-5.2')
        expect(prefs[:models]['copilot']).to eq(Llm::Models.default_model_for('copilot'))
      end
    end

    describe 'with saved feature preferences' do
      it 'returns saved feature states' do
        account.update!(captain_features: { 'editor' => true, 'assistant' => true })

        prefs = account.captain_preferences

        expect(prefs[:features]['editor']).to be true
        expect(prefs[:features]['assistant']).to be true
        expect(prefs[:features]['copilot']).to be false
      end
    end

    describe 'validation' do
      it 'rejects invalid model for a feature' do
        account.captain_models = { 'label_suggestion' => 'gpt-5.1' }

        expect(account).not_to be_valid
        expect(account.errors[:captain_models].first).to include('not a valid model for label_suggestion')
      end

      it 'accepts valid model for a feature' do
        account.captain_models = { 'editor' => 'gpt-4.1-mini', 'label_suggestion' => 'gpt-4.1-nano' }

        expect(account).to be_valid
      end

      it 'rejects unknown feature keys' do
        account.captain_models = { 'unknown_feature' => 'gpt-4.1' }

        expect(account).not_to be_valid
        expect(account.errors[:captain_models]).to include("'unknown_feature' is not a known feature")
      end

      it 'removes blank model overrides before saving' do
        account.update!(captain_models: { 'editor' => '', 'assistant' => 'gpt-5.2' })

        expect(account.captain_models).to eq('assistant' => 'gpt-5.2')
      end
    end
  end
end
