require 'rails_helper'

# Estado da página para a gaveta do agente de IA (#1305): `ai_status` sai da MESMA regra que decide se a IA pode marcar
# (`InvitePages#status`, lida por `Native::Agenda.estado`), e `recebe` diz quem recebe sem ninguém atribuído à conversa,
# só pelo nome de exibição. A lista não consulta a elegibilidade página por página.
RSpec.describe Crm::BookingV2::PageSerializer do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agenda', agent_type: 'scheduler', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'booking_page_id' => profile.id })
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before { account.enable_features!('crm_booking_v2') }

  def summary(page = profile)
    described_class.new(page.reload).summary
  end

  # O estado que a tela mostra é o mesmo que a IA usa para decidir se marca.
  def mesmo_estado_da_ia!(estado)
    expect(summary[:ai_status]).to eq(estado)
    expect(Autonomia::Agents::Tools::Native::Agenda.estado(agent.reload)).to eq(estado)
  end

  describe 'responsável fixo' do
    it 'ativa, com o nome de exibição do responsável da página, nada além do nome, e o fuso da página' do
      world.host.update!(display_name: 'Cami')

      mesmo_estado_da_ia!('ativa')
      expect(summary[:recebe]).to eq(modo: 'fixo', nome: 'Cami')
      expect(summary[:timezone]).to eq('America/Sao_Paulo')
      expect(summary[:timezone]).to eq(described_class.new(profile).full[:timezone])
    end

    it 'agenda pausada: o responsável pausou Meus horários (a página segue no ar e recebendo convite)' do
      Crm::AgentAvailability.create!(account: account, user: world.host, paused: true)

      mesmo_estado_da_ia!('agenda_pausada')
      expect(summary[:recebe]).to eq(modo: 'fixo', nome: world.host.available_name)
      expect(Crm::BookingV2::InvitePages.new(account).usable?(profile.reload)).to be(true)
    end

    it 'pausada' do
      profile.update!(enabled: false)

      mesmo_estado_da_ia!('pausada')
      expect(summary[:recebe]).to eq(modo: 'fixo', nome: world.host.available_name)
    end

    it 'sem responsável: quem atendia saiu da conta' do
      AccountUser.find_by(account: account, user: world.host).destroy!

      mesmo_estado_da_ia!('sem_responsavel')
      expect(summary[:recebe]).to eq(modo: 'fixo', nome: nil)
    end
  end

  describe 'um link por pessoa' do
    let(:colega) { create(:user, account: account, role: :agent, name: 'Rui Prado') }

    before { profile.update!(assignment_mode: :per_agent, default_assignee: nil) }

    it 'recebe o primeiro link ativo de quem pode atender (o mesmo da IA sem ninguém atribuído)' do
      desligado = profile.agent_booking_links.create!(account: account, agent: world.host)
      desligado.update!(enabled: false)
      profile.agent_booking_links.create!(account: account, agent: colega)

      mesmo_estado_da_ia!('ativa')
      expect(summary[:recebe]).to eq(modo: 'por_pessoa', nome: colega.available_name)
      expect(Crm::BookingV2::InvitePages.new(account).link_for(profile.reload, nil).agent).to eq(colega)
    end

    it 'pula quem pausou a agenda; todos pausados: agenda pausada' do
      profile.agent_booking_links.create!(account: account, agent: world.host)
      profile.agent_booking_links.create!(account: account, agent: colega)
      Crm::AgentAvailability.create!(account: account, user: world.host, paused: true)

      mesmo_estado_da_ia!('ativa')
      expect(summary[:recebe]).to eq(modo: 'por_pessoa', nome: colega.available_name)

      Crm::AgentAvailability.create!(account: account, user: colega, paused: true)
      mesmo_estado_da_ia!('agenda_pausada')
    end

    # A ordem dos links é a da associação (por id): a lista e a IA, em consultas diferentes, chegam à mesma pessoa.
    it 'a tela e a IA sem ninguém atribuído escolhem a mesma pessoa' do
      terceiro = create(:user, account: account, role: :agent, name: 'Lia Souza')
      [terceiro, colega, world.host].each { |user| profile.agent_booking_links.create!(account: account, agent: user) }
      conversa = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: world.contact, assignee: nil)
      entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil, origin_message_id: 1)
      ferramenta = Autonomia::Agents::Tools::Native::HorariosDisponiveis.new(agent: agent, params: {}, delivery: entrega)

      lista = Crm::BookingV2::InvitePages.new(account)
      Crm::AgentBookingProfile.where(id: profile.id).includes(agent_booking_links: :agent).each do |pagina|
        expect(described_class.new(pagina, invite_pages: lista).summary[:recebe][:nome]).to eq(terceiro.available_name)
      end
      expect(ferramenta.send(:pessoas).atendem.map(&:user)).to eq([terceiro, colega, world.host])
      expect(summary[:pessoas].pluck(:id)).to eq([terceiro, colega, world.host].map(&:id))
    end

    it 'sem nenhum link de quem possa atender: sem responsável' do
      profile.agent_booking_links.create!(account: account, agent: colega)
      AccountUser.find_by(account: account, user: colega).destroy!

      mesmo_estado_da_ia!('sem_responsavel')
      expect(summary[:recebe]).to eq(modo: 'por_pessoa', nome: nil)
    end
  end

  # #1307: as pessoas que a gaveta oferece para liberar, só nome de exibição e estado, na ordem fixa.
  describe 'pessoas' do
    it 'responsável único: uma pessoa, sem e-mail nem telefone' do
      world.host.update!(display_name: 'Cami')

      expect(summary[:pessoas]).to eq([{ id: world.host.id, nome: 'Cami', ai_status: 'ativa' }])
    end

    it 'um link por pessoa: os links ativos de quem pode atender, na ordem dos links, com quem pausou marcado' do
      colega = create(:user, account: account, role: :agent, name: 'Rui Prado')
      saiu = create(:user, account: account, role: :agent)
      profile.update!(assignment_mode: :per_agent, default_assignee: nil)
      [colega, world.host, saiu].each { |user| profile.agent_booking_links.create!(account: account, agent: user) }
      AccountUser.find_by(account: account, user: saiu).destroy!
      Crm::AgentAvailability.create!(account: account, user: world.host, paused: true)

      expect(summary[:pessoas]).to eq([
                                        { id: colega.id, nome: colega.available_name, ai_status: 'ativa' },
                                        { id: world.host.id, nome: world.host.available_name, ai_status: 'agenda_pausada' }
                                      ])
      expect(summary[:pessoas].flat_map(&:keys).uniq).to eq(%i[id nome ai_status])
    end

    it 'sem N+1: as mesmas consultas para 1 e para 4 páginas' do
      outros = Array.new(3) { create(:user, account: account, role: :agent) }
      paginas = Array.new(4) do
        create_booking_profile(account: account, host: world.host, pipeline: world.pipeline, stage: world.stage).tap do |pagina|
          pagina.update!(assignment_mode: :per_agent, default_assignee: nil)
          outros.each { |user| pagina.agent_booking_links.create!(account: account, agent: user) }
        end
      end

      consultas = lambda do |ids|
        lista = Crm::AgentBookingProfile.where(id: ids).includes(:default_assignee, agent_booking_links: :agent).order(:id).to_a
        invite_pages = Crm::BookingV2::InvitePages.new(account)
        contadas = 0
        contar = ->(*, payload) { contadas += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
        ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') do
          lista.each { |page| described_class.new(page, invite_pages: invite_pages).send(:pessoas) }
        end
        contadas
      end

      expect(consultas.call(paginas.first(1).map(&:id))).to eq(consultas.call(paginas.map(&:id)))
    end
  end

  it 'na lista, a elegibilidade sai numa consulta só, com uma ou com várias páginas' do
    paginas = Array.new(3) { create_booking_profile(account: account, host: world.host, pipeline: world.pipeline, stage: world.stage) }

    consultas = lambda do |lista|
      invite_pages = Crm::BookingV2::InvitePages.new(account)
      contadas = []
      contar = ->(*, payload) { contadas << payload[:sql] if payload[:sql].include?('"account_users"') }
      ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') do
        lista.each { |page| described_class.new(page, upcoming_meetings_count: 0, paused_user_ids: Set.new, invite_pages: invite_pages).summary }
      end
      contadas.size
    end

    expect(consultas.call(paginas.first(1))).to eq(1)
    expect(consultas.call(paginas)).to eq(1)
  end
end
