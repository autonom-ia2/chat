require 'rails_helper'

# #1755: a posição de cada bloco de memória no pedido. "Antes desta conversa" logo depois do segmento da conta (no
# prefixo do cache; sem segmento, como na Lia, é o primeiro item); o estado como `developer` depois da regra do turno;
# os fatos como `user` imediatamente antes da pergunta.
RSpec.describe Autonomia::Agents::PromptBuilder do
  let(:account) { conta_da_fase2 }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let(:memoria) do
    Autonomia::Agents::PromptParts::Memoria::Blocos.new(antes: 'ANTES', sistema: 'ESTADO', fatos: 'FATOS', ids: [1])
  end
  let(:history) { [{ role: 'user', content: 'Oi' }, { role: 'assistant', content: 'Olá!' }] }

  def textos(input)
    input.map { |item| [item[:role], item[:content].first[:text]] }
  end

  def builder(**extras)
    described_class.new(agent: agent, query: 'E a placa?', history: history, contexto_do_turno: 'REGRA', **extras)
  end

  it 'sem segmento: antes, histórico, regra do turno, estado, fatos e a pergunta, nessa ordem' do
    allow(Autonomia::Agents::PromptParts::SegmentoDaConta).to receive(:mensagem).and_return(nil)

    expect(textos(builder(memoria: memoria).input)).to eq(
      [%w[user ANTES], %w[user Oi], %w[assistant Olá!], %w[developer REGRA], %w[developer ESTADO], %w[user FATOS],
       ['user', 'E a placa?']]
    )
  end

  it 'com segmento da conta, o "antes" vem logo depois dele' do
    segmento = Autonomia::Agents::PromptParts::Mensagem.montar('user', 'SEGMENTO')
    allow(Autonomia::Agents::PromptParts::SegmentoDaConta).to receive(:mensagem).and_return(segmento)

    expect(textos(builder(memoria: memoria).input).first(2)).to eq([%w[user SEGMENTO], %w[user ANTES]])
  end

  it 'sem memória (padrão ou vazia), o input é o mesmo de antes' do
    allow(Autonomia::Agents::PromptParts::SegmentoDaConta).to receive(:mensagem).and_return(nil)
    antes = builder.input

    expect(builder(memoria: Autonomia::Agents::PromptParts::Memoria::Blocos.vazio).input).to eq(antes)
    expect(builder(memoria: nil).input).to eq(antes)
  end

  it 'só o bloco que existe entra (fatos sem antes nem estado)' do
    allow(Autonomia::Agents::PromptParts::SegmentoDaConta).to receive(:mensagem).and_return(nil)
    so_fatos = Autonomia::Agents::PromptParts::Memoria::Blocos.new(antes: nil, sistema: nil, fatos: 'FATOS', ids: [])

    expect(textos(builder(memoria: so_fatos).input).last(2)).to eq([%w[user FATOS], ['user', 'E a placa?']])
    expect(textos(builder(memoria: so_fatos).input).first).to eq(%w[user Oi])
  end
end
