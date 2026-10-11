require 'rails_helper'

# Link curto (#1282): `/a/<nome>` vira o slug opaco da página; `/a/<nome>/<pessoa>`, o do link da pessoa. O apelido
# da pessoa é curto, único dentro da página e não muda quando a pessoa troca de nome.
RSpec.describe Crm::BookingV2::ShortLink do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account, host_name: 'Ana Souza') }
  let(:profile) { world.profile }
  let(:second) { create(:user, account: account, role: :agent, name: 'Ana Lima') }
  let(:third) { create(:user, account: account, role: :agent, name: 'João Pedro') }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://chat.exemplo.com') do
      example.run
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
  end

  def per_agent!(*users)
    Crm::BookingV2::PagePeople.new(profile).assign!(users.map(&:id))
    Crm::BookingV2::PersonNames.new(profile).assign_missing!
    profile.reload
  end

  def link_of(user)
    profile.agent_booking_links.find_by(agent_id: user.id)
  end

  describe '.resolve' do
    before { profile.update!(short_name: 'clinica-viva') }

    it 'troca o nome pelo slug da página, sem ligar para maiúsculas' do
      expect(described_class.resolve('clinica-viva')).to eq(profile.slug)
      expect(described_class.resolve('Clinica-Viva')).to eq(profile.slug)
    end

    it 'não acha nome desconhecido, vazio, mal formado ou do sistema' do
      [nil, '', 'outra-clinica', 'ab', 'clinica viva', 'admin', profile.slug].each do |name|
        expect(described_class.resolve(name)).to be_nil, name.inspect
      end
    end

    it 'não acha a página com a flag da conta desligada' do
      account.disable_features('crm_booking_v2')
      account.save!

      expect(described_class.resolve('clinica-viva')).to be_nil
    end

    it 'troca nome e pessoa pelo slug do link da pessoa' do
      per_agent!(world.host, second, third)

      expect(described_class.resolve('clinica-viva', 'ana')).to eq(link_of(world.host).slug)
      expect(described_class.resolve('clinica-viva', 'ana-2')).to eq(link_of(second).slug)
      expect(described_class.resolve('clinica-viva', 'JOAO')).to eq(link_of(third).slug)
      expect(described_class.resolve('clinica-viva', 'maria')).to be_nil
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
    it 'usa o link curto quando a página tem nome e o comprido quando não tem' do
      expect(described_class.url_for(profile)).to eq("https://chat.exemplo.com/book/#{profile.slug}")

      profile.update!(short_name: 'clinica-viva')
      expect(described_class.url_for(profile)).to eq('https://chat.exemplo.com/a/clinica-viva')
    end

    it 'usa o link curto da pessoa, e o comprido para a pessoa ainda sem apelido' do
      per_agent!(world.host, second)
      profile.update!(short_name: 'clinica-viva')
      expect(described_class.url_for(profile, link: link_of(second))).to eq('https://chat.exemplo.com/a/clinica-viva/ana-2')

      link_of(second).update_column(:metadata, {}) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.url_for(profile, link: link_of(second))).to eq("https://chat.exemplo.com/book/#{link_of(second).slug}")
    end

    it 'dá apelido a quem já atendia quando a página ganha o nome curto, mesmo com link que hoje não passaria na validação' do
      Crm::BookingV2::PagePeople.new(profile).assign!([world.host.id, second.id])
      profile.agent_booking_links.find_each { |link| link.update_column(:metadata, {}) } # rubocop:disable Rails/SkipsModelValidations
      second.account_users.find_by(account: account).destroy!

      profile.update!(short_name: 'clinica-viva')

      expect([world.host, second].map { |user| Crm::BookingV2::PersonNames.for(link_of(user)) }).to eq(%w[ana ana-2])
    end
  end
end
