require 'rails_helper'

RSpec.describe Crm::AgentBookingProfile, type: :model do
  let(:account) { create(:account) }
  let(:host) { create(:user, account: account, role: :agent) }

  def build_profile(**attrs)
    account.crm_agent_booking_profiles.new(
      { page_version: described_class::NEW_PAGE, default_assignee: host, enabled: true }.merge(attrs)
    )
  end

  describe 'página nova (page_version 2)' do
    it 'funciona sem caixa de e-mail' do
      expect(build_profile).to be_valid
    end

    it 'calcula as durações oferecidas, sem repetir e em ordem' do
      profile = build_profile(duration_minutes: 30, slot_durations: [60, 30, 15])

      expect(profile.durations).to eq([15, 30, 60])
    end

    it 'aceita só locais conhecidos' do
      expect(build_profile(locations: [{ 'type' => 'in_person', 'address' => 'Rua A, 10' }])).to be_valid
      expect(build_profile(locations: [{ 'type' => 'telepatia' }])).not_to be_valid
    end

    it 'exige http ou https no link do agente e recusa javascript:' do
      ok = build_profile(locations: [{ 'type' => 'custom_link', 'url' => 'https://meet.example.com/x' }])
      bad = build_profile(locations: [{ 'type' => 'custom_link', 'url' => 'javascript:alert(1)' }])

      expect(ok).to be_valid
      expect(bad).not_to be_valid
      expect(bad.errors[:locations]).to include('link must be an http or https URL')
    end

    it 'limita a quantidade de locais e de durações extras' do
      expect(build_profile(locations: Array.new(7) { { 'type' => 'whatsapp_video' } })).not_to be_valid
      expect(build_profile(slot_durations: [10, 15, 20, 25, 30, 35])).not_to be_valid
      expect(build_profile(slot_durations: [1])).not_to be_valid
    end

    it 'valida antecedência mínima' do
      expect(build_profile(min_notice_minutes: 120)).to be_valid
      expect(build_profile(min_notice_minutes: -1)).not_to be_valid
      expect(build_profile(min_notice_minutes: described_class::MAX_MIN_NOTICE + 1)).not_to be_valid
    end

    it 'valida também quando os ajustes chegam com chave símbolo' do
      profile = build_profile(brand: { color: 'azul' }, locations: [{ type: 'custom_link', url: 'javascript:alert(1)' }])

      expect(profile).not_to be_valid
      expect(profile.errors[:brand]).to include('invalid color')
      expect(profile.errors[:locations]).to include('link must be an http or https URL')
    end

    it 'valida a cor da marca como #RRGGBB' do
      expect(build_profile(brand: { 'color' => '#0D2344' })).to be_valid
      expect(build_profile(brand: { 'color' => 'azul' })).not_to be_valid
      expect(build_profile(brand: { 'color' => '#GGGGGG' })).not_to be_valid
      expect(build_profile(brand: { 'color' => 'red;background:url(x)' })).not_to be_valid
    end

    it 'valida o telefone de contato como E.164' do
      expect(build_profile(contact_phone: '+5511912345678')).to be_valid
      expect(build_profile(contact_phone: '1191234')).not_to be_valid
    end

    it 'não é enxergada pela gaveta antiga' do
      new_page = build_profile.tap(&:save!)

      expect(described_class.legacy_pages).not_to include(new_page)
      expect(described_class.new_pages).to include(new_page)
    end

    it 'recusa logo e foto que não sejam imagem comum ou passem do tamanho' do
      profile = build_profile.tap(&:save!)

      profile.logo.attach(io: StringIO.new('<svg onload=alert(1)/>'), filename: 'logo.svg', content_type: 'image/svg+xml')
      expect(profile).not_to be_valid
      expect(profile.errors[:logo]).to be_present

      profile.logo.detach
      profile.photo.attach(io: StringIO.new('x' * (described_class::MAX_IMAGE_BYTES + 1)), filename: 'p.png', content_type: 'image/png')
      expect(profile).not_to be_valid
    end
  end

  describe 'página antiga (page_version 1)' do
    it 'continua exigindo caixa de e-mail' do
      profile = account.crm_agent_booking_profiles.new(default_assignee: host, enabled: true)

      expect(profile).not_to be_valid
      expect(profile.errors[:inbox]).to be_present
    end
  end
end
