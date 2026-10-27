require 'rails_helper'

# Lista nova "o que fazer agora" (#2283): grupos, ordem, filtros e contagem pelo mesmo CASE.
RSpec.describe Crm::Cards::ActionGroups do
  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Gestora') }
  let(:admin_membership) { admin.account_users.find_by!(account: account) }
  let(:colleague) { create(:user, account: account, role: :agent, name: 'Colega') }
  let(:inbox) { create_crm_inbox(account: account, members: [admin, colleague]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:visibility) { Crm::Conversations::Visibility.new(account: account, user: admin, account_user: admin_membership) }

  def conversation(assignee: nil, waiting: false)
    contact = create(:contact, account: account)
    create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: assignee).tap do |record|
      # A conversa nasce esperando (ensure_waiting_since); só a que espera fica com a marca.
      record.update_columns(waiting_since: waiting ? 2.hours.ago : nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def card(title, conversation: nil, owner: nil, **attributes)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: title, owner: owner, inbox: inbox,
                              primary_conversation: conversation, **attributes)
  end

  def follow_up(card, due_at:, status: :pending, mode: :reminder_only, source: nil)
    record = account.crm_follow_ups.create!(card: card, created_by: admin, title: 'Retorno', due_at: due_at,
                                            timezone: 'America/Sao_Paulo', status: status,
                                            metadata: source ? { 'source' => source } : {})
    # Envio automático exige modelo e janela (AutoSendValidator); aqui só o modo importa.
    record.update_columns(automation_mode: Crm::FollowUp.automation_modes[mode]) unless mode == :reminder_only # rubocop:disable Rails/SkipsModelValidations
    record
  end

  def stale!(card, days: 10)
    card.update_columns(last_message_at: days.days.ago, entered_stage_at: days.days.ago) # rubocop:disable Rails/SkipsModelValidations
  end

  def query(params = {})
    Crm::Cards::FilterQuery.new(scope: account.crm_cards, params: params.with_indifferent_access,
                                conversation_visibility: visibility, account: account, account_user: admin_membership).perform
  end

  def groups(params = {})
    query(params.merge(sort: 'acao')).select('crm_cards.*', described_class::SELECT)
                                     .to_h { |row| [row.title, described_class::KEYS[row[:acao_grupo]]] }
  end

  def summary(params = {})
    Current.account = account
    Current.account_user = admin_membership
    Crm::Cards::GroupSummary.new(scope: account.crm_cards, params: params.merge(group_by: 'acao').with_indifferent_access,
                                 group_by: 'acao', conversation_visibility: visibility).perform[:groups]
                            .to_h { |group| [group[:key], group[:count]] }
  ensure
    Current.reset
  end

  describe 'grupos' do
    it 'põe cada card no primeiro grupo que vale' do
      card('Esperando', conversation: conversation(assignee: colleague, waiting: true), owner: colleague)
      waiting_and_due = card('Esperando e com retorno', conversation: conversation(assignee: colleague, waiting: true), owner: colleague)
      follow_up(waiting_and_due, due_at: 1.day.ago, status: :overdue)
      overdue = card('Retorno de ontem', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(overdue, due_at: 1.day.ago, status: :overdue)
      card('Ninguém cuidando', conversation: conversation)
      stale!(card('Parado', owner: colleague, conversation: conversation(assignee: colleague)))
      card('Os demais', owner: colleague, conversation: conversation(assignee: colleague))

      expect(groups).to eq(
        'Esperando' => 'esperando', 'Esperando e com retorno' => 'esperando', 'Retorno de ontem' => 'retorno',
        'Ninguém cuidando' => 'ninguem', 'Parado' => 'parado', 'Os demais' => 'demais'
      )
    end

    it 'deixa envio automático pendente e toque da IA de hoje fora de "retorno"' do
      auto_send = card('Mensagem programada', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(auto_send, due_at: 1.minute.from_now, mode: :auto_send_message)
      ai_touch = card('Assistente retoma', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(ai_touch, due_at: 1.minute.from_now, source: Crm::FollowUp::AI_FOLLOWUP_SOURCE)
      done = card('Retorno feito', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(done, due_at: 1.hour.ago, status: :done)
      snooze = card('Adiar conversa', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(snooze, due_at: 1.minute.from_now).update!(automation_mode: :snooze_conversation, conversation: snooze.primary_conversation)

      expect(groups).to eq('Mensagem programada' => 'demais', 'Assistente retoma' => 'demais', 'Retorno feito' => 'demais',
                           'Adiar conversa' => 'retorno')
    end

    it 'conta retorno até o fim de hoje no fuso da conta, não amanhã' do
      today = card('Hoje à noite', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(today, due_at: Crm::Timezone::Resolver.new(account: account).zone_or_default.now.end_of_day - 1.minute)
      tomorrow = card('Amanhã', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(tomorrow, due_at: Crm::Timezone::Resolver.new(account: account).zone_or_default.now.end_of_day + 1.minute)

      expect(groups).to eq('Hoje à noite' => 'retorno', 'Amanhã' => 'demais')
    end

    it 'não põe em "ninguém cuidando" o card com robô, com pessoa na conversa ou com dono' do
      bot_inbox = create_crm_inbox(account: account, name: 'Caixa do robô', members: [admin])
      AgentBotInbox.create!(inbox: bot_inbox, agent_bot: create(:agent_bot, account: account), status: :active)
      bot_conversation = create_crm_conversation(account: account, inbox: bot_inbox, contact: create(:contact, account: account))
      bot_conversation.update_columns(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations
      card('Robô cuida', conversation: bot_conversation, inbox: bot_inbox)
      card('Pessoa na conversa', conversation: conversation(assignee: colleague))
      card('Tem dono', owner: colleague, conversation: conversation)
      card('Sem conversa e sem dono')
      card('Sem conversa, caixa com robô', inbox: bot_inbox)

      expect(groups).to eq('Robô cuida' => 'demais', 'Pessoa na conversa' => 'demais', 'Tem dono' => 'demais',
                           'Sem conversa e sem dono' => 'ninguem', 'Sem conversa, caixa com robô' => 'demais')
    end

    it 'tira de "parado" o card com retorno da pessoa marcado para depois' do
      combined = card('Parado com retorno', owner: colleague, conversation: conversation(assignee: colleague))
      stale!(combined)
      follow_up(combined, due_at: 3.days.from_now)
      robot_touch = card('Parado só com toque da IA', owner: colleague, conversation: conversation(assignee: colleague))
      stale!(robot_touch)
      follow_up(robot_touch, due_at: 3.days.from_now, source: Crm::FollowUp::AI_FOLLOWUP_SOURCE)

      expect(groups).to eq('Parado com retorno' => 'demais', 'Parado só com toque da IA' => 'parado')
    end
  end

  describe 'ordem' do
    it 'ordena por grupo, dentro do grupo e desempata por score e id, com páginas estáveis' do
      older_wait = card('Espera há mais tempo', owner: colleague, conversation: conversation(assignee: colleague, waiting: true))
      older_wait.primary_conversation.update_columns(waiting_since: 5.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      card('Espera há pouco', owner: colleague, conversation: conversation(assignee: colleague, waiting: true))
      later = card('Retorno de hoje', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(later, due_at: 1.minute.ago)
      earlier = card('Retorno de ontem', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(earlier, due_at: 1.day.ago, status: :overdue)
      card('Entrou antes', created_at: 2.days.ago)
      card('Entrou depois', created_at: 1.hour.ago)
      stale!(card('Parado há 9 dias', owner: colleague, conversation: conversation(assignee: colleague)), days: 9)
      stale!(card('Parado há 14 dias', owner: colleague, conversation: conversation(assignee: colleague)), days: 14)
      card('Demais sem retorno', owner: colleague, score: 90)
      follow_up(card('Demais com retorno', owner: colleague), due_at: 2.days.from_now)
      tie_a = card('Empate A', owner: colleague, score: 10)
      tie_b = card('Empate B', owner: colleague, score: 10)

      titles = query(sort: 'acao').map(&:title)
      expect(titles).to eq(['Espera há mais tempo', 'Espera há pouco', 'Retorno de ontem', 'Retorno de hoje', 'Entrou antes',
                            'Entrou depois', 'Parado há 14 dias', 'Parado há 9 dias', 'Demais com retorno',
                            'Demais sem retorno', tie_b.title, tie_a.title])
      paged = (1..4).flat_map { |page| query(sort: 'acao').page(page).per(3).map(&:title) }
      expect(paged).to eq(titles)
    end

    it 'põe primeiro, em "esperando", o SLA mais perto quando a conta usa SLA' do
      account.enable_features!('sla')
      older = card('Espera há 5 horas sem SLA', owner: colleague, conversation: conversation(assignee: colleague, waiting: true))
      older.primary_conversation.update_columns(waiting_since: 5.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      with_sla = card('Espera há 1 hora com SLA', owner: colleague, conversation: conversation(assignee: colleague, waiting: true))
      create(:applied_sla, conversation: with_sla.primary_conversation,
                           sla_policy: create(:sla_policy, account: account, next_response_time_threshold: 600))

      expect(query(sort: 'acao').map(&:title)).to eq(['Espera há 1 hora com SLA', 'Espera há 5 horas sem SLA'])
    end

    it 'ordena "os demais" pelo retorno da pessoa, não pelo toque da IA que está mais perto' do
      ai_only = card('Só toque da IA amanhã', owner: colleague, next_follow_up_at: 1.day.from_now)
      follow_up(ai_only, due_at: 1.day.from_now, source: Crm::FollowUp::AI_FOLLOWUP_SOURCE)
      person = card('Retorno da pessoa em 3 dias', owner: colleague, next_follow_up_at: 3.days.from_now)
      follow_up(person, due_at: 3.days.from_now)

      expect(query(sort: 'acao').map(&:title)).to eq(['Retorno da pessoa em 3 dias', 'Só toque da IA amanhã'])
    end
  end

  describe 'filtros e contagem' do
    before do
      card('Esperando', owner: colleague, conversation: conversation(assignee: colleague, waiting: true))
      due = card('Retorno', owner: colleague, conversation: conversation(assignee: colleague))
      follow_up(due, due_at: 1.day.ago, status: :overdue)
      card('Ninguém', conversation: conversation)
      card('Demais', owner: colleague, conversation: conversation(assignee: colleague))
    end

    it 'filtra esperando, retorno e grupo com o mesmo número da contagem' do
      counts = summary

      expect(counts).to eq('esperando' => 1, 'retorno' => 1, 'ninguem' => 1, 'parado' => 0, 'demais' => 1)
      expect(query(waiting: 'true').map(&:title)).to eq(['Esperando'])
      expect(query(follow_up_status: 'due').map(&:title)).to eq(['Retorno'])
      expect(query(action_group: 'ninguem').map(&:title)).to eq(['Ninguém'])
      expect(query(sort: 'acao').count).to eq(counts.values.sum)
    end

    it 'mostra lista vazia, e não a lista inteira, quando o grupo pedido não existe' do
      expect(query(action_group: 'qualquer')).to be_empty
      expect(query(action_group: 'retorno').map(&:title)).to eq(['Retorno'])
    end

    it 'conta uma vez o card com várias conversas, sem eager_load, com o grupo na linha' do
      many = card('Várias conversas', owner: colleague, conversation: conversation(assignee: colleague, waiting: true))
      2.times { many.card_conversations.create!(account: account, conversation: conversation(assignee: colleague), linked_by: admin) }
      relation = query(sort: 'acao', waiting: 'true')

      expect(relation.eager_loading?).to be(false)
      expect(relation.references_values).to be_empty
      expect(relation.count).to eq(2)
      expect(relation.select('crm_cards.*', described_class::SELECT).map { |row| [row.title, row[:acao_grupo]] })
        .to contain_exactly(['Esperando', 1], ['Várias conversas', 1])
      expect(summary).to include('esperando' => 2)
      expect(summary.values.sum).to eq(query(sort: 'acao').count)
    end

    it 'devolve os cinco grupos na ordem, com zero e com valor' do
      Current.account = account # como no controller: o FilterQuery lê a conta do Current
      result = Crm::Cards::GroupSummary.new(scope: account.crm_cards, params: { group_by: 'acao' }.with_indifferent_access,
                                            group_by: 'acao', conversation_visibility: visibility).perform

      expect(result[:group_by]).to eq('acao')
      expect(result[:groups].pluck(:key)).to eq(%w[esperando retorno ninguem parado demais])
      expect(result[:groups].find { |group| group[:key] == 'parado' }).to include(count: 0, sum_cents: 0, currency: 'BRL')
    ensure
      Current.reset
    end
  end

  describe 'só meus' do
    let(:me) { colleague }
    let(:me_membership) { colleague.account_users.find_by!(account: account) }
    let(:visibility) { Crm::Conversations::Visibility.new(account: account, user: me, account_user: me_membership) }

    def mine_groups(extra = {})
      Crm::Cards::FilterQuery.new(scope: account.crm_cards, params: { sort: 'acao', mine: 'true' }.merge(extra).with_indifferent_access,
                                  conversation_visibility: visibility, account: account, account_user: me_membership)
                             .perform.select('crm_cards.*', described_class::SELECT)
                             .to_h { |row| [row.title, described_class::KEYS[row[:acao_grupo]]] }
    end

    it 'traz os meus, a conversa minha esperando em card de outro dono e quem ninguém cuida' do
      card('Meu', owner: me, conversation: conversation(assignee: admin))
      card('Sem dono, conversa minha', conversation: conversation(assignee: me))
      card('De outro, conversa minha esperando', owner: admin, conversation: conversation(assignee: me, waiting: true))
      card('De outro, conversa minha parada', owner: admin, conversation: conversation(assignee: me))
      card('Ninguém cuidando', conversation: conversation)
      card('De outro', owner: admin, conversation: conversation(assignee: admin, waiting: true))

      expect(mine_groups).to eq('De outro, conversa minha esperando' => 'esperando', 'Ninguém cuidando' => 'ninguem',
                                'Meu' => 'demais', 'Sem dono, conversa minha' => 'demais')
    end
  end
end
