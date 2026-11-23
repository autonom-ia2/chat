require 'rails_helper'

# Os gráficos da `relatorio_de_atendimento` (#3158, B8a) chegam à tela pelo `Chat::Result` e voltam ao reabrir
# a conversa pelo `Turno`.
RSpec.describe Autonomia::Guide::Chat do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:grafico) do
    { 'modo' => 'ranking', 'titulo' => 'Conversas resolvidas por pessoa', 'medida' => 'Conversas resolvidas',
      'de' => '2026-10-01', 'ate' => '2026-10-31', 'barras' => [{ 'rotulo' => 'Ana Souza', 'valor' => 128 }] }
  end

  before do
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(instance_double(Autonomia::Agents::Agent))
    allow(Autonomia::Agents::Retriever).to receive(:new).and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
  end

  # O stub do Answerer faz o papel da ferramenta: é dentro dela que o gráfico vai para o Contexto e que a saída
  # chega ao registro do turno.
  def responder(texto, saida: nil, registro: nil)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      kwargs[:operador].desenhar(grafico)
      kwargs[:operador].registrar_chamada({ 'name' => 'relatorio_de_atendimento', 'arguments' => '{}' }, saida, 10) if saida
      instance_double(Autonomia::Agents::Answerer,
                      answer: Autonomia::Agents::AnswerResult.new(reply: texto, raw_reply: texto.presence || 'retido', confidence: 1.0,
                                                                  handoff: { should: false, reason: nil }))
    end
    described_class.new(account: conta, user: admin, message: 'quem resolveu mais em outubro?', registro: registro).perform
  end

  it 'manda os gráficos do turno na resposta, com o id do marcador' do
    resultado = responder('A Ana resolveu mais. [grafico:1]')

    expect(resultado.graficos).to eq([grafico.merge('id' => '1')])
  end

  it 'manda os gráficos também na resposta retida: os números vieram da ferramenta', :aggregate_failures do
    resultado = responder('')

    expect(resultado.retido).to be(true)
    expect(resultado.graficos).to eq([grafico.merge('id' => '1')])
  end

  it 'Guia fora do ar não tem gráfico' do
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(nil)
    allow(Autonomia::Guide::Seed).to receive(:ensure_async_for).and_return(false)

    expect(described_class.new(account: conta, user: admin, message: 'oi').perform.graficos).to be_nil
  end

  describe 'o turno guardado' do
    let(:conversa) { Autonomia::Guide::Conversa.create!(account: conta, user: admin, titulo: 'Relatórios') }
    let(:turno) { Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: 'quem resolveu mais?', tela: nil) }

    it 'grava os gráficos e os devolve ao reabrir a conversa', :aggregate_failures do
      resultado = responder('A Ana resolveu mais. [grafico:1]')

      Autonomia::Guide::Turno.concluir(turno.pedido_id, resultado.to_h, { 'rodadas' => 1 })

      expect(turno.reload.para_tela['graficos']).to eq([grafico.merge('id' => '1')])
      expect(turno.diagnostico).to include('rodadas' => 1)
    end

    it 'sem gráfico, a tela recebe nil' do
      Autonomia::Guide::Turno.concluir(turno.pedido_id, { text: 'Oi.', available: true }, {})

      expect(turno.reload.para_tela['graficos']).to be_nil
    end
  end
end
