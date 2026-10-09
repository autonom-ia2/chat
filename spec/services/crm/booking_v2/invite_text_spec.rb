require 'rails_helper'

# Texto pronto do convite (#1190, J1-A12): texto da página ou padrão do idioma da conta, `{nome}` e `{link}`
# trocados como texto literal.
RSpec.describe Crm::BookingV2::InviteText do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:invite) { create_booking_invite(world: world) }

  around { |example| with_modified_env('FRONTEND_URL' => 'https://app.example.com') { example.run } }

  it 'uses the default text in the account language with the first name and the link' do
    expect(described_class.new(invite).to_s)
      .to eq("Oi, Marcos! Escolha o melhor horário para a gente conversar: https://app.example.com/b/#{invite.code}")
  end

  it 'uses the English default for an English account' do
    account.update!(locale: 'en')

    expect(described_class.new(invite.reload).to_s).to eq("Hi, Marcos! Pick the best time for us to talk: #{invite.url}")
  end

  it 'uses the page text, replacing every {nome} and {link}' do
    world.profile.update!(invite_text: '{nome}, seu link: {link} (de novo: {link}) — {nome}')

    expect(described_class.new(invite.reload).to_s).to eq("Marcos, seu link: #{invite.url} (de novo: #{invite.url}) — Marcos")
  end

  it 'keeps the name literal: regex metacharacters and backreferences are not interpreted' do
    world.contact.update!(name: '\\0 .* $1')
    world.profile.update!(invite_text: 'Oi {nome}! [{link}] {nome}')

    expect(described_class.new(invite.reload).to_s).to eq("Oi \\0! [#{invite.url}] \\0")
  end

  it 'falls back to the text without name when the contact has no name or only a phone number as name' do
    ['', '+55 11 91234-5678'].each do |name|
      world.contact.update_columns(name: name) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.new(invite.reload).to_s).to eq("Oi! Escolha o melhor horário para a gente conversar: #{invite.url}")
    end
  end

  it 'does not use regular expressions to fill the text' do
    source = Rails.root.join('app/services/crm/booking_v2/invite_text.rb').read

    expect(source).not_to include('Regexp')
    expect(source).not_to include('gsub(/')
  end
end
