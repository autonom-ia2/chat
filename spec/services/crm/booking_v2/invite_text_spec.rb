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
      .to eq("Oi, Marcos! Escolha o melhor horário para você: https://app.example.com/b/#{invite.code}")
  end

  # #1517: com o botão, o padrão sai sem o link cru; texto da página com {link} não leva botão.
  describe 'button (#1517)' do
    it 'default text without the raw link, and the button with the invite link' do
      text = described_class.new(invite, button: true)

      expect(text.to_s).to eq('Oi, Marcos! Escolha o melhor horário para você no botão abaixo.')
      expect(text.rich_message).to eq('type' => 'link_button', 'label' => 'Ver meu horário', 'url' => invite.url)
      expect(text.carries_link?).to be(false)
    end

    it 'page text with {link}: no button, text as is' do
      world.profile.update!(invite_text: 'Escolha aqui: {link}')
      text = described_class.new(invite.reload, button: true)

      expect(text.rich_message).to be_nil
      expect(text.to_s).to eq("Escolha aqui: #{invite.url}")
    end

    it 'page text without {link}: button' do
      world.profile.update!(invite_text: 'Escolha seu horário.')

      expect(described_class.new(invite.reload, button: true).rich_message).to include('url' => invite.url)
    end
  end

  it 'uses the English default for an English account' do
    account.update!(locale: 'en')

    expect(described_class.new(invite.reload).to_s).to eq("Hi, Marcos! Pick the best time for you: #{invite.url}")
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

      expect(described_class.new(invite.reload).to_s).to eq("Oi! Escolha o melhor horário para você: #{invite.url}")
    end
  end

  it 'does not use regular expressions to fill the text' do
    source = Rails.root.join('app/services/crm/booking_v2/invite_text.rb').read

    expect(source).not_to include('Regexp')
    expect(source).not_to include('gsub(/')
  end
end
