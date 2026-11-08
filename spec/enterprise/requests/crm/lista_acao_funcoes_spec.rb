require 'rails_helper'

# Lista nova (sort=acao, #2283) com função personalizada: LINHA DE BASE da Issue #2299.
#
# Hoje o CRM decide a visibilidade da conversa pela caixa, pela opção "só as atribuídas" e pelo funil
# (Crm::Conversations::Visibility); as chaves de conversa da função não entram. Por isso os três casos abaixo saem
# iguais a um agente sem função: a conversa de um colega na caixa da pessoa aparece (grupo, quem cuida e retorno),
# mesmo com só "as minhas" ou sem chave de conversa. Este spec registra o comportamento ATUAL e VAI MUDAR com a
# #2299, que faz o CRM seguir a mesma regra da tela de conversas (Conversations::PermissionFilterService).
RSpec.describe 'CRM Lista nova com função personalizada (linha de base #2299)', type: :request do
  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Gestora Ana') }
  let(:person) { create(:user, name: 'Pessoa da Função') }
  let(:inbox) { create_crm_inbox(account: account, members: [admin, person]) }
  let(:hidden_inbox) { create_crm_inbox(account: account, name: 'Caixa da gestão', members: [admin]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:api) { "/api/v1/accounts/#{account.id}/crm" }

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    create(:account_user, account: account, user: person, role: :agent, custom_role: role)
  end

  def conversation(inbox:, assignee:)
    create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account), assignee: assignee).tap do |record|
      record.update_columns(waiting_since: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def card_with_overdue_follow_up(title, conversation)
    pipeline, stage = pipeline_and_stage
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: title, inbox: inbox, primary_conversation: conversation)
    follow_up = account.crm_follow_ups.create!(card: card, conversation: conversation, created_by: admin, title: "Retorno #{title}",
                                               due_at: 1.day.ago, timezone: 'America/Sao_Paulo', status: :overdue)
    [card, follow_up]
  end

  def rows
    get "#{api}/cards", params: { sort: 'acao', per_page: 100 }, headers: auth_headers(person)
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload'].index_by { |row| row['id'] }
  end

  def counts
    get "#{api}/cards/summaries", params: { group_by: 'acao' }, headers: auth_headers(person)
    expect(response).to have_http_status(:ok)
    response.parsed_body.dig('payload', 'groups').to_h { |group| [group['key'], group['count']] }
  end

  {
    'só as minhas (conversation_participating_manage)' => %w[crm_view conversation_participating_manage],
    'só olhar (conversation_view)' => %w[crm_view conversation_view],
    'sem chave de conversa' => %w[crm_view]
  }.each do |label, permissions|
    context label do
      before { give_role(permissions) }

      it 'segue só a caixa: a conversa do colega aparece e a da caixa que não vê fica oculta (muda com a #2299)' do
        colleague_conversation = conversation(inbox: inbox, assignee: admin)
        colleague, colleague_follow_up = card_with_overdue_follow_up('Colega', colleague_conversation)
        hidden, = card_with_overdue_follow_up('Oculta', conversation(inbox: hidden_inbox, assignee: admin))

        by_id = rows

        # Comportamento atual: a função não restringe a conversa da caixa da pessoa.
        expect(by_id[colleague.id]).to include('action_group' => 'esperando', 'next_follow_up_id' => colleague_follow_up.id,
                                               'conversation_id' => colleague_conversation.id)
        expect(by_id[colleague.id]['current_responsible']).to include('type' => 'agent', 'name' => 'Gestora Ana')
        # A conversa de caixa que a pessoa não vê já fica oculta: sem grupo de conversa, sem quem cuida e sem o retorno.
        expect(by_id[hidden.id]).to include('action_group' => 'demais', 'next_follow_up_id' => nil, 'conversation_id' => nil,
                                            'current_responsible' => nil)
        expect(by_id[hidden.id]).not_to have_key('responsible')
        expect(counts).to eq('esperando' => 1, 'retorno' => 0, 'ninguem' => 0, 'parado' => 0, 'demais' => 1)
      end
    end
  end

  # "Mais → Organizar por → Quem cuida" (#2379): o grupo de cada linha é o current_responsible que ela mostra, e nem a
  # linha nem a contagem trazem quem atende a conversa que a função não vê. Sem `sales_value_view`, sem soma de valor.
  describe 'organizar por quem cuida' do
    before { give_role(%w[crm_view]) }

    it 'agrupa igual à linha, sem o atendente da conversa oculta e sem somar valor' do
      bot = create(:agent_bot, account: account, name: 'Assistente Bia')
      AgentBotInbox.create!(inbox: hidden_inbox, agent_bot: bot, status: :active)
      card_with_overdue_follow_up('Colega', conversation(inbox: inbox, assignee: admin))
      hidden, = card_with_overdue_follow_up('Oculta com robô', conversation(inbox: hidden_inbox, assignee: admin))

      get "#{api}/cards", params: { sort: 'quem_cuida', per_page: 100 }, headers: auth_headers(person)
      expect(response).to have_http_status(:ok)
      line_keys = response.parsed_body['payload'].map do |row|
        responsible = row['current_responsible']
        responsible && "#{responsible['type']}:#{responsible['id']}"
      end
      expect(response.parsed_body['payload'].find { |row| row['id'] == hidden.id }['current_responsible'])
        .to include('type' => 'bot', 'id' => bot.id)

      get "#{api}/cards/summaries", params: { group_by: 'quem_cuida' }, headers: auth_headers(person)
      expect(response).to have_http_status(:ok)
      groups = response.parsed_body.dig('payload', 'groups')
      expect(groups.pluck('key')).to match_array(line_keys.uniq)
      expect(groups.pluck('label')).to contain_exactly('Gestora Ana', 'Assistente Bia')
      expect(groups.pluck('sum_cents')).to all(be_nil)
      expect(groups.sum { |group| group['count'] }).to eq(line_keys.size)
    end
  end
end
