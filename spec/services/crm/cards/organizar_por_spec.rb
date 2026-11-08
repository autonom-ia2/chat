require 'rails_helper'

# Lista nova, "Mais → Organizar por" (#2379): quem cuida igual à linha, ordem estável entre páginas e contagem por card.
RSpec.describe Crm::Cards::OrganizarPor do
  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Gestora') }
  let(:viewer) { create(:user, account: account, role: :agent, name: 'Bruna') }
  let(:viewer_membership) { viewer.account_users.find_by!(account: account) }
  let(:hidden_attendant) { create(:user, account: account, role: :agent, name: 'Atendente Oculta') }
  # A caixa que quem lê vê, e a outra, onde a conversa fica oculta para ela.
  let(:inbox) { create_crm_inbox(account: account, members: [admin, viewer]) }
  let(:other_inbox) { create_crm_inbox(account: account, name: 'Outra caixa', members: [admin, hidden_attendant]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:visibility) { Crm::Conversations::Visibility.new(account: account, user: viewer, account_user: viewer_membership) }

  before do
    Current.account = account
    Current.account_user = viewer_membership
  end

  after { Current.reset }

  def conversation(on: inbox, assignee: nil)
    create_crm_conversation(account: account, inbox: on, contact: create(:contact, account: account), assignee: assignee).tap do |record|
      record.update_columns(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def card(title, stage: nil, **attributes)
    pipeline, first_stage = pipeline_and_stage
    account.crm_cards.create!({ pipeline: pipeline, stage: stage || first_stage, title: title, inbox: inbox }.merge(attributes))
  end

  def query(params = {})
    query_as(viewer_membership, visibility, params)
  end

  def query_as(membership, visible, params)
    Crm::Cards::FilterQuery.new(scope: account.crm_cards, params: params.with_indifferent_access, conversation_visibility: visible,
                                account: account, account_user: membership).perform
  end

  def quem_cuida_rows
    columns = ["#{described_class::QUEM_TIPO} AS quem_tipo", "#{described_class::QUEM_ID} AS quem_id"]
    query(sort: 'quem_cuida').select('crm_cards.*', *columns)
  end

  def summary(group_by, params = {}, membership: viewer_membership, value_visible: true)
    Current.account_user = membership
    Crm::Cards::GroupSummary.new(scope: account.crm_cards, params: params.merge(group_by: group_by).with_indifferent_access,
                                 group_by: group_by, conversation_visibility: visibility_for(membership),
                                 value_visible: value_visible).perform[:groups]
  end

  def visibility_for(membership)
    Crm::Conversations::Visibility.new(account: account, user: membership.user, account_user: membership)
  end

  # O "quem cuida" que a linha mostra: o current_responsible do payload, já sem o atendente da conversa oculta.
  def line_responsible(record)
    Crm::Cards::PayloadBuilder.new(record, user: viewer, account_user: viewer_membership, conversation_visibility: visibility)
                              .perform[:current_responsible]
  end

  def bot_inbox!
    create(:agent_bot, account: account, name: 'Assistente Bia').tap do |bot|
      AgentBotInbox.create!(inbox: other_inbox, agent_bot: bot, status: :active)
    end
  end

  describe 'quem cuida' do
    it 'agrupa cada card igual ao current_responsible da linha, sem revelar o atendente da conversa oculta' do
      bot = bot_inbox!
      owner = card('Dono', owner: admin, primary_conversation: conversation(assignee: viewer))
      visible = card('Sem dono, atendente visível', primary_conversation: conversation(assignee: viewer))
      hidden_conversation = conversation(on: other_inbox, assignee: hidden_attendant)
      hidden_bot = card('Sem dono, atendente oculto, com robô', inbox: other_inbox, primary_conversation: hidden_conversation)
      hidden_nobody_inbox = create_crm_inbox(account: account, name: 'Terceira caixa', members: [hidden_attendant])
      nobody_conversation = conversation(on: hidden_nobody_inbox, assignee: hidden_attendant)
      hidden_nobody = card('Sem dono, atendente oculto, sem robô', inbox: hidden_nobody_inbox, primary_conversation: nobody_conversation)
      nothing = card('Sem nada')

      rows = quem_cuida_rows.index_by(&:id)
      [owner, visible, hidden_bot, hidden_nobody, nothing].each do |record|
        expected = line_responsible(record.reload)
        row = rows.fetch(record.id)
        expect([row[:quem_tipo], row[:quem_id]]).to eq([expected&.dig(:type), expected&.dig(:id)]), record.title
      end
      expect(rows[hidden_bot.id][:quem_id]).to eq(bot.id)
      expect(rows.values.map { |row| row[:quem_id] }).not_to include(hidden_attendant.id)

      groups = summary('quem_cuida').index_by { |group| group[:key] }
      expect(groups.keys).to contain_exactly("agent:#{admin.id}", "agent:#{viewer.id}", "bot:#{bot.id}", nil)
      expect(groups["bot:#{bot.id}"]).to include(type: 'bot', label: 'Assistente Bia', count: 1)
      expect(groups[nil]).to include(type: nil, label: nil, count: 2)
      expect(groups.values.pluck(:label)).not_to include('Atendente Oculta')
    end

    it 'segue a linha com dono que saiu da conta e com robô apagado que deixou o vínculo na caixa' do
      gone = create(:user, account: account, role: :agent, name: 'Saiu da conta')
      left = card('Dono saiu', owner: gone)
      AccountUser.where(user: gone, account: account).delete_all
      bot = bot_inbox!
      orphan = card('Robô apagado', inbox: other_inbox)
      AgentBot.where(id: bot.id).delete_all

      rows = quem_cuida_rows.index_by(&:id)
      [left, orphan].each do |record|
        expected = line_responsible(Crm::Card.find(record.id))
        expect([rows[record.id][:quem_tipo], rows[record.id][:quem_id]]).to eq([expected&.dig(:type), expected&.dig(:id)]), record.title
      end
      groups = summary('quem_cuida').index_by { |group| group[:key] }
      expect(groups["agent:#{gone.id}"]).to include(label: 'Saiu da conta', count: 1)
      expect(groups[nil]).to include(count: 1)
    end

    # Sem índice único por caixa (#2298): o robô é o do has_one ordenado (InboxBotStatus), a linha ativa de menor id.
    it 'com várias linhas de robô na caixa, escolhe o mesmo robô que a linha' do
      paused, first, second = %w[Pausado Primeiro Segundo].map { |name| create(:agent_bot, account: account, name: name) }
      AgentBotInbox.create!(inbox: other_inbox, agent_bot: paused, status: :inactive)
      AgentBotInbox.create!(inbox: other_inbox, agent_bot: second, status: :active)
      AgentBotInbox.create!(inbox: other_inbox, agent_bot: first, status: :active)
      record = card('Duas linhas ativas', inbox: other_inbox)

      expected = line_responsible(Crm::Card.find(record.id))
      row = quem_cuida_rows.find { |item| item.id == record.id }
      expect([row[:quem_tipo], row[:quem_id]]).to eq([expected&.dig(:type), expected&.dig(:id)])
      expect(row[:quem_id]).to eq(second.id)
      expect(summary('quem_cuida').pluck(:key)).to eq(["bot:#{second.id}"])
    end

    it 'ordena pessoas e robôs por nome, ninguém no fim, com o grupo inteiro e páginas estáveis' do
      bot_inbox!
      zelia = create(:user, account: account, role: :agent, name: 'Zélia')
      3.times { |index| card("Zélia #{index}", owner: zelia) }
      3.times { |index| card("Bruna #{index}", owner: viewer) }
      2.times { |index| card("Robô #{index}", inbox: other_inbox) }
      2.times { |index| card("Ninguém #{index}") }

      titles = query(sort: 'quem_cuida').map(&:title)
      expect(titles.map { |title| title.split.first }.chunk_while { |a, b| a == b }.map(&:first))
        .to eq(%w[Bruna Zélia Robô Ninguém])
      paged = (1..4).flat_map { |page| query(sort: 'quem_cuida').page(page).per(3).map(&:title) }
      expect(paged).to eq(titles)
    end
  end

  describe 'etapa' do
    it 'ordena pela posição da etapa, o mais urgente primeiro dentro dela, e conta cada card uma vez' do
      pipeline, first = pipeline_and_stage
      later = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
      waiting = card('Proposta esperando', stage: later, owner: viewer, primary_conversation: conversation(assignee: viewer))
      waiting.primary_conversation.update_columns(waiting_since: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
      card('Proposta demais', stage: later, owner: viewer, value_cents: 10_000)
      many_conversation = conversation(assignee: viewer)
      many = card('Novo com várias conversas', stage: first, owner: viewer, value_cents: 5_000, primary_conversation: many_conversation)
      2.times { many.card_conversations.create!(account: account, conversation: conversation(assignee: viewer), linked_by: admin) }

      expect(query(sort: 'etapa').map(&:title)).to eq(['Novo com várias conversas', 'Proposta esperando', 'Proposta demais'])
      groups = summary('stage', { sort: 'etapa' }).index_by { |group| group[:key] }
      expect(groups[first.id]).to include(count: 1, sum_cents: 5_000)
      expect(groups[later.id]).to include(count: 2, sum_cents: 10_000)
      expect(summary('quem_cuida').sum { |group| group[:count] }).to eq(3)
      expect(summary('quem_cuida').find { |group| group[:key] == "agent:#{viewer.id}" }).to include(count: 3, sum_cents: 15_000)
    end
  end

  describe 'listas únicas' do
    it 'ordena pelo retorno da pessoa, por parado há mais tempo e pelo nome que a linha mostra' do
      soon = card('Retorno amanhã', owner: viewer)
      account.crm_follow_ups.create!(card: soon, created_by: admin, title: 'Retorno', due_at: 1.day.from_now, timezone: 'America/Sao_Paulo')
      later = card('Retorno em 3 dias', owner: viewer)
      account.crm_follow_ups.create!(card: later, created_by: admin, title: 'Retorno', due_at: 3.days.from_now, timezone: 'America/Sao_Paulo')
      card('Sem retorno', owner: viewer).update_columns(last_message_at: 20.days.ago, entered_stage_at: 20.days.ago) # rubocop:disable Rails/SkipsModelValidations
      card('Zeca', contact: create(:contact, account: account, name: 'Ana Contato'), owner: viewer)

      expect(query(sort: 'retorno').map(&:title).first(2)).to eq(['Retorno amanhã', 'Retorno em 3 dias'])
      expect(query(sort: 'parado').map(&:title).first).to eq('Sem retorno')
      expect(query(sort: 'nome').map(&:title).first).to eq('Zeca')
    end

    it 'põe o grupo de ação na linha da página em todas as ordens' do
      card('Algum', owner: viewer)
      described_class::SORTS.each do |sort|
        row = query(sort: sort).select('crm_cards.*', Crm::Cards::ActionGroups::SELECT).first
        expect(row[:acao_grupo]).to eq(5), sort
      end
    end
  end

  describe 'função personalizada' do
    let(:role) { create(:custom_role, account: account, permissions: %w[crm_view]) }
    let(:limited) { create(:user, account: account, role: :agent, name: 'Função limitada') }
    let(:limited_membership) { limited.account_users.find_by!(account: account).tap { |member| member.update!(custom_role: role) } }

    it 'não revela o atendente da conversa que a função não vê, não soma valor e larga a ordem por valor' do
      bot_inbox!
      card('Barato', owner: admin, value_cents: 100)
      card('Caro', owner: admin, value_cents: 90_000)
      hidden = card('Conversa oculta', inbox: other_inbox, value_cents: 500,
                                       primary_conversation: conversation(on: other_inbox, assignee: hidden_attendant))
      visible = visibility_for(limited_membership)

      groups = summary('quem_cuida', membership: limited_membership, value_visible: Crm::ValorDeVenda.ve?(limited_membership))
      expect(groups.pluck(:label)).not_to include('Atendente Oculta')
      expect(groups.find { |group| group[:key]&.start_with?('bot:') }).to include(count: 1, sum_cents: nil)
      expect(query_as(limited_membership, visible, { sort: 'valor' }).map(&:title))
        .to eq(query_as(limited_membership, visible, { sort: 'acao' }).map(&:title))
      expect(hidden.reload.primary_conversation.assignee).to eq(hidden_attendant)
    end
  end
end
