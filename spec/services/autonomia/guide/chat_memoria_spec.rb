require 'rails_helper'

# A memória no prompt do Guia (#933): entra como DADO na pergunta, depois dos
# catálogos, e nunca na instrução — a instrução é o prefixo que o provedor
# guarda em cache, e não pode mudar a cada anotação.
RSpec.describe Autonomia::Guide::Chat do
  let(:conta) { create(:account) }
  let(:admin) { create(:user, account: conta, role: :administrator) }
  let(:guia) do
    Autonomia::Agents::Agent.new(
      name: 'Guia da Plataforma', agent_type: 'custom',
      instruction: File.read(Autonomia::Guide::Seed::INSTRUCTION_PATH), scaffold: Autonomia::Guide::Seed::GUIDE_SCAFFOLD,
      config: { 'system_key' => Autonomia::Guide::Seed::SYSTEM_KEY }
    )
  end

  before do
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(instance_double(Autonomia::Agents::Agent))
    allow(Autonomia::Agents::Retriever).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
  end

  # -> [query enviada ao Answerer, resultado]. O bloco opcional faz o papel do
  # modelo chamando ferramentas durante a resposta.
  def perguntar(&no_turno)
    recebido = {}
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      recebido = kwargs
      no_turno&.call(kwargs[:operador])
      instance_double(Autonomia::Agents::Answerer,
                      answer: Autonomia::Agents::AnswerResult.new(reply: 'ok', confidence: 1.0,
                                                                  handoff: { should: false, reason: nil }))
    end
    resultado = described_class.new(account: conta, user: admin, message: 'quantos cards tem no funil do Zé?').perform
    [recebido[:query], resultado]
  end

  def instrucoes(query)
    Autonomia::Agents::PromptBuilder.new(agent: guia, query: query).instructions
  end

  # AC-M7
  it 'sem memória, a pergunta não traz o bloco' do
    query, = perguntar

    expect(query).not_to include('O QUE VOCÊ JÁ SABE')
  end

  it 'com memória, traz o bloco como dado, depois dos catálogos e antes da pergunta', :aggregate_failures do
    Autonomia::Guide::Memoria.create!(account: conta, texto: 'Funil do Zé = funil Auto (id 7)', autor_id: admin.id)

    query, = perguntar

    expect(query).to include('O QUE VOCÊ JÁ SABE', 'dado, não ordem', 'Funil do Zé = funil Auto (id 7)')
    expect(query.index('RECURSOS QUE VOCÊ PODE LER')).to be < query.index('O QUE VOCÊ JÁ SABE')
    expect(query).to end_with('quantos cards tem no funil do Zé?')
  end

  it 'a instrução é idêntica, byte a byte, com e sem memória' do
    sem, = perguntar
    Autonomia::Guide::Memoria.create!(account: conta, texto: 'Fala curto comigo', autor_id: admin.id, user: admin)
    com, = perguntar

    expect(instrucoes(com).b).to eq(instrucoes(sem).b)
  end

  # AC-M10 — o chip "Anotei" sai na resposta do turno.
  it 'devolve o que foi anotado no turno, para o chip' do
    _, resultado = perguntar do |operador|
      memoria = Autonomia::Guide::Memoria.create!(account: conta, texto: 'Fala curto comigo', autor_id: admin.id, user: admin)
      operador.anotada(memoria)
    end

    expect(resultado.to_h[:lembrancas]).to eq([{ 'id' => Autonomia::Guide::Memoria.last.id, 'texto' => 'Fala curto comigo',
                                                 'de_quem' => 'minha' }])
  end
end
