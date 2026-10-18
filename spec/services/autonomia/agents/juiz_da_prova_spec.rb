require 'rails_helper'

# #1428 (tema 6, parte 3, entrega B) — o juiz das perguntas de prova: só { indice, ok }, um por item. Faltando item,
# repetido, malformado ou provedor fora: nil (a prova fica indisponível, nunca um ✓ inventado).
RSpec.describe Autonomia::Agents::JuizDaProva do
  let(:account) { create(:account) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:pedidos) { [{ 'pedido' => 'no máximo 2 frases', 'resumo' => 'Respostas curtas.' }] }
  let(:itens) do
    [{ 'pergunta' => 'Quais seguros?', 'resposta' => 'Auto e vida.', 'equipe' => false },
     { 'pergunta' => 'Quanto custa?', 'resposta' => nil, 'equipe' => true }]
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def juiz_responde(resultados)
    allow(cliente).to receive(:create).and_return(text: { resultados: resultados }.to_json)
  end

  def julgar
    described_class.new(account: account).julgar(pedidos: pedidos, itens: itens)
  end

  it 'um veredito por item, na ordem dos índices' do
    juiz_responde([{ indice: 1, ok: false }, { indice: 0, ok: true }])

    expect(julgar).to eq([true, false])
  end

  it 'outro modelo, a feature da prova, schema só de índices e sem nova tentativa', :aggregate_failures do
    juiz_responde([{ indice: 0, ok: true }, { indice: 1, ok: true }])

    julgar

    expect(Crm::Ai::ResponsesClient).to have_received(:new)
      .with(hash_including(feature: 'agente_prova_do_ajuste', account: account, max_retries: 0))
    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:model]).not_to eq(Autonomia::Agents::Config::ANSWERER_MODEL)
      expect(kwargs[:schema][:schema][:properties][:resultados][:items][:properties].keys).to eq(%i[indice ok])
      expect(kwargs[:timeout]).to eq(30)
      texto = kwargs[:input].first[:content].first[:text]
      expect(texto).to include('Respostas curtas.', 'Quais seguros?', 'Auto e vida.', '"passa_para_equipe": true')
    end
  end

  it 'faltando um índice: nil' do
    juiz_responde([{ indice: 0, ok: true }])

    expect(julgar).to be_nil
  end

  it 'índice fora da lista não preenche o que falta' do
    juiz_responde([{ indice: 0, ok: true }, { indice: 7, ok: true }])

    expect(julgar).to be_nil
  end

  it 'índice repetido vale o primeiro' do
    juiz_responde([{ indice: 0, ok: false }, { indice: 0, ok: true }, { indice: 1, ok: true }])

    expect(julgar).to eq([false, true])
  end

  it 'saída que não é objeto: nil' do
    allow(cliente).to receive(:create).and_return(text: '[]')

    expect(julgar).to be_nil
  end

  it 'provedor fora: nil' do
    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

    expect(julgar).to be_nil
  end

  it 'sem credencial: nil, sem chamar o modelo' do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))

    expect(julgar).to be_nil
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end
end
