# #1428 (tema 6, parte 2) — montagem comum dos specs do "Mudar conversando" no piloto: o Hubber, a thread de ajuste,
# o Construtor e a conferência dublados. `respostas` são as saídas do Construtor na ordem (`:falha` levanta erro do
# provedor); `conferencias` são as marcas da conferência (`nao:`, `fora:`, `conflito:`, `erro:`), aplicadas à lista
# que ela recebeu.
RSpec.shared_context 'with ajuste por lista' do
  let(:account) { conta_da_fase2 }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Hubber', agent_type: 'support', mode: :guided, status: :active, enabled: true,
      instruction: 'Atenda o cliente da corretora com cordialidade.', scaffold: 'andaime', tone: 'cordial',
      greeting: 'Oi! Aqui é o Hubber.', fallback_message: 'Vou confirmar com a equipe.',
      handoff_rule: 'Passe para a equipe quando o cliente pedir.', starter_questions: ['Como funciona?'],
      human_card: 'O Hubber atende os clientes.', config: { 'guardrails' => ['Não invente valores.'], 'voice' => 'masculina',
                                                            'with_knowledge' => false }
    )
  end
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, agent: agent) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:conferente) { instance_double(Autonomia::Agents::ConferenciaDoAjuste) }
  let(:calls) { [] }
  let(:respostas) { [] }
  let(:conferencias) { [] }
  let(:recebidas) { [] }
  let(:fala) { 'Responda em no máximo 2 frases' }

  # A saída do Construtor no ajuste: a config atual, com o que o teste mudar por cima.
  def saida(overrides = {})
    { 'name' => 'Hubber', 'agent_type' => 'support', 'instruction' => 'Atenda o cliente da corretora com cordialidade.',
      'scaffold' => 'andaime', 'human_card' => 'O Hubber atende os clientes.', 'greeting' => 'Oi! Aqui é o Hubber.',
      'fallback_message' => 'Vou confirmar com a equipe.', 'handoff_rule' => 'Passe para a equipe quando o cliente pedir.',
      'starter_questions' => ['Como funciona?'], 'tone' => 'cordial', 'guardrails' => ['Não invente valores.'],
      'voice' => 'masculina', 'needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => false,
      'so_pergunta' => false, 'mudancas' => [], 'resposta_ao_dono' => '' }.merge(overrides)
  end

  def mudanca(campo, pedido = fala, resumo = 'Mudou.')
    { 'pedido' => pedido, 'campo' => campo, 'resumo' => resumo }
  end

  # O que a conferência devolveria para esta lista, com as marcas dadas.
  def conferencia_de(mudancas, nao: [], fora: false, conflito: false, erro: nil)
    return Autonomia::Agents::ConferenciaDoAjuste::INDISPONIVEL.merge('duracao_ms' => 1) if erro

    itens = mudancas.each_with_index.map { |item, indice| item.merge('atendido' => nao.exclude?(indice), 'pedido_pelo_dono' => true) }
    { 'itens' => itens, 'faltou_fora_da_lista' => fora, 'conflito' => conflito, 'falta' => nao.any? || fora,
      'duracao_ms' => 5 }
  end

  def texto(chave, **)
    I18n.t("autonomia.agents.ajuste.#{chave}", **)
  end

  before do
    allow(builder).to receive_messages(credential: { api_key: 'chave-de-teste' }, client: fake_client,
                                       cliente_da_correcao: fake_client)
    allow(fake_client).to receive(:create) do |**params|
      calls << params
      resposta = respostas.shift || saida
      raise Crm::Ai::ResponsesClient::Error, 'timeout' if resposta == :falha

      { text: resposta.to_json, usage: {}, tools_used: [] }
    end
    allow(Autonomia::Agents::ConferenciaDoAjuste).to receive(:new).and_return(conferente)
    allow(conferente).to receive(:conferir) do |**kwargs|
      recebidas << kwargs
      marcas = conferencias.shift || {}
      raise marcas if marcas.is_a?(Exception)

      conferencia_de(kwargs[:mudancas], **marcas)
    end
    thread.append_message!('user', fala)
  end

  def run_turn(token = thread.begin_build!)
    builder.run!(token)
  end

  def versoes_do_construtor
    agent.instruction_versions.where(reason: 'builder_adjust').order(:id)
  end

  def estado
    thread.reload.state
  end

  def ultimas_do_assistente(quantas)
    thread.reload.messages.last(quantas).map { |mensagem| [mensagem['role'], mensagem['content']] }
  end
end
