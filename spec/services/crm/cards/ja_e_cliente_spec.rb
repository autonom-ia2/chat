require 'rails_helper'

# #2710, variante 2: o card que a página de agendamento cria para quem já comprou leva o selo "Já é cliente desde…", que
# abre o card ganho do mesmo contato. Só para quem pode ver o card ganho; uma consulta para a página inteira do quadro.
RSpec.describe Crm::Cards::JaECliente do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_and_account_user) { create_crm_agent(account: account) }
  let(:agent) { agent_and_account_user.first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:customer_since) { Time.zone.parse('2026-11-03 10:00') }
  let(:contact) { new_contact(customer: true) }

  def new_contact(customer:)
    contact = account.contacts.create!(name: 'Ana Costa', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    contact.update!(contact_type: :customer, customer_since: customer_since) if customer
    contact
  end

  def card((pipeline, stage), contact: self.contact, status: :open, source: 'public_link', card_inbox: inbox)
    created = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Ana Costa - Agenda', inbox: card_inbox,
                                        contact: contact, source: source)
    created.update_columns(status: Crm::Card.statuses[status], closed_at: Time.current) unless status == :open # rubocop:disable Rails/SkipsModelValidations
    created
  end

  def selos(cards, user: admin)
    account_user = user.account_users.find_by(account: account)
    described_class.new(user: user, account: account, account_user: account_user).para(cards.map(&:reload))
  end

  it 'leva o card ganho do contato e a data em que ele virou cliente ao card que a página criou' do
    ganho = card(pos_venda, status: :won, source: nil)
    agenda = card(vendas)

    expect(selos([agenda])).to eq(agenda.id => { card_id: ganho.id, desde: customer_since.to_i })
  end

  it 'vale para o convite e aponta para a compra mais recente' do
    card(pos_venda, status: :won, source: nil).update_columns(closed_at: 2.months.ago) # rubocop:disable Rails/SkipsModelValidations
    recente = card(pos_venda, status: :won, source: nil)
    convite = card(vendas, source: 'invite')

    expect(selos([convite]).dig(convite.id, :card_id)).to eq(recente.id)
  end

  it 'usa a data do ganho quando o contato não tem a data de cliente' do
    ganho = card(pos_venda, status: :won, source: nil)
    contact.update_columns(customer_since: nil) # rubocop:disable Rails/SkipsModelValidations
    agenda = card(vendas)

    expect(selos([agenda]).dig(agenda.id, :desde)).to eq(ganho.reload.closed_at.to_i)
  end

  it 'não põe selo em card que não veio da página, em card fechado, em quem não é cliente nem sem compra' do
    card(pos_venda, status: :won, source: nil)
    manual = card(vendas, source: nil)
    perdido = card(vendas, status: :lost)
    lead = new_contact(customer: false)
    card(pos_venda, contact: lead, status: :won, source: nil)
    agenda_do_lead = card(vendas, contact: lead)
    sem_compra = card(vendas, contact: new_contact(customer: true))

    expect(selos([manual, perdido, agenda_do_lead, sem_compra])).to eq({})
  end

  describe 'quem pode ver o card ganho' do
    it 'não manda o selo a quem não vê a caixa do card ganho' do
      card(pos_venda, status: :won, source: nil, card_inbox: create_crm_inbox(account: account, name: 'Outra caixa'))
      agenda = card(vendas)

      expect(selos([agenda], user: agent)).to eq({})
      expect(selos([agenda], user: admin)).to have_key(agenda.id)
    end

    it 'não manda o selo a quem não alcança o funil do card ganho' do
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false, triage: false)
      access.agent_pipelines.create!(account: account, pipeline: vendas.first)
      ganho = card(pos_venda, status: :won, source: nil)
      agenda = card(vendas)

      expect(Crm::CardPolicy.new({ user: agent, account: account, account_user: agent_and_account_user.last }, ganho).show?).to be(false)
      expect(selos([agenda], user: agent)).to eq({})
    end

    it 'não manda o selo a quem não vê o card ganho numa caixa "Só as suas"' do
      account.crm_inbox_settings.create!(inbox: inbox, visibility_mode: :assigned_only)
      outra_caixa = create_crm_inbox(account: account, name: 'Caixa aberta', members: [agent])
      ganho = card(pos_venda, status: :won, source: nil)
      agenda = card(vendas, card_inbox: outra_caixa)

      expect(selos([agenda], user: agent)).to eq({})

      ganho.update_columns(owner_id: agent.id) # rubocop:disable Rails/SkipsModelValidations
      expect(selos([agenda], user: agent)).to eq(agenda.id => { card_id: ganho.id, desde: customer_since.to_i })
    end

    it 'manda o selo a quem vê o card ganho' do
      ganho = card(pos_venda, status: :won, source: nil)
      agenda = card(vendas)

      expect(Crm::CardPolicy.new({ user: agent, account: account, account_user: agent_and_account_user.last }, ganho).show?).to be(true)
      expect(selos([agenda], user: agent)).to eq(agenda.id => { card_id: ganho.id, desde: customer_since.to_i })
    end
  end

  it 'responde a página inteira com uma consulta só, uma linha por contato' do
    contatos = Array.new(3) { new_contact(customer: true) }
    contatos.each do |dono|
      card(pos_venda, contact: dono, status: :won, source: nil).update_columns(closed_at: 1.year.ago) # rubocop:disable Rails/SkipsModelValidations
      card(pos_venda, contact: dono, status: :won, source: nil)
    end
    agendas = Crm::Card.where(id: contatos.map { |dono| card(vendas, contact: dono).id }).includes(:contact).to_a
    account_user = admin.account_users.includes(:account).find_by(account: account)
    servico = described_class.new(user: admin, account: account, account_user: account_user)

    consultas = []
    contar = lambda do |*, payload|
      consultas << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:name] == 'CACHE' || payload[:cached]
    end
    resultado = ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') { servico.para(agendas) }

    expect(resultado.keys).to match_array(agendas.map(&:id))
    expect(consultas.size).to eq(1)
    expect(consultas.first).to include('DISTINCT ON (crm_cards.contact_id)')
  end

  describe 'onde o selo sai' do
    around do |example|
      with_modified_env CRM_KANBAN_ENABLED: 'true' do
        example.run
      end
    end

    let!(:ganho) { card(pos_venda, status: :won, source: nil) }
    let!(:agenda) { card(vendas) }
    let(:selo) { { card_id: ganho.id, desde: customer_since.to_i } }

    def account_user_of(user) = user.account_users.find_by(account: account)

    it 'no quadro, no card da página; o selo "Cliente" dos outros cards segue igual' do
      outro = card(vendas, source: nil)
      context = Crm::Kanban::BoardContext.new(params: {}, account: account, user: admin, account_user: account_user_of(admin))
      payload = Crm::Kanban::BoardPayloadBuilder.new(pipeline: vendas.first, cards_scope: account.crm_cards, context: context).perform
      cards = payload[:stages].flat_map { |stage| stage[:cards] }.index_by { |item| item[:id] }

      expect(cards[agenda.id][:ja_cliente]).to eq(selo)
      expect(cards[outro.id]).not_to have_key(:ja_cliente)
      expect(cards[outro.id][:contact][:contact_type]).to eq('customer')
    end

    it 'no card aberto' do
      detail = Crm::Cards::DetailPayloadBuilder.new(card: agenda.reload, user: admin, account_user: account_user_of(admin)).perform

      expect(detail[:ja_cliente]).to eq(selo)
    end

    it 'no tempo real, só para quem vê o card ganho' do
      ganho.update_columns(inbox_id: create_crm_inbox(account: account, name: 'Outra caixa').id) # rubocop:disable Rails/SkipsModelValidations
      chamadas = []
      allow(ActionCableBroadcastJob).to receive(:perform_later) { |tokens, _evento, payload| chamadas << [tokens.first, payload] }
      allow(Crm::Card).to receive(:won).and_call_original

      Crm::Cards::Broadcaster.broadcast(agenda, Events::Types::CRM_CARD_CREATED)
      por_pessoa = chamadas.to_h

      expect(por_pessoa[admin.pubsub_token][:ja_cliente]).to eq(selo)
      expect(por_pessoa[agent.pubsub_token][:ja_cliente]).to be_nil
      # As compras do contato saem uma vez por evento, não uma vez por destinatário.
      expect(Crm::Card).to have_received(:won).once
    end
  end
end
