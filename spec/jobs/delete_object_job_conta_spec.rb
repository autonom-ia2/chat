require 'rails_helper'

# #2133: excluir a conta pré-apagava só conversas, contatos, caixas e eventos de relatório. O resto das associações da
# conta é `destroy_async`, que só roda depois do commit, e as tabelas do fork com chave estrangeira para a conta sem
# cascata barravam o DELETE da conta (PG::ForeignKeyViolation).
RSpec.describe DeleteObjectJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990001') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }

  # Linha mínima numa tabela, sem passar pelo modelo: o que importa aqui é a linha existir no banco. Coluna com nome
  # errado levanta erro (o insert! recusa atributo desconhecido); só os carimbos de tempo entram quando a tabela tem.
  def linha!(tabela, atributos)
    modelo = Class.new(ApplicationRecord) { self.table_name = tabela }
    agora = Time.current
    carimbos = { created_at: agora, updated_at: agora }.slice(*modelo.column_names.map(&:to_sym))
    modelo.insert!(atributos.merge(carimbos), returning: :id).rows.first.first # rubocop:disable Rails/SkipsModelValidations
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def montar_crm
    segunda = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta')
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, conversation_id: conversation.id,
                                     title: 'Pedido', owner: user)
    account.crm_cards.create!(pipeline: pipeline, stage: segunda, title: 'Sem contato')
    Crm::CardConversation.create!(account: account, card: card, conversation: conversation)
    Crm::ActivityLogger.new(card: card, actor: user, event_type: 'note', payload: { 'text' => 'anotação' }).perform
    serie = Crm::FollowUpSeries.create!(account: account, card: card, created_by: user, title: 'Toda segunda', frequency: :weekly,
                                        starts_at: 1.day.from_now, timezone: 'America/Sao_Paulo', weekdays: [1])
    Crm::FollowUp.create!(account: account, card: card, series: serie, title: 'Retorno', due_at: 1.day.from_now, status: :pending)
    reuniao = account.crm_meetings.create!(card: card, created_by: user, title: 'Conversa', provider: :internal,
                                           online_meeting_type: :whatsapp_video, status: :scheduled, timezone: 'America/Sao_Paulo',
                                           starts_at: 2.days.from_now, ends_at: 2.days.from_now + 30.minutes)
    reuniao.meeting_guests.create!(account: account, user: user, name: user.name, email: user.email,
                                   guest_type: :internal_user)
    Crm::MeetingNotice.create!(meeting: reuniao, account: account, kind: 'booked', due_at: 1.minute.ago)
    account.crm_ai_stage_suggestions.create!(card: card, from_stage: stage, to_stage: segunda, confidence: 0.8, reasoning: 'x',
                                             model_used: 'm')
    automacao = account.crm_stage_automations.create!(pipeline: pipeline, stage: stage, name: 'Boas-vindas', trigger_event: :on_enter)
    linha!('crm_stage_automation_steps', account_id: account.id, stage_automation_id: automacao.id, position: 0)
    Crm::StageAutomationExecution.create!(account: account, card: card, stage_automation: automacao, trigger_token: SecureRandom.hex(4))
    Crm::SavedView.create!(account: account, user: user, pipeline: pipeline, name: 'Minha visão', visibility: :account,
                           config: { 'columns' => ['title'] })
    Crm::InboxSetting.create!(account: account, inbox: inbox, default_pipeline: pipeline, default_stage: stage)
    Crm::PipelineInbox.create!(account: account, pipeline: pipeline, inbox: inbox, default_stage: stage, created_by: user)
    perfil = linha!('crm_agent_booking_profiles', account_id: account.id, slug: "p-#{SecureRandom.hex(4)}",
                                                  post_meeting_stage_id: segunda.id)
    linha!('crm_agent_booking_links', account_id: account.id, booking_profile_id: perfil, agent_id: user.id, slug: "l-#{SecureRandom.hex(4)}")
    linha!('crm_calendar_sync_states', account_id: account.id, inbox_id: inbox.id)
    create(:crm_ai_usage_event, account: account, pipeline_id: pipeline.id, card_id: card.id)
    create(:crm_google_conversion_event, account: account, card_id: card.id)
    Crm::MetaConversionEvent.create!(account: account, card: card, event_id: "crm-#{card.id}-won-1", event_type: 'won', status: :accepted)
    card
  end

  def montar_resto_do_fork
    agente = linha!('autonomia_agents', account_id: account.id, name: 'Atendente', created_by_id: user.id)
    linha!('autonomia_agent_tool_runs', account_id: account.id, autonomia_agent_id: agente, conversation_id: conversation.id,
                                        slug: 'consulta', execution_key: SecureRandom.hex(4))
    linha!('autonomia_agent_events', account_id: account.id, autonomia_agent_id: agente, event_type: 0)
    linha!('autonomia_agent_knowledge', account_id: account.id, autonomia_agent_id: agente, content: 'Horário: 9h às 18h')
    linha!('autonomia_insurance_connections', account_id: account.id)
    token = linha!('crm_integration_tokens', account_id: account.id, name: 'n8n')
    bearer = linha!('access_tokens', owner_type: 'Crm::IntegrationToken', owner_id: token, token: SecureRandom.hex(12))
    linha!('crm_service_schedules', account_id: account.id, owner_type: 'Inbox', owner_id: inbox.id, timezone: 'America/Sao_Paulo')
    linha!('email_templates', account_id: account.id, name: 'Resposta', body: 'Olá')
    mcp = Mcp::IntegrationToken.create!(account: account, created_by: user, identity_subject: 'auth-2133', name: 'Connect',
                                        scopes: Mcp::IntegrationToken::DEFAULT_SCOPES)
    linha!('account_email_oauth_apps', account_id: account.id, provider: 'google')
    linha!('idempotency_keys', account_id: account.id, key: SecureRandom.hex(4), request_fingerprint: 'x')
    remetente = linha!('email_sender_identities', account_id: account.id, domain: 'exemplo.invalid')
    campanha = linha!('email_campaigns', account_id: account.id, name: 'Novidades', sender_identity_id: remetente)
    destinatario = linha!('email_campaign_recipients', email_campaign_id: campanha, email: 'cliente@exemplo.invalid')
    evento = linha!('email_events', recipient_id: destinatario, event_type: 0, occurred_at: Time.current)
    linha!('email_campaign_templates', account_id: account.id, name: 'Modelo')
    linha!('email_suppressions', account_id: account.id, email: 'saiu@exemplo.invalid')
    modelo = create_whatsapp_api_template(account: account, inbox: create_crm_whatsapp_api_inbox(account: account), user: user)
    linha!('whatsapp_api_campaigns', account_id: account.id, created_by_id: user.id, title: 'Aviso',
                                     whatsapp_api_message_template_id: modelo.id)
    # Linhas sem account_id: achadas pela campanha e pelo dono do token. O usuário técnico do MCP sai pelo revoke!.
    { 'email_campaign_recipients' => destinatario, 'email_events' => evento, 'access_tokens' => bearer, 'users' => mcp.account_user.user_id }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  # Tabelas que o `dependent: :destroy_async` da conta limpa depois do commit, num job próprio.
  def limpas_depois_do_commit
    Account.reflect_on_all_associations.select { |assoc| assoc.options[:dependent] == :destroy_async }.map { |assoc| assoc.klass.table_name }
  end

  # Toda tabela com account_id que ainda guarda linha da conta e que ninguém mais vai limpar.
  def sobras_da_conta(account_id)
    conexao = ActiveRecord::Base.connection
    (conexao.tables - limpas_depois_do_commit).select do |tabela|
      next false unless conexao.column_exists?(tabela, :account_id)

      conexao.select_value("SELECT 1 FROM #{conexao.quote_table_name(tabela)} WHERE account_id = #{Integer(account_id)} LIMIT 1")
    end
  end

  def existe?(tabela, id)
    ActiveRecord::Base.connection.select_value("SELECT 1 FROM #{tabela} WHERE id = #{Integer(id)}").present?
  end

  it 'apaga a conta que usa o CRM, os agentes de IA e as campanhas, sem deixar linha da conta para trás' do
    create_incoming_message(conversation: conversation, content: 'Quero o orçamento')
    montar_crm
    sem_account_id = montar_resto_do_fork

    described_class.perform_now(account)

    expect(Account.exists?(account.id)).to be(false)
    expect(sobras_da_conta(account.id)).to eq([])
    expect(sem_account_id.select { |tabela, id| existe?(tabela, id) }).to eq({})
  end

  # Revisão de banco P1-2: whatsapp_api_campaign_recipients.message_id aponta para a mensagem sem cascata. Com o
  # destinatário ainda lá, o job que apaga as mensagens da conversa falhava e as mensagens ficavam órfãs. Quando o
  # destinatário guarda a conversa, a cascata dela o leva antes; o caso é o destinatário sem conversa gravada.
  it 'apaga as mensagens da conta mesmo com destinatário de campanha apontando para elas' do
    mensagem = create_incoming_message(conversation: conversation, content: 'Quero o orçamento')
    campanha = linha!('whatsapp_api_campaigns', account_id: account.id, created_by_id: user.id, title: 'Aviso')
    linha!('whatsapp_api_campaign_recipients', account_id: account.id, whatsapp_api_campaign_id: campanha, contact_id: contact.id,
                                               message_id: mensagem.id)

    perform_enqueued_jobs(only: ActiveRecord::DestroyAssociationAsyncJob) { described_class.perform_now(account) }

    expect([Message.exists?(mensagem.id), Account.exists?(account.id)]).to eq([false, false])
  end

  # Revisão de banco P2: a conta seguia ativa durante a exclusão (campanha agendada disparava, a IA respondia).
  it 'suspende a conta e cancela as campanhas agendadas antes do pré-apagar' do
    campanha = linha!('whatsapp_api_campaigns', account_id: account.id, created_by_id: user.id, title: 'Aviso',
                                                scheduled_at: 1.minute.ago, status: WhatsappApiCampaign.statuses[:scheduled])
    job = described_class.new
    no_pre_apagar = nil
    allow(job).to receive(:purge_heavy_associations).and_wrap_original do |original, objeto|
      no_pre_apagar = [Account.find(account.id).status, WhatsappApiCampaign.find(campanha).status]
      original.call(objeto)
    end

    job.perform(account)

    expect(no_pre_apagar).to eq(%w[suspended cancelled])
    expect(Account.exists?(account.id)).to be(false)
  end

  # Revisão de banco P3 (#1516): a limpeza do fork não apaga a atribuição de IP; ela sai na cascata do destroy! da conta,
  # antes do TeardownSessionJob rodar. O teardown sem a linha (release! vazio) termina normalmente. Quem impede outra conta
  # de pegar o IP de uma sessão ainda ligada é o Assigner#free_ip, que descarta IP em uso no motor.
  it 'deixa a atribuição de proxy para a cascata da conta, e o teardown depois dela não quebra' do
    atribuicao = WhatsappProxy::Assignment.create!(session_name: 'c2y-sessao-2133', account_id: account.id, pool: 'isp',
                                                   webshare_proxy_id: '1', proxy_address: '10.0.0.1', proxy_port: 6000,
                                                   assigned_at: Time.current)

    Autonomia::ExclusaoDaConta.new(account).perform
    expect(WhatsappProxy::Assignment.exists?(atribuicao.id)).to be(true)

    described_class.new.perform(account)
    expect(WhatsappProxy::Assignment.exists?(atribuicao.id)).to be(false)

    waha = instance_double(Waha::Client, get_session: { 'status' => 'WORKING' }, logout_session: nil, delete_session: nil)
    allow(Waha::Client).to receive(:new).and_return(waha)
    expect { WhatsappHybrid::TeardownSessionJob.perform_now('c2y-sessao-2133') }.not_to raise_error
    expect(waha).to have_received(:delete_session).with('c2y-sessao-2133')
  end

  # A conexão sai com a caixa (Inbox has_one, dependent: :destroy), no pré-apagar do job, e o callback desliga a sessão.
  it 'desliga a sessão do WhatsApp Híbrido no WAHA, que ficaria conectada ao celular' do
    linha!('whatsapp_hybrid_connections', account_id: account.id, inbox_id: inbox.id, session_name: 'c2y-sessao-2133',
                                          public_id: SecureRandom.uuid)

    expect { described_class.perform_now(account) }.to have_enqueued_job(WhatsappHybrid::TeardownSessionJob).with('c2y-sessao-2133')
    expect(Account.exists?(account.id)).to be(false)
  end

  it 'não toca o CRM de outra conta' do
    outra = create(:account)
    outro_admin = create(:user, account: outra, role: :administrator)
    funil_de_fora, etapa_de_fora = create_crm_pipeline(account: outra, user: outro_admin)
    card_de_fora = outra.crm_cards.create!(pipeline: funil_de_fora, stage: etapa_de_fora, title: 'Alheio')
    montar_crm

    described_class.perform_now(account)

    expect([card_de_fora.reload.id, funil_de_fora.reload.id, outra.reload.id]).to eq([card_de_fora.id, funil_de_fora.id, outra.id])
  end
end
