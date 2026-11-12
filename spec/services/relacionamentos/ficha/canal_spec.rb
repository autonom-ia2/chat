require 'rails_helper'

# #2895 — o canal de uma caixa nas palavras da ficha de Relacionamentos: whatsapp, email, instagram, site ou outro.
RSpec.describe Relacionamentos::Ficha::Canal do
  def canal_da(caixa_do_canal)
    described_class.de(Inbox.new(channel: caixa_do_canal))
  end

  it 'WhatsApp: a caixa oficial, a do celular (WAHA) e a da Twilio no WhatsApp' do
    expect(canal_da(Channel::Whatsapp.new)).to eq('whatsapp')
    expect(canal_da(Channel::Api.new(additional_attributes: { 'provider' => 'waha' }))).to eq('whatsapp')
    expect(canal_da(Channel::TwilioSms.new(medium: :whatsapp))).to eq('whatsapp')
  end

  it 'e-mail' do
    expect(canal_da(Channel::Email.new)).to eq('email')
  end

  it 'Instagram: a caixa do Instagram e a página do Facebook com Instagram ligado' do
    expect(canal_da(Channel::Instagram.new(instagram_id: '17840000000000000'))).to eq('instagram')
    expect(canal_da(Channel::FacebookPage.new(instagram_id: '17840000000000000'))).to eq('instagram')
  end

  it 'site' do
    expect(canal_da(Channel::WebWidget.new)).to eq('site')
  end

  it 'outro: o que a ficha não tem nome para dizer' do
    [Channel::Api.new, Channel::TwilioSms.new(medium: :sms), Channel::FacebookPage.new, Channel::Telegram.new, Channel::Sms.new].each do |canal|
      expect(canal_da(canal)).to eq('outro'), canal.class.name
    end
  end
end
