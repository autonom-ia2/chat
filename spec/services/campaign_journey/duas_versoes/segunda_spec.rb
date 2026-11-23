require 'rails_helper'

# #3099: a versão 2 de cada canal. WhatsApp Oficial (D3): só outro modelo aprovado que pede as mesmas informações;
# e-mail (D2): só o assunto.
RSpec.describe CampaignJourney::DuasVersoes::Segunda, :aggregate_failures do
  def modelo(nome, corpo, status: 'APPROVED', language: 'pt_BR')
    { 'name' => nome, 'status' => status, 'language' => language, 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => corpo }] }
  end

  let(:primeiro) { modelo('renovacao', 'Olá {{1}}, sua apólice vence em {{2}}.') }
  let(:mesmas) { modelo('renovacao_curta', 'Oi {{1}}! Vence {{2}}.') }
  let(:outras) { modelo('renovacao_cupom', 'Oi {{1}}!') }
  let(:pendente) { modelo('renovacao_nova', 'Oi {{1}}, vence {{2}}.', status: 'PENDING') }
  let(:modelos) { [primeiro, mesmas, outras, pendente] }

  def whatsapp(nome, language = 'pt_BR')
    described_class.whatsapp_cloud({ 'template_name' => nome, 'template_language' => language }, modelos: modelos, primeiro: primeiro)
  end

  def recusa(code)
    raise_error(CampaignJourney::DuasVersoes::Invalida) { |erro| expect(erro.code).to eq(code) }
  end

  it 'aceita outro modelo aprovado com as mesmas informações e guarda o corpo dele' do
    expect(whatsapp('renovacao_curta')).to eq('template_name' => 'renovacao_curta', 'template_language' => 'pt_BR',
                                              'message' => 'Oi {{1}}! Vence {{2}}.')
  end

  it 'recusa o mesmo modelo, um que pede outras informações, um não aprovado e a escolha vazia' do
    expect { whatsapp('renovacao') }.to recusa('segunda_versao_igual')
    expect { whatsapp('renovacao_cupom') }.to recusa('segunda_versao_outras_informacoes')
    expect { whatsapp('renovacao_nova') }.to recusa('segunda_versao_modelo_nao_aprovado')
    expect { whatsapp('') }.to recusa('segunda_versao_vazia')
  end

  it 'no e-mail muda só o assunto, diferente do da versão 1 e dentro do tamanho' do
    expect(described_class.email({ 'subject' => ' Só hoje ' }, primeiro: 'Oferta')).to eq('subject' => 'Só hoje')
    expect { described_class.email({ 'subject' => 'Oferta' }, primeiro: 'Oferta ') }.to recusa('segunda_versao_igual')
    expect { described_class.email({ 'subject' => 'a' * 251 }, primeiro: 'Oferta') }.to recusa('segunda_versao_longa')
  end
end
