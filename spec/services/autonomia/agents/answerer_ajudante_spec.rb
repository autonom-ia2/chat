require 'rails_helper'

# Tema 14 (#1434): o principal consulta o ajudante pela função `consultar_<slug>`, com dois tetos simples por resposta
# (consultas e prazo). Passou do teto, a consulta não roda e o modelo lê "responda com o que tem".
RSpec.describe Autonomia::Agents::Answerer do
  let(:conta) { conta_da_fase2 }
  let(:joana) { criar_principal(conta) }
  let(:ajudante) { criar_ajudante(conta) }
  let(:resposta_final) do
    { reply: 'A franquia do Auto é 5% da FIPE.', confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  # O principal: chama `chamadas` (todas numa rodada) e responde. Devolve o que ele recebeu.
  def principal(chamadas: nil)
    capturado = { tools: nil, saidas: nil, kwargs: nil }
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential'))
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      capturado[:kwargs] = kwargs
      capturado[:tools] = Array(kwargs[:tools]).filter_map { |t| t[:name] }
      capturado[:saidas] = executor.call(chamadas) if chamadas
      { text: resposta_final }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    capturado
  end

  def chamada(vinculo, id = 'c1')
    { 'name' => vinculo.function_name, 'call_id' => id, 'arguments' => { 'pedido' => 'franquia do Auto?' }.to_json }
  end

  def responder(**extras)
    described_class.new(agent: joana, query: 'qual a franquia?', trust_instruction: true, **extras).answer
  end

  def runner_que_responde(texto = 'A franquia é 5% da FIPE.')
    runner = instance_double(Autonomia::Agents::Specialists::Runner,
                             call: texto, motivo: nil, rodadas_usadas: 1, base_falhou?: false)
    allow(Autonomia::Agents::Specialists::Runner).to receive(:new).and_return(runner)
    runner
  end

  it 'oferece o ajudante ao principal como função, com o "quando chamar"' do
    vinculo = vincular(joana, ajudante)
    capturado = principal

    responder

    expect(capturado[:tools]).to include(vinculo.function_name)
  end

  it 'não oferece com a Fase 2 desligada: o catálogo fica igual ao de hoje' do
    vincular(joana, ajudante)
    conta.update!(internal_attributes: conta.internal_attributes.merge('autonomia_agents_fase2' => false))
    capturado = principal

    responder

    expect(capturado[:tools]).to be_empty
  end

  it 'não oferece ajudante parado' do
    vincular(joana, ajudante)
    ajudante.update_columns(enabled: false) # rubocop:disable Rails/SkipsModelValidations
    capturado = principal

    responder

    expect(capturado[:tools]).to be_empty
  end

  it 'as ferramentas do principal continuam com ele, mesmo com o mesmo slug no ajudante' do
    [joana, ajudante].each do |agente|
      Autonomia::Agents::Tool.create!(account: conta, agent: agente, name: 'Agenda', slug: 'ver_agenda',
                                      endpoint_url: 'https://adapters.example.com/agenda', param_schema: [])
    end
    vincular(joana, ajudante)
    capturado = principal

    responder

    expect(capturado[:tools]).to include('ver_agenda')
  end

  it 'a consulta passa pelo Runner com o vínculo e devolve a resposta cercada ao principal' do
    vinculo = vincular(joana, ajudante)
    runner_que_responde
    capturado = principal(chamadas: [chamada(vinculo)])

    responder

    expect(Autonomia::Agents::Specialists::Runner).to have_received(:new)
      .with(hash_including(specialist: vinculo, request: 'franquia do Auto?'))
    expect(capturado[:saidas].first[:output]).to include('RESPOSTA DO AJUDANTE', 'A franquia é 5% da FIPE.')
    expect(Autonomia::Agents::AgentEvent.where(autonomia_agent_id: ajudante.id, event_type: :consulted).count).to eq(1)
  end

  describe 'limites por resposta' do
    it 'a 7ª consulta não roda: o modelo lê "limite atingido, responda com o que tem"' do
      vinculo = vincular(joana, ajudante)
      runner_que_responde
      chamadas = (1..7).map { |n| chamada(vinculo, "c#{n}") }
      capturado = principal(chamadas: chamadas)

      result = responder

      expect(Autonomia::Agents::Specialists::Runner).to have_received(:new).exactly(6).times
      expect(capturado[:saidas].last[:output]).to eq(Autonomia::Agents::Ajudantes::LIMITE_ATINGIDO)
      expect(result.reply).to eq('A franquia do Auto é 5% da FIPE.')
      falha = Autonomia::Agents::AgentEvent.find_by!(autonomia_agent_id: ajudante.id, event_type: :consult_failed)
      expect(falha.metadata).to include('motivo' => 'limite', 'limite' => 'consultas', 'principal_id' => joana.id)
    end

    it 'passado o prazo de 15 minutos, a consulta não roda e o modelo responde com o que tem' do
      vinculo = vincular(joana, ajudante)
      runner_que_responde
      agora = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      relogio = [agora, agora + 901]
      allow(Autonomia::Agents::Ajudantes::Orcamento).to receive(:agora) { relogio.shift || (agora + 901) }
      capturado = principal(chamadas: [chamada(vinculo)])

      responder

      expect(Autonomia::Agents::Specialists::Runner).not_to have_received(:new)
      expect(capturado[:saidas].first[:output]).to eq(Autonomia::Agents::Ajudantes::LIMITE_ATINGIDO)
      falha = Autonomia::Agents::AgentEvent.find_by!(autonomia_agent_id: ajudante.id, event_type: :consult_failed)
      expect(falha.metadata).to include('limite' => 'prazo')
    end

    it 'a consulta que começa perto do fim da resposta recebe só o tempo que resta (nunca mais que 5 min)' do
      vinculo = vincular(joana, ajudante)
      runner_que_responde
      agora = 1_000.0
      relogio = [agora, agora + 10, agora + 10, agora + 860, agora + 860]
      allow(Autonomia::Agents::Ajudantes::Orcamento).to receive(:agora) { relogio.shift || (agora + 860) }
      principal(chamadas: [chamada(vinculo, 'c1'), chamada(vinculo, 'c2')])

      responder

      expect(Autonomia::Agents::Specialists::Runner).to have_received(:new).with(hash_including(prazo: 300)).ordered
      expect(Autonomia::Agents::Specialists::Runner).to have_received(:new).with(hash_including(prazo: 40)).ordered
    end

    it 'o limite é recusa, não dado de sistema (o portão do #1361 não o toma por base)' do
      vinculo = vincular(joana, ajudante)
      runner_que_responde
      principal(chamadas: (1..7).map { |n| chamada(vinculo, "c#{n}") })

      expect { responder }.to change(Autonomia::Agents::Tools::Recusa, :registradas).by(1)
    end
  end
end
