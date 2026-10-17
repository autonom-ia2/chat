require 'rails_helper'

# #1428 (tema 6, parte 2) — a conferência do ajuste: o segundo modelo, com o mesmo cliente, modelo e raciocínio do
# Construtor, e feature própria na Gestão IA. O julgamento de verdade é do eval pago.
RSpec.describe Autonomia::Agents::ConferenciaDoAjuste do
  let(:account) { create(:account) }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:conferencia) { described_class.new(account: account, credential: { api_key: 'chave-de-teste' }) }
  let(:antes) { { 'tone' => 'cordial', 'instruction' => 'Atenda.' } }
  let(:depois) { { 'tone' => 'cordial e curto', 'instruction' => 'Atenda.' } }
  let(:mudancas) { [{ 'pedido' => 'no máximo 2 frases', 'campo' => 'tone', 'resumo' => 'Curto.' }] }
  let(:saida) do
    { 'itens' => [{ 'pedido' => 'no máximo 2 frases', 'atendido' => true, 'onde' => 'tone', 'observacao' => 'Entrou.' },
                  { 'pedido' => 'preço passa para a equipe', 'atendido' => false, 'onde' => '', 'observacao' => 'Faltou.' }],
      'conflitos' => ['Pediu curto e detalhado ao mesmo tempo.'], 'pergunta' => 'Você quer dizer...?' }
  end

  before do
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:create).and_return(text: saida.to_json)
  end

  def conferir
    conferencia.conferir(pedido: 'Responda em no máximo 2 frases e preço passa para a equipe', mudancas: mudancas,
                         antes: antes, depois: depois)
  end

  it 'usa o modelo e o raciocínio do Construtor, com a feature própria da conta' do
    conferir

    expect(Crm::Ai::ResponsesClient).to have_received(:new)
      .with(credential: { api_key: 'chave-de-teste' }, feature: 'agente_builder_conferencia', account: account)
    expect(fake_client).to have_received(:create).with(
      hash_including(model: Autonomia::Agents::Config::BUILDER_MODEL, schema: described_class::SCHEMA,
                     reasoning_effort: Autonomia::Agents::Config::BUILDER_REASONING_EFFORT_FINAL,
                     instructions: described_class::INSTRUCAO)
    )
  end

  it 'manda a fala, a lista e o agente antes e depois' do
    conferir

    expect(fake_client).to have_received(:create) do |**params|
      texto = params[:input].first[:content].first[:text]
      expect(texto).to include('preço passa para a equipe', '"campo": "tone"', '"tone": "cordial"', '"tone": "cordial e curto"')
    end
  end

  it 'devolve os itens, os conflitos, a pergunta e as pendências (o que faltou e os conflitos)' do
    expect(conferir).to eq(saida.merge('pendencias' => ['preço passa para a equipe', 'Pediu curto e detalhado ao mesmo tempo.']))
  end

  it 'falha do provedor não levanta: devolve a conferência indisponível, sem pendências' do
    allow(fake_client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

    expect(conferir).to eq('erro' => 'conferencia_indisponivel', 'pendencias' => [])
  end

  it 'saída malformada também vira conferência indisponível' do
    allow(fake_client).to receive(:create).and_return(text: '[1, 2]')

    expect(conferir).to include('erro' => 'conferencia_indisponivel')
  end
end
