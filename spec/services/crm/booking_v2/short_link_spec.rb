require 'rails_helper'

# Link curto (#1282, #1299): `/a/<conta>/<página>` vira o slug opaco da página; `/a/<conta>/<página>/<pessoa>`, o do
# link da pessoa. O formato antigo (`/a/<página>`, `/a/<página>/<pessoa>`) continua abrindo enquanto o nome for de uma
# página só, e nenhum dos dois abre página de outra conta. O apelido da pessoa é curto, único dentro da página e não
# muda quando a pessoa troca de nome.
RSpec.describe Crm::BookingV2::ShortLink do
  let(:account) { create(:account, name: 'Clínica Viva') }
  let(:world) { build_booking_world(account: account, host_name: 'Ana Souza') }
  let(:profile) { world.profile }
  let(:second) { create(:user, account: account, role: :agent, name: 'Ana Lima') }
  let(:third) { create(:user, account: account, role: :agent, name: 'João Pedro') }
  let(:other_account) { create(:account, name: 'Outra Empresa') }
  let(:other_world) { build_booking_world(account: other_account, host_name: 'Ana Outra') }
  let(:other_profile) { other_world.profile }
  let(:other_second) { create(:user, account: other_account, role: :agent, name: 'Bia Outra') }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://chat.exemplo.com') do
      example.run
    end
  end

  before do
    [account, other_account].each do |item|
      item.enable_features('crm_booking_v2')
      item.save!
    end
  end

  def per_agent!(*users, page: profile)
    Crm::BookingV2::PagePeople.new(page).assign!(users.map(&:id))
    Crm::BookingV2::PersonNames.new(page).assign_missing!
    page.reload
  end

  def link_of(user, page: profile)
    page.agent_booking_links.find_by(agent_id: user.id)
  end

  def address!(of_account)
    Crm::BookingV2::AccountAddress.ensure!(of_account)
  end

  describe '.resolve no formato novo' do
    before do
      profile.update!(short_name: 'avaliacao')
      address!(account)
    end

    it 'troca conta e página pelo slug da página, sem ligar para maiúsculas' do
      expect(described_class.resolve('clinica-viva', 'avaliacao')).to eq(profile.slug)
      expect(described_class.resolve('Clinica-Viva', 'Avaliacao')).to eq(profile.slug)
    end

    it 'troca conta, página e pessoa pelo slug do link da pessoa' do
      per_agent!(world.host, second, third)

      expect(described_class.resolve('clinica-viva', 'avaliacao', 'ana')).to eq(link_of(world.host).slug)
      expect(described_class.resolve('clinica-viva', 'avaliacao', 'ana-2')).to eq(link_of(second).slug)
      expect(described_class.resolve('clinica-viva', 'avaliacao', 'JOAO')).to eq(link_of(third).slug)
      expect(described_class.resolve('clinica-viva', 'avaliacao', 'maria')).to be_nil
    end

    it 'não acha página desconhecida, mal formada ou do sistema, nem pessoa em página de um responsável só' do
      ['outra-pagina', 'ab', 'avaliacao gratis', 'admin', profile.slug].each do |name|
        expect(described_class.resolve('clinica-viva', name)).to be_nil, name.inspect
      end
      expect(described_class.resolve('clinica-viva', 'avaliacao', 'ana')).to be_nil
    end

    it 'duas contas com página de mesmo nome: cada endereço abre a página da própria conta' do
      other_profile.update!(short_name: 'avaliacao')
      address!(other_account)

      expect(described_class.resolve('clinica-viva', 'avaliacao')).to eq(profile.slug)
      expect(described_class.resolve('outra-empresa', 'avaliacao')).to eq(other_profile.slug)
    end

    it 'nunca abre com o endereço de uma conta a página de outra' do
      other_profile.update!(short_name: 'so-da-outra')
      address!(other_account)

      expect(described_class.resolve('clinica-viva', 'so-da-outra')).to be_nil
      expect(described_class.resolve('outra-empresa', 'avaliacao')).to be_nil
    end

    it 'não acha nada com a flag da conta desligada' do
      account.disable_features('crm_booking_v2')
      account.save!

      expect(described_class.resolve('clinica-viva', 'avaliacao')).to be_nil
      expect(described_class.resolve('clinica-viva')).to be_nil
    end
  end

  describe '.resolve só com o endereço da conta' do
    before do
      profile
      address!(account)
    end

    it 'abre a página da conta quando ela tem uma só no ar, mesmo sem nome curto' do
      expect(described_class.resolve('clinica-viva')).to eq(profile.slug)
    end

    it 'não conta página pausada nem página antiga' do
      paused = create_booking_profile(account: account, host: world.host, enabled: false)
      inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
      create_booking_profile(account: account, host: world.host, page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: inbox)

      expect(described_class.resolve('clinica-viva')).to eq(profile.slug)

      profile.update!(enabled: false)
      paused.update!(enabled: true)
      expect(described_class.resolve('clinica-viva')).to eq(paused.slug)
    end

    it 'não escolhe nenhuma quando a conta tem mais de uma no ar, nem quando não tem nenhuma' do
      extra = create_booking_profile(account: account, host: world.host)
      expect(described_class.resolve('clinica-viva')).to be_nil

      [profile, extra].each { |page| page.update!(enabled: false) }
      expect(described_class.resolve('clinica-viva')).to be_nil
    end
  end

  describe '.resolve no formato antigo (#1282)' do
    before { profile.update!(short_name: 'avaliacao') }

    it 'abre `/a/<página>` enquanto o nome é de uma página só na instalação' do
      expect(described_class.resolve('avaliacao')).to eq(profile.slug)
      expect(described_class.resolve('Avaliacao')).to eq(profile.slug)
    end

    it 'abre `/a/<página>/<pessoa>`' do
      per_agent!(world.host, second)

      expect(described_class.resolve('avaliacao', 'ana-2')).to eq(link_of(second).slug)
      expect(described_class.resolve('avaliacao', 'maria')).to be_nil
      expect(described_class.resolve('avaliacao', 'ana-2', 'sobra')).to be_nil
    end

    it 'para de abrir quando outra conta cria uma página com o mesmo nome: não escolhe uma das duas' do
      other_profile.update!(short_name: 'avaliacao')

      expect(described_class.resolve('avaliacao')).to be_nil
      expect(described_class.resolve('avaliacao', 'ana')).to be_nil
    end

    it 'não acha nome desconhecido, vazio, mal formado ou do sistema, nem com a flag desligada' do
      [nil, '', 'outra-clinica', 'ab', 'clinica viva', 'admin', profile.slug].each do |name|
        expect(described_class.resolve(name)).to be_nil, name.inspect
      end

      account.disable_features('crm_booking_v2')
      account.save!
      expect(described_class.resolve('avaliacao')).to be_nil
    end
  end

  describe '.resolve quando o pedaço pode ser conta ou página' do
    it 'endereço de conta igual ao nome de uma página DELA: o link antigo da página e o da pessoa continuam abrindo' do
      account.update!(name: 'Avaliação')
      profile.update!(short_name: 'avaliacao')
      expect(address!(account)).to eq('avaliacao')
      per_agent!(world.host, second)

      expect(described_class.resolve('avaliacao', 'ana-2')).to eq(link_of(second).slug)
      expect(described_class.resolve('avaliacao', 'avaliacao', 'ana-2')).to eq(link_of(second).slug)
    end

    it 'com o endereço da conta, o formato novo vem primeiro: a página chamada como a pessoa ganha do link antigo da pessoa' do
      account.update!(name: 'Avaliação')
      profile.update!(short_name: 'avaliacao')
      address!(account)
      per_agent!(world.host, second)
      named_like_person = create_booking_profile(account: account, host: world.host, short_name: 'ana-2')

      expect(described_class.resolve('avaliacao', 'ana-2')).to eq(named_like_person.slug)
    end

    it 'endereço de conta igual ao nome antigo de página de OUTRA conta não nasce: o link antigo segue da dona' do
      other_profile.update!(short_name: 'clinica-viva')
      per_agent!(other_world.host, other_second, page: other_profile)

      expect(address!(account)).to eq('clinica-viva-2')
      expect(described_class.resolve('clinica-viva')).to eq(other_profile.slug)
      expect(described_class.resolve('clinica-viva', 'ana')).to eq(link_of(other_world.host, page: other_profile).slug)
    end

    it 'página criada depois com o nome igual ao endereço de outra conta não é aberta por ele' do
      address!(account)
      other_profile.update!(short_name: 'clinica-viva')
      per_agent!(other_world.host, other_second, page: other_profile)
      profile.update!(enabled: false)

      expect(described_class.resolve('clinica-viva')).to be_nil
      expect(described_class.resolve('clinica-viva', 'ana')).to be_nil
      expect(described_class.resolve('clinica-viva', 'clinica-viva')).to be_nil

      address!(other_account)
      expect(described_class.resolve('outra-empresa', 'clinica-viva')).to eq(other_profile.slug)
    end
  end

  describe 'apelido da pessoa' do
    it 'sai do primeiro nome, sem acento, com número quando repete, e não muda depois' do
      per_agent!(world.host, second, third)
      expect([world.host, second, third].map { |user| Crm::BookingV2::PersonNames.for(link_of(user)) }).to eq(%w[ana ana-2 joao])

      world.host.update!(name: 'Mariana Souza')
      Crm::BookingV2::PersonNames.new(profile).assign_missing!
      expect(Crm::BookingV2::PersonNames.for(link_of(world.host))).to eq('ana')
    end

    it 'usa um apelido genérico quando o nome não tem letra que sirva' do
      world.host.update!(name: '日本')
      per_agent!(world.host, second)

      expect(Crm::BookingV2::PersonNames.for(link_of(world.host))).to eq('p')
    end
  end

  describe '.url_for' do
    it 'usa o link curto com a conta quando a página tem nome e o comprido quando não tem' do
      expect(described_class.url_for(profile)).to eq("https://chat.exemplo.com/book/#{profile.slug}")
      expect(Crm::BookingAccountAddress.count).to eq(0)

      profile.update!(short_name: 'avaliacao')
      expect(described_class.url_for(profile)).to eq('https://chat.exemplo.com/a/clinica-viva/avaliacao')
    end

    it 'cria o endereço da conta na primeira vez que a página com nome precisa dele' do
      profile.update!(short_name: 'avaliacao')
      expect(Crm::BookingAccountAddress.count).to eq(0)

      described_class.url_for(profile)

      expect(Crm::BookingAccountAddress.pluck(:account_id, :name)).to eq([[account.id, 'clinica-viva']])
    end

    it 'usa o link curto da pessoa, e o comprido para a pessoa ainda sem apelido' do
      per_agent!(world.host, second)
      profile.update!(short_name: 'avaliacao')
      expect(described_class.url_for(profile, link: link_of(second))).to eq('https://chat.exemplo.com/a/clinica-viva/avaliacao/ana-2')

      link_of(second).update_column(:metadata, {}) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.url_for(profile, link: link_of(second))).to eq("https://chat.exemplo.com/book/#{link_of(second).slug}")
    end

    it 'o endereço que monta é o que resolve' do
      per_agent!(world.host, second)
      profile.update!(short_name: 'avaliacao')

      segments = described_class.path_for(profile, link: link_of(second)).delete_prefix('/a/').split('/')
      expect(described_class.resolve(*segments)).to eq(link_of(second).slug)
    end

    it 'dá apelido a quem já atendia quando a página ganha o nome curto, mesmo com link que hoje não passaria na validação' do
      Crm::BookingV2::PagePeople.new(profile).assign!([world.host.id, second.id])
      profile.agent_booking_links.find_each { |link| link.update_column(:metadata, {}) } # rubocop:disable Rails/SkipsModelValidations
      second.account_users.find_by(account: account).destroy!

      profile.update!(short_name: 'avaliacao')

      expect([world.host, second].map { |user| Crm::BookingV2::PersonNames.for(link_of(user)) }).to eq(%w[ana ana-2])
    end
  end
end
