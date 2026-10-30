require 'rails_helper'

# #1426 (tema 4b, termo t4d) — o autoteste: no máximo 10 perguntas (8 do material + 2 de fora), o agente responde como
# no Testar sem ferramenta (modo prova), o juiz dá o veredito, e a rodada guarda pergunta, resposta e veredito.
# Teto de custo por rodada com contagem real: para ANTES de passar. O gerador, o agente e o juiz são dublados aqui.
RSpec.describe Autonomia::Agents::Material::Autoteste do
  include_context 'with material do agente'

  let!(:cardapio) { material('cardapio.pdf', trechos: ['X-Burger R$ 25.']) }
  let(:gerador) { instance_double(Autonomia::Agents::Material::PerguntasDoAutoteste) }
  let(:juiz) { instance_double(Autonomia::Agents::Material::JuizDoAutoteste) }
  let(:perguntados) { [] }
  let(:do_material) do
    Array.new(8) { |i| { 'pergunta' => "Pergunta #{i}?", 'esperado' => "Resposta #{i}", 'fonte' => cardapio.id } }
  end
  let(:de_fora) { [{ 'pergunta' => 'Vende bolo de casamento?' }, { 'pergunta' => 'Qual a senha do Wi-Fi?' }] }

  before do
    allow(Autonomia::Agents::Material::PerguntasDoAutoteste).to receive(:new).and_return(gerador)
    allow(gerador).to receive(:gerar).and_return(material: do_material, fora: de_fora)
    allow(Autonomia::Agents::Material::JuizDoAutoteste).to receive(:new).and_return(juiz)
    allow(juiz).to receive(:julgar) { |itens| itens.map { |item| item['origem'] == 'fora' ? 'recusou' : 'certo' } }
    agente_responde
  end

  def agente_responde(resultado = nil)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      perguntados << kwargs
      instance_double(Autonomia::Agents::Answerer, answer: resultado || resposta('O X-Burger custa R$ 25.'))
    end
  end

  def resposta(texto, handoff: false, error: nil)
    Autonomia::Agents::AnswerResult.new(
      reply: texto, confidence: 0.9, handoff: { should: handoff, reason: nil }, error: error,
      used_knowledge: [{ id: 77, content: 'X-Burger R$ 25.', source: 'cardapio.pdf' }]
    )
  end

  def estado
    agent.reload.config['autoteste']
  end

  def pedir_e_rodar(medidor: Autonomia::Agents::Material::MedidorDeCusto.new)
    described_class.pedir!(agent, quando: 'pedido')
    described_class.new(agent, estado['rodada'], medidor: medidor).rodar!
  end

  it 'o job que começa atrasado na fila (mais que a validade da rodada) ainda roda: o prazo conta do começo' do
    described_class.pedir!(agent, quando: 'pedido')

    travel(20.minutes) { described_class.new(agent, estado['rodada']).rodar! }

    expect(estado['estado']).to eq('pronto')
  end

  it 'pedir! começa a rodada e enfileira o job; com uma rodada viva, não abre outra', :aggregate_failures do
    expect { described_class.pedir!(agent, quando: 'pedido') }.to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
    expect(estado).to include('estado' => 'rodando', 'quando' => 'pedido', 'feitas' => 0)

    expect { described_class.pedir!(agent, quando: 'pedido') }.not_to have_enqueued_job
  end

  it 'rodada que morreu (rodando além da validade) libera um pedido novo' do
    described_class.pedir!(agent, quando: 'pedido')
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', estado.merge('desde' => 1.hour.ago.iso8601))

    travel(3.minutes) do
      expect { described_class.pedir!(agent, quando: 'pedido') }.to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
    end
  end

  it 'roda 10 perguntas (8 + 2) e guarda pergunta, resposta e veredito', :aggregate_failures do
    pedir_e_rodar

    expect(estado).to include('estado' => 'pronto', 'feitas' => 10, 'total' => 10, 'rodada_dos_itens' => estado['rodada'])
    itens = estado['itens']
    expect(itens.size).to eq(10)
    expect(itens.count { |item| item['origem'] == 'material' }).to eq(8)
    expect(itens.count { |item| item['origem'] == 'fora' }).to eq(2)
    expect(itens.first).to include('pergunta' => 'Pergunta 0?', 'esperado' => 'Resposta 0', 'resposta' => 'O X-Burger custa R$ 25.',
                                   'veredito' => 'certo', 'equipe' => false)
    expect(itens.last['veredito']).to eq('recusou')
  end

  it 'o agente responde em modo prova (sem ferramenta), com o rótulo de custo do autoteste' do
    pedir_e_rodar

    expect(perguntados.size).to eq(10)
    expect(perguntados).to all(include(prova: true, trust_instruction: true, feature: 'agente_autoteste_resposta', agent: agent))
  end

  # Tema 6 (D6): a exceção da Lia mora num lugar só (Playground.como_no_atendimento?); o autoteste segue o que ele diz.
  it 'agente fora do motor do atendimento (a Lia) responde com o portão' do
    allow(Autonomia::Agents::Playground).to receive(:como_no_atendimento?).with(agent).and_return(false)

    pedir_e_rodar

    expect(perguntados).to all(include(trust_instruction: false))
  end

  it 'nunca mais de 10, mesmo que o gerador mande mais' do
    allow(gerador).to receive(:gerar).and_return(material: do_material.first(8), fora: de_fora)

    pedir_e_rodar

    expect(estado['itens'].size).to be <= 10
  end

  it 'para ANTES de passar do teto: não chama o que não cabe e guarda o gasto', :aggregate_failures do
    medidor = Autonomia::Agents::Material::MedidorDeCusto.new(teto: 0.5)

    pedir_e_rodar(medidor: medidor)

    # perguntas (estimativa 0,15) + 3 respostas (0,10 cada) = 0,45; a 4ª passaria de 0,5
    expect(perguntados.size).to eq(3)
    expect(estado).to include('estado' => 'parado', 'motivo' => 'teto', 'feitas' => 3)
    expect(estado['gasto_usd']).to be <= 0.5
    expect(juiz).not_to have_received(:julgar)
  end

  it 'conta o custo real das chamadas (aviso crm.ai_usage)' do
    agente_responde
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**_kwargs|
      ActiveSupport::Notifications.instrument(Crm::Ai::UsageRecorder::EVENT_NAME, cost: 0.01)
      instance_double(Autonomia::Agents::Answerer, answer: resposta('Custa R$ 25.'))
    end

    pedir_e_rodar

    # perguntas e juiz sem aviso (estimativa 0,15 + 0,03) + 10 respostas reais de 0,01
    expect(estado['gasto_usd']).to be_within(0.0001).of(0.28)
  end

  it 'a parada no meio NÃO apaga o resultado anterior' do
    pedir_e_rodar
    anterior = estado['itens']
    agente_responde(resposta(nil, error: 'ai_unavailable'))

    travel(3.minutes) { pedir_e_rodar }

    expect(estado).to include('estado' => 'parado', 'motivo' => 'indisponivel', 'itens' => anterior)
  end

  it 'gerador ou juiz indisponível: parado, sem veredito inventado', :aggregate_failures do
    allow(juiz).to receive(:julgar).and_return(nil)
    pedir_e_rodar
    expect(estado).to include('estado' => 'parado', 'motivo' => 'indisponivel')

    allow(gerador).to receive(:gerar).and_return(nil)
    travel(3.minutes) { pedir_e_rodar }
    expect(estado).to include('estado' => 'parado', 'motivo' => 'indisponivel')
  end

  it 'rodada superada (outra pedida no meio) não grava nada' do
    described_class.pedir!(agent, quando: 'pedido')
    velha = estado['rodada']
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', estado.merge('rodada' => 'nova'))

    described_class.new(agent, velha).rodar!

    expect(perguntados).to be_empty
    expect(estado['rodada']).to eq('nova')
  end

  describe '.quando_automatica' do
    it 'agora na primeira vez; nil com a mesma base; base mudada antes de 30 min: o fim dos 30 min', :aggregate_failures do
      expect(described_class.quando_automatica(agent)).to be_within(1.second).of(Time.current)

      described_class.pedir!(agent, quando: 'base_mudou')
      described_class.new(agent, estado['rodada']).rodar!
      expect(described_class.quando_automatica(agent)).to be_nil

      ultima = Time.zone.parse(estado['ultima_automatica'])
      material('horarios.pdf')
      expect(described_class.quando_automatica(agent)).to be_within(1.second).of(ultima + 30.minutes)
    end

    it 'base mudada com uma rodada viva: daqui a pouco, nunca agora' do
      described_class.pedir!(agent, quando: 'pedido')
      material('horarios.pdf')

      expect(described_class.quando_automatica(agent)).to be_within(1.second).of(described_class::ESPERA_DA_RODADA_VIVA.from_now)
    end
  end

  it 'fora da Fase 2, na Lia ou sem material aprovado: não começa', :aggregate_failures do
    cardapio.update!(review_status: 'needs_resend')
    expect(described_class.pedir!(agent, quando: 'pedido')).to be_nil

    cardapio.update!(review_status: 'accepted')
    Autonomia::Agents::Fase2.desligar!(account)
    expect(described_class.pedir!(agent.reload, quando: 'pedido')).to be_nil

    Autonomia::Agents::Fase2.ligar!(account)
    allow(agent).to receive(:instrucao_mantida?).and_return(true)
    expect(described_class.pedir!(agent, quando: 'pedido')).to be_nil
  end
end
