require 'rails_helper'

# Caixas no CRM (#1149): a caixa inteira num salvamento só.
RSpec.describe 'CRM Caixas no CRM API', type: :request do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let!(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:ana) { create_crm_agent(account: account, name: 'Ana Ribeiro').first }
  let(:leo) { create_crm_agent(account: account, name: 'Léo Martins').first }
  let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp Comercial', members: [admin, ana, leo]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/caixas" }

  before { account.enable_features!('crm_configurar_caixas') }

  def salvar(user: admin, **caixa)
    put "#{url}/#{inbox.id}", params: { caixa: caixa }, headers: auth_headers(user), as: :json
  end

  def pessoa(user, triage:, pipeline_ids:, only_own: false)
    { id: user.id, triage: triage, pipeline_ids: pipeline_ids, only_own: only_own }
  end

  def acesso(user)
    Crm::InboxAgentAccess.find_by(account_id: account.id, inbox_id: inbox.id, user_id: user.id)
  end

  it 'lists every inbox with its pipelines and people as they see today' do
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, default_pipeline: vendas.first,
                                       default_stage: vendas.last, auto_create_card: true)
    account.crm_pipeline_inboxes.create!(inbox: inbox, pipeline: vendas.first, auto_create_card: true)

    get url, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    caixa = response.parsed_body.dig('payload', 'caixas').find { |item| item.dig('inbox', 'id') == inbox.id }
    expect(caixa['pipeline_ids']).to eq([vendas.first.id])
    expect(caixa['auto_create_card']).to be(true)
    expect(caixa['people'].pluck('name')).to eq(['Admin User', 'Ana Ribeiro', 'Léo Martins'])
    expect(caixa['people'].find { |item| item['id'] == ana.id })
      .to include('triage' => true, 'all_pipelines' => true, 'only_own' => false, 'administrator' => false)
    expect(response.parsed_body.dig('payload', 'funis').pluck('name')).to include('Vendas')
  end

  it 'shows the AI agent that answers first in the inbox, the same one the card shows' do
    bot = AgentBot.create!(name: 'Clara', account: account)
    AgentBotInbox.create!(inbox: inbox, agent_bot: bot, account: account)

    get url, headers: auth_headers(admin)

    caixa = response.parsed_body.dig('payload', 'caixas').find { |item| item.dig('inbox', 'id') == inbox.id }
    # Sem agente dos Agentes IA por trás do robô: agente externo (#1570).
    expect(caixa['agent_bot']).to eq('id' => bot.id, 'name' => 'Clara', 'tipo_do_principal' => 'externo')

    inbox.agent_bot_inbox.update!(status: :inactive)
    get "#{url}/#{inbox.id}", headers: auth_headers(admin)
    expect(response.parsed_body.dig('payload', 'caixa', 'agent_bot')).to be_nil
  end

  it 'answers 404 and writes nothing when the account does not have the flag' do
    account.disable_features!('crm_configurar_caixas')

    salvar(pipeline_ids: [vendas.first.id], modo: 'chegou', people: [])

    expect(response).to have_http_status(:not_found)
    expect(account.crm_inbox_settings.find_by(inbox: inbox)).to be_nil
    expect(account.crm_pipeline_inboxes.where(inbox: inbox)).to be_empty
  end

  it 'refuses agents: only administrators decide who sees what' do
    get url, headers: auth_headers(ana)
    expect(response).to have_http_status(:unauthorized)

    salvar(pipeline_ids: [], modo: 'off', people: [], user: ana)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'saves an inbox with several pipelines: the subject AI creates the card, and only restricted people get a row' do
    salvar(pipeline_ids: [vendas.first.id, pos_venda.first.id], modo: 'auto',
           people: [pessoa(ana, triage: true, pipeline_ids: [vendas.first.id]),
                    pessoa(leo, triage: true, pipeline_ids: [vendas.first.id, pos_venda.first.id])])

    expect(response).to have_http_status(:ok)
    setting = account.crm_inbox_settings.find_by(inbox: inbox)
    expect(setting).to have_attributes(crm_enabled: true, default_pipeline_id: nil, auto_create_card: false,
                                       subject_ai_mode: 'auto', visibility_mode: 'all_inbox_cards')
    expect(account.crm_pipeline_inboxes.where(inbox: inbox).pluck(:pipeline_id, :auto_create_card))
      .to contain_exactly([vendas.first.id, false], [pos_venda.first.id, false])
    expect(acesso(ana)).to have_attributes(all_pipelines: false, triage: true, only_own: false)
    expect(acesso(ana).agent_pipelines.pluck(:pipeline_id)).to eq([vendas.first.id])
    expect([acesso(leo), acesso(admin)]).to eq([nil, nil])
    expect(response.parsed_body.dig('payload', 'caixa', 'pipeline_ids')).to eq([vendas.first.id, pos_venda.first.id])
  end

  it 'refuses several pipelines when nobody sees the conversations without a subject (R7) and writes nothing' do
    salvar(pipeline_ids: [vendas.first.id, pos_venda.first.id], modo: 'auto',
           people: [pessoa(ana, triage: false, pipeline_ids: [vendas.first.id]),
                    pessoa(leo, triage: false, pipeline_ids: [pos_venda.first.id])])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.sem_triagem')
    expect(account.crm_inbox_settings.find_by(inbox: inbox)).to be_nil
    expect(Crm::InboxAgentAccess.where(inbox_id: inbox.id)).to be_empty
  end

  it 'saves a single-pipeline inbox like before: the card is born on arrival, at the chosen stage' do
    proposta = create_crm_stage(account: account, pipeline: vendas.first, name: 'Proposta')
    salvar(pipeline_ids: [vendas.first.id], default_stage_id: proposta.id, modo: 'chegou',
           people: [pessoa(ana, triage: false, pipeline_ids: [vendas.first.id]),
                    pessoa(leo, triage: false, pipeline_ids: [], only_own: true)])

    expect(response).to have_http_status(:ok)
    expect(account.crm_inbox_settings.find_by(inbox: inbox))
      .to have_attributes(default_pipeline_id: vendas.first.id, default_stage_id: proposta.id,
                          auto_create_card: true, subject_ai_mode: 'off')
    link = account.crm_pipeline_inboxes.find_by(inbox: inbox, pipeline: vendas.first)
    expect(link).to have_attributes(auto_create_card: true, default_stage_id: proposta.id)
    # Com um funil só, quem cuida do funil cuida também da conversa sem card: Ana fica como hoje.
    expect(acesso(ana)).to be_nil
    expect(acesso(leo)).to have_attributes(all_pipelines: false, triage: false, only_own: true)
  end

  it 'drops the pipelines taken out of the inbox and, with none left, takes the inbox out of the CRM' do
    salvar(pipeline_ids: [vendas.first.id, pos_venda.first.id], modo: 'off',
           people: [pessoa(ana, triage: true, pipeline_ids: [vendas.first.id, pos_venda.first.id])])
    salvar(pipeline_ids: [vendas.first.id], modo: 'chegou', people: [])
    expect(account.crm_pipeline_inboxes.where(inbox: inbox).pluck(:pipeline_id)).to eq([vendas.first.id])

    salvar(pipeline_ids: [], modo: 'off', people: [])

    expect(response).to have_http_status(:ok)
    expect(account.crm_inbox_settings.find_by(inbox: inbox)).to have_attributes(crm_enabled: false, auto_create_card: false)
    expect(account.crm_pipeline_inboxes.where(inbox: inbox).pluck(:auto_create_card)).to eq([false])
    expect(response.parsed_body.dig('payload', 'caixa', 'pipeline_ids')).to eq([])
  end

  it 'refuses people outside the inbox and pipelines of another account' do
    outsider = create_crm_agent(account: account, name: 'Fora').first
    salvar(pipeline_ids: [vendas.first.id], modo: 'off', people: [pessoa(outsider, triage: true, pipeline_ids: [])])
    expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.pessoa_invalida')

    other_account, other_admin = create_account_and_user
    foreign = create_crm_pipeline(account: other_account, user: other_admin).first
    salvar(pipeline_ids: [foreign.id], modo: 'chegou', people: [])
    expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.funil_invalido')
  end

  context 'when the inbox is still on "assigned only" (R6)' do
    before do
      account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, visibility_mode: :assigned_only,
                                         default_pipeline: vendas.first)
    end

    it 'refuses to save without an explicit choice, so nobody starts seeing more by accident' do
      salvar(pipeline_ids: [vendas.first.id], modo: 'off', people: [pessoa(ana, triage: true, pipeline_ids: [vendas.first.id])])

      expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.legado_pendente')
      expect(account.crm_inbox_settings.find_by(inbox: inbox).visibility_mode).to eq('assigned_only')
    end

    it 'keeps each agent on "only theirs" when the admin keeps it that way' do
      salvar(pipeline_ids: [vendas.first.id], modo: 'off', legado: 'manter',
             people: [pessoa(ana, triage: true, pipeline_ids: [vendas.first.id], only_own: true),
                      pessoa(leo, triage: true, pipeline_ids: [vendas.first.id], only_own: true)])

      expect(account.crm_inbox_settings.find_by(inbox: inbox).visibility_mode).to eq('all_inbox_cards')
      expect([acesso(ana), acesso(leo)].map(&:only_own)).to eq([true, true])
    end

    it 'uses what was selected when the admin chooses to change' do
      salvar(pipeline_ids: [vendas.first.id], modo: 'off', legado: 'mudar',
             people: [pessoa(ana, triage: true, pipeline_ids: [vendas.first.id])])

      expect(account.crm_inbox_settings.find_by(inbox: inbox).visibility_mode).to eq('all_inbox_cards')
      expect(acesso(ana)).to be_nil
    end
  end

  it 'leaves links and grants of archived pipelines untouched' do
    arquivado = create_crm_pipeline(account: account, user: admin, name: 'Antigo').first
    account.crm_pipeline_inboxes.create!(inbox: inbox, pipeline: arquivado)
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: ana, all_pipelines: false)
    access.agent_pipelines.create!(account: account, pipeline: arquivado)
    arquivado.update!(status: :archived)

    salvar(pipeline_ids: [vendas.first.id, pos_venda.first.id], modo: 'off',
           people: [pessoa(ana, triage: true, pipeline_ids: [vendas.first.id])])

    expect(response).to have_http_status(:ok)
    expect(account.crm_pipeline_inboxes.where(inbox: inbox, pipeline: arquivado)).to exist
    expect(access.agent_pipelines.reload.pluck(:pipeline_id)).to contain_exactly(arquivado.id, vendas.first.id)
  end

  it 'expires pending subject suggestions of a pipeline taken out of the inbox' do
    salvar(pipeline_ids: [vendas.first.id, pos_venda.first.id], modo: 'suggest',
           people: [pessoa(ana, triage: true, pipeline_ids: [vendas.first.id, pos_venda.first.id])])
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: account.contacts.create!(name: 'Cliente'))
    decision = Crm::SubjectDecision.create!(account: account, conversation: conversation, mode: 'suggest', action: 'create',
                                            state: 'suggested', pipeline: pos_venda.first, title: 'Troca')

    salvar(pipeline_ids: [vendas.first.id], modo: 'chegou', people: [])

    expect(decision.reload.state).to eq('expired')
  end

  it 'refuses a start stage from another pipeline, a body without caixa and an inbox of another account' do
    salvar(pipeline_ids: [vendas.first.id], default_stage_id: pos_venda.last.id, modo: 'chegou', people: [])
    expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.etapa_invalida')

    put "#{url}/#{inbox.id}", params: { pipeline_ids: [] }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    other_account, other_admin = create_account_and_user
    other_inbox = create_crm_inbox(account: other_account, members: [other_admin])
    get "#{url}/#{other_inbox.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:not_found)
  end

  # #1676: a IA de assunto em Automática por padrão, atrás da flag do #1675 (contas 1, 16 e 18 por enquanto).
  describe 'IA de assunto por padrão (#1676)' do
    def setting
      account.crm_inbox_settings.find_by(inbox: inbox)
    end

    def triagem
      [pessoa(ana, triage: true, pipeline_ids: [vendas.first.id, pos_venda.first.id])]
    end

    def caixa_listada
      inbox
      get url, headers: auth_headers(admin)
      response.parsed_body.dig('payload', 'caixas').find { |item| item.dig('inbox', 'id') == inbox.id }
    end

    context 'with the crm_avaliar_toda_mensagem flag' do
      before { account.enable_features!(Crm::Conversations::CardEmFoco::FLAG) }

      it 'saves a single-pipeline inbox with the subject AI on Automatic, in "chegou" and by hand', :aggregate_failures do
        salvar(pipeline_ids: [vendas.first.id], modo: 'chegou', people: [])
        expect(response).to have_http_status(:ok)
        expect(setting).to have_attributes(auto_create_card: true, subject_ai_mode: 'auto')

        salvar(pipeline_ids: [vendas.first.id], modo: 'off', people: [])
        expect(setting).to have_attributes(auto_create_card: false, subject_ai_mode: 'auto')
      end

      it 'keeps what the screen sent with several pipelines, and off without pipelines', :aggregate_failures do
        salvar(pipeline_ids: [vendas.first.id, pos_venda.first.id], modo: 'suggest', people: triagem)
        expect(setting.subject_ai_mode).to eq('suggest')

        salvar(pipeline_ids: [vendas.first.id, pos_venda.first.id], modo: 'off', people: triagem)
        expect(setting.subject_ai_mode).to eq('off')

        salvar(pipeline_ids: [], modo: 'off', people: [])
        expect(setting).to have_attributes(crm_enabled: false, subject_ai_mode: 'off')
      end

      it 'shows Automatic for an inbox without CRM settings, and the saved mode for the others (no data change)' do
        expect(caixa_listada['subject_ai_mode']).to eq('auto')

        account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, subject_ai_mode: :off)
        expect(caixa_listada['subject_ai_mode']).to eq('off')
        expect(setting.reload.subject_ai_mode).to eq('off')
      end
    end

    context 'without the flag' do
      it 'keeps the subject AI off with one pipeline and shows off for an inbox without settings, as before',
         :aggregate_failures do
        expect(caixa_listada['subject_ai_mode']).to eq('off')

        salvar(pipeline_ids: [vendas.first.id], modo: 'chegou', people: [])
        expect(setting.subject_ai_mode).to eq('off')
      end
    end
  end
end
