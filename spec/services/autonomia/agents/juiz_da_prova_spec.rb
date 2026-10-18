require 'rails_helper'

# #1428 (tema 6, parte 3, entrega B) — o juiz das perguntas de prova: só { indice, veredito } (ok, nao, nao_testa), um por
# item. Faltando item,
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

  it 'um veredito por item, na ordem dos índices, com os três estados' do
    itens << { 'pergunta' => 'Vocês atendem em Curitiba?', 'resposta' => 'Atendemos.', 'equipe' => false }
    juiz_responde([{ indice: 2, veredito: 'nao_testa' }, { indice: 1, veredito: 'nao' }, { indice: 0, veredito: 'ok' }])

    expect(julgar).to eq(%w[ok nao nao_testa])
  end

  it 'veredito fora dos três: nil' do
    juiz_responde([{ indice: 0, veredito: 'ok' }, { indice: 1, veredito: 'talvez' }])

    expect(julgar).to be_nil
  end

  it 'a instrução separa a pergunta que não toca a mudança' do
    expect(described_class::INSTRUCAO).to include('nao_testa: a mensagem nao toca nenhuma das mudancas')
    expect(described_class::SCHEMA.dig(:schema, :properties, :resultados, :items, :properties, :veredito, :enum))
      .to eq(%w[ok nao nao_testa])
  end

  it 'outro modelo, a feature da prova, schema só de índices e sem nova tentativa', :aggregate_failures do
    juiz_responde([{ indice: 0, veredito: 'ok' }, { indice: 1, veredito: 'ok' }])

    julgar

    expect(Crm::Ai::ResponsesClient).to have_received(:new)
      .with(hash_including(feature: 'agente_prova_juiz', account: account, max_retries: 0))
    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:model]).not_to eq(Autonomia::Agents::Config::ANSWERER_MODEL)
      expect(kwargs[:schema][:schema][:properties][:resultados][:items][:properties].keys).to eq(%i[indice veredito])
      expect(kwargs[:timeout]).to eq(30)
      texto = kwargs[:input].first[:content].first[:text]
      expect(texto).to include('Respostas curtas.', 'Quais seguros?', 'Auto e vida.', '"passa_para_equipe": true')
    end
  end

  it 'faltando um índice: nil' do
    juiz_responde([{ indice: 0, veredito: 'ok' }])

    expect(julgar).to be_nil
  end

  it 'índice fora da lista não preenche o que falta' do
    juiz_responde([{ indice: 0, veredito: 'ok' }, { indice: 7, veredito: 'ok' }])

    expect(julgar).to be_nil
  end

  it 'índice repetido vale o primeiro' do
    juiz_responde([{ indice: 0, veredito: 'nao' }, { indice: 0, veredito: 'ok' }, { indice: 1, veredito: 'ok' }])

    expect(julgar).to eq(%w[nao ok])
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
