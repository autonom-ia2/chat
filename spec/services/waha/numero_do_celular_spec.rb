require 'rails_helper'

# #2211 — a tela mostra por onde a mensagem sai: o número do WhatsApp do celular vem no JSON da caixa.
RSpec.describe Waha::NumeroDoCelular do
  let(:account) { create(:account) }

  it 'é a sessão WAHA com +' do
    canal = build(:channel_api, additional_attributes: { 'provider' => 'waha', 'session' => '5511999999999' })
    expect(described_class.de(canal)).to eq('+5511999999999')
  end

  it 'é nil fora do WAHA ou com sessão que não é número' do
    expect(described_class.de(build(:channel_api))).to be_nil
    expect(described_class.de(build(:channel_api, additional_attributes: { 'provider' => 'waha', 'session' => 'loja-centro' }))).to be_nil
    expect(described_class.de(build(:channel_api, additional_attributes: { 'provider' => 'waha' }))).to be_nil
  end

  describe 'no JSON da caixa', type: :request do
    it 'vem como waha_phone_number' do
      admin = create(:user, account: account, role: :administrator)
      celular = create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => '5511988887777' }).inbox
      comum = create(:channel_api, account: account).inbox
      get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token, as: :json
      caixas = response.parsed_body['payload'].index_by { |caixa| caixa['id'] }
      expect(caixas[celular.id]['waha_phone_number']).to eq('+5511988887777')
      expect(caixas[comum.id]).not_to have_key('waha_phone_number')
    end
  end
end
