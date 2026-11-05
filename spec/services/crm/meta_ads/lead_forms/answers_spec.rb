require 'rails_helper'

# O metadata do card para quem lê (#2195, #2558): as respostas só para quem vê o contato inteiro; o formulário, o
# anúncio e a campanha só para quem vê o anúncio de origem. O resto do metadata não muda.
RSpec.describe Crm::MetaAds::LeadForms::Answers do
  let(:origem) do
    { 'leadgen_id' => 'L1', 'form_id' => 'F1', 'form_name' => 'Orçamento', 'ad_id' => '1202', 'ad_name' => 'Carrossel',
      'campaign_name' => 'Primavera', 'captured_at' => '2026-11-01T12:00:00Z', 'fields' => [{ 'key' => 'city', 'value' => 'Campinas' }] }
  end
  let(:metadata) { { 'ai' => { 'score' => 3 }, 'meta_lead_form' => origem } }

  def para(contato_inteiro:, anuncio_visivel:)
    described_class.para(metadata, contato_inteiro: contato_inteiro, anuncio_visivel: anuncio_visivel)
  end

  it 'vê o contato e o anúncio: nada muda' do
    expect(para(contato_inteiro: true, anuncio_visivel: true)).to eq(metadata)
  end

  it 'vê o anúncio, não o contato inteiro: sai só as respostas' do
    expect(para(contato_inteiro: false, anuncio_visivel: true)['meta_lead_form']).to eq(origem.except('fields'))
  end

  it 'vê o contato inteiro, não o anúncio: ficam a hora e as respostas' do
    expect(para(contato_inteiro: true, anuncio_visivel: false)['meta_lead_form']).to eq(origem.slice('captured_at', 'fields'))
  end

  it 'não vê nenhum dos dois: fica só a hora; o resto do metadata segue' do
    lido = para(contato_inteiro: false, anuncio_visivel: false)

    expect(lido['meta_lead_form']).to eq('captured_at' => '2026-11-01T12:00:00Z')
    expect(lido['ai']).to eq('score' => 3)
  end

  it 'metadata sem formulário, vazio ou que não é Hash passa como está' do
    expect(described_class.para({ 'ai' => {} }, contato_inteiro: false, anuncio_visivel: false)).to eq('ai' => {})
    expect(described_class.para(nil, contato_inteiro: false, anuncio_visivel: false)).to be_nil
    expect(described_class.para('x', contato_inteiro: false, anuncio_visivel: false)).to eq('x')
  end

  it 'não altera o metadata recebido' do
    para(contato_inteiro: false, anuncio_visivel: false)

    expect(metadata['meta_lead_form']).to eq(origem)
  end
end
