require 'rails_helper'

# Tema 14 (#1434), termo t14f: A LIA NÃO MUDA. O caminho do ajudante passa pelo mesmo Specialist, Runner e Answerer
# da Cotação; aqui a prova é o PEDIDO à OpenAI. Um turno da Lia (o principal e o especialista que ela consulta) manda
# exatamente o mesmo corpo com a Fase 2 desligada e com a Fase 2 ligada e um ajudante vinculado a outro agente da conta.
RSpec.describe 'A Lia com o ajudante no ar (tema 14)' do # rubocop:disable RSpec/DescribeClass
  let(:conta) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
  end
  let(:lia) { Autonomia::Insurance::QuoteAgent::Builder.new(account: conta, nome_agente: 'Lia', nome_corretora: 'X').call }
  let(:resposta_do_principal) do
    { reply: 'Vou cotar.', confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
      answered_from_knowledge: false }.to_json
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') do
      travel_to(Time.zone.parse('2026-10-14 10:00')) { example.run }
    end
  end

  # Tudo o que sai para a OpenAI no turno: os argumentos do cliente (etiqueta de consumo) e de cada chamada.
  def pedidos_do_turno
    pedidos = []
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential'))
    allow(Crm::Ai::ResponsesClient).to receive(:new) do |**kwargs_do_cliente|
      pedidos << [:cliente, kwargs_do_cliente.except(:account)]
      cliente_que_anota(pedidos)
    end
    rodadas = Autonomia::Agents::Ajudantes.rodadas(lia) || Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(lia)
    Autonomia::Agents::Answerer.new(agent: lia.reload, query: 'quero cotar meu carro', trust_instruction: true,
                                    **rodadas).answer
    pedidos
  end

  # Anota cada chamada. Na primeira (a do principal), chama o especialista da Lia, para o Runner rodar também.
  def cliente_que_anota(pedidos)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      pedidos << [:chamada, kwargs]
      chamar_especialista(kwargs, executor) if pedidos.count { |pedido| pedido.first == :chamada } == 1
      { text: kwargs[:schema] == Autonomia::Agents::Specialists::Runner::RESULT_SCHEMA ? '{}' : resposta_do_principal }
    end
    allow(client).to receive(:create) do |**kwargs|
      pedidos << [:create, kwargs]
      { text: resposta_do_principal }
    end
    client
  end

  def chamar_especialista(kwargs, executor)
    funcoes = lia.specialists.enabled.map(&:function_name)
    especialista = Array(kwargs[:tools]).find { |tool| funcoes.include?(tool[:name].to_s) }
    return unless especialista && executor

    executor.call([{ 'name' => especialista[:name], 'call_id' => 'c1', 'arguments' => { 'pedido' => 'cotar o carro' }.to_json }])
  end

  it 'manda o mesmo pedido com a Fase 2 desligada e com a Fase 2 ligada e um ajudante na conta' do
    desligada = pedidos_do_turno

    Autonomia::Agents::Fase2.ligar!(conta)
    joana = criar_principal(conta)
    vincular(joana, criar_ajudante(conta))
    ligada = pedidos_do_turno

    expect(desligada.count { |p| p.first == :chamada }).to be >= 2 # o principal e o especialista
    expect(ligada).to eq(desligada)
  end

  # A comparação acima não pega uma mudança que valha igual nos dois lados; aqui, os botões da Cotação, com os valores
  # de antes do tema 14: as etiquetas de consumo, as rodadas e o relógio do principal e do especialista.
  it 'o principal e o especialista da Lia seguem com as etiquetas, as rodadas e o relógio de antes' do
    Autonomia::Agents::Fase2.ligar!(conta)
    vincular(criar_principal(conta), criar_ajudante(conta))

    pedidos = pedidos_do_turno
    clientes = pedidos.select { |pedido| pedido.first == :cliente }.map { |pedido| pedido.last[:feature] }
    principal, especialista = pedidos.select { |pedido| pedido.first == :chamada }.map(&:last)

    expect(clientes.first(2)).to eq(%w[agente_resposta agente_especialista])
    expect(principal.slice(:max_rodadas, :max_segundos)).to eq(Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(lia))
    expect(especialista.slice(:max_rodadas, :max_segundos, :timeout)).to eq(
      max_rodadas: Autonomia::Agents::Specialists::Runner::RODADAS_DE_FERRAMENTA,
      max_segundos: Autonomia::Agents::Specialists::Runner::SEGUNDOS_DE_FERRAMENTA,
      timeout: Autonomia::Agents::Specialists::Runner::SEGUNDOS_POR_CHAMADA
    )
    expect(especialista[:instructions]).not_to include('um ajudante consultado')
  end

  it 'as rodadas da Lia continuam as do Builder: o ajudante não dá rodada a ela' do
    Autonomia::Agents::Fase2.ligar!(conta)

    expect(Autonomia::Agents::Ajudantes.rodadas(lia)).to be_nil
  end
end
