require 'rails_helper'

# Motivo da recusa no log (#2341): o código 100 puro é "parâmetro inválido" para qualquer campo. O que diz qual campo
# vem no subcódigo, no título e na mensagem para a pessoa e no fbtrace_id, que a Meta pede para achar a chamada.
RSpec.describe Meta::AdsGraphClient::Recusa do
  let(:token) { 'token-de-teste-que-nunca-aparece' }
  let(:client) { Meta::AdsGraphClient.new(access_token: token, api_version: 'v23.0') }
  let(:url) { 'https://graph.facebook.com/v23.0/act_123/adsets' }
  let(:logged) { [] }

  before { allow(Rails.logger).to receive(:warn) { |text| logged << text } }

  def recusa(error)
    stub_request(:post, url).to_return(status: 400, headers: { 'Content-Type' => 'application/json' }, body: { error: error }.to_json)
    client.create_adset('123', name: 'Teste')
  end

  def linha
    logged.find { |text| text.start_with?('[MetaAdsGraph]') }
  end

  it 'guarda subcódigo, título, mensagem para a pessoa e fbtrace no log e no resultado' do
    result = recusa(code: 100, error_subcode: 1_885_183, message: 'Invalid parameter', fbtrace_id: 'AxYz12_ab-CD',
                    error_user_title: 'Número do WhatsApp inválido', error_user_msg: 'O número não está ligado à Página.')

    expect(result).to have_attributes(ok: false, error_code: 100, error_subcode: 1_885_183, fbtrace_id: 'AxYz12_ab-CD',
                                      error_user_title: 'Número do WhatsApp inválido',
                                      error_user_msg: 'O número não está ligado à Página.')
    expect(linha).to eq('[MetaAdsGraph] POST act_123/adsets http=400 code=100 message=Invalid parameter subcode=1885183 ' \
                        'fbtrace=AxYz12_ab-CD user_title="Número do WhatsApp inválido" ' \
                        'user_msg="O número não está ligado à Página."')
  end

  it 'sem esses campos, a linha fica como antes' do
    recusa(code: 100, message: 'Invalid parameter')

    expect(linha).to eq('[MetaAdsGraph] POST act_123/adsets http=400 code=100 message=Invalid parameter')
  end

  it 'limpa trecho com cara de segredo do título e da mensagem para a pessoa' do
    segredo = "EAAB#{'x' * 40}"
    result = recusa(code: 100, message: 'Invalid parameter', error_user_title: "Chave #{segredo}",
                    error_user_msg: "Token #{segredo} recusado")

    expect(result.error_user_title).to eq('Chave <REDACTED>')
    expect(result.error_user_msg).to eq('Token <REDACTED> recusado')
    expect(linha).not_to include(segredo)
  end

  it 'texto da Meta com aspas ou quebra de linha fica numa linha só, sem imitar outro campo' do
    recusa(code: 100, message: 'Invalid parameter', error_user_msg: "Campo \"x\" inválido\nsubcode=1")

    expect(linha).to end_with(%(user_msg="Campo 'x' inválido subcode=1"))
    expect(linha).not_to include("\n")
  end

  it 'fbtrace fora do formato curto de letras, números, _ e - sai como <REDACTED>' do
    longo = recusa(code: 100, message: 'Invalid parameter', fbtrace_id: 'A' * 33)
    estranho = recusa(code: 100, message: 'Invalid parameter', fbtrace_id: 'abc def')

    expect([longo.fbtrace_id, estranho.fbtrace_id]).to eq(%w[<REDACTED> <REDACTED>])
  end

  it 'o token nunca entra no log' do
    recusa(code: 100, message: 'Invalid parameter', error_user_msg: 'Falhou', fbtrace_id: 'Ab1')

    expect(logged.join).not_to include(token)
  end
end
