require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (eval com provedor pago só com execução explícita).
# Roda com `AUTONOMIA_EVAL_PAGO=1` e `OPENAI_API_KEY`, contra o modelo de produção do Construtor.
#
# #641: a intenção de fechar do Construtor era a regex CLOSE_INTENT_PATTERNS sobre a fala crua do dono. Virou o
# campo `user_asked_to_close` do schema de saída. O que a regex tratava com exceção manual (negação, "pode criar" que
# é pedido novo, "sem material") agora é entendimento do modelo, e só se prova com o modelo: mesma instrução-mãe,
# mesmo input montado pelo Builder, mesmo schema e mesmo esforço de raciocínio da produção.
module AvaliacaoDoFechamento
  PERGUNTA_ABERTA = 'E qual o horário de atendimento da Ana?'.freeze

  # [fala do dono, leitura esperada]
  CRIACAO = [
    ['pode fechar', true],
    ['monta assim mesmo, depois eu ajusto', true],
    ['Terminei, você pode finalizar o agente.', true],
    ["that's enough questions, just build it", true],
    ['chega de pergunta, cria ela do jeito que está', true],
    ['de segunda a sexta, das 9h às 18h', false],
    ['ainda não pode fechar, falta eu te passar o horário', false],
    ['não monte sem o material de preços que ficou pendente', false],
    ['não tenho material nenhum', false]
  ].freeze

  # Em AJUSTE o agente já existe: "pode criar X" é pedido de edição, não ordem de fechar.
  AJUSTE = [
    ['pode criar uma saudação nova também', false],
    ['inclui o link do catálogo na resposta de preços', false]
  ].freeze
end

RSpec.describe Autonomia::Agents::Builder do
  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  let(:account) { create(:account) }

  def leitura_do_modelo(fala, agent: nil)
    thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent)
    thread.persist_start_options!(type: 'sdr')
    thread.save!
    thread.append_message!('user', 'Quero uma SDR chamada Ana para a minha corretora de seguros.')
    thread.append_message!('assistant', AvaliacaoDoFechamento::PERGUNTA_ABERTA)
    thread.append_message!('user', fala)
    builder = described_class.new(account: account, build_thread: thread)
    cliente = Crm::Ai::ResponsesClient.new(credential: { api_key: ENV.fetch('OPENAI_API_KEY') }, feature: 'eval_construtor')
    raw = cliente.create(model: Autonomia::Agents::Config::BUILDER_MODEL, instructions: described_class::MOTHER_INSTRUCTION,
                         input: builder.send(:build_input), schema: described_class::BUILDER_SCHEMA,
                         reasoning_effort: builder.send(:reasoning_effort))
    JSON.parse(raw[:text])['user_asked_to_close']
  end

  def avaliar(casos, agent: nil)
    casos.filter_map do |fala, esperado|
      lida = leitura_do_modelo(fala, agent: agent)
      "#{fala.inspect}: esperado #{esperado}, lido #{lida.inspect}" unless lida == esperado
    end
  end

  it 'o Construtor lê a ordem de fechar na fala do dono', :eval_pago do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1 e OPENAI_API_KEY' unless ligada

    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', mode: :guided,
                                              status: :active, enabled: true, instruction: 'Instrução fechada da Ana.')
    erros = avaliar(AvaliacaoDoFechamento::CRIACAO) + avaliar(AvaliacaoDoFechamento::AJUSTE, agent: agente)

    expect(erros).to be_empty, "leituras erradas:\n#{erros.join("\n")}"
  end
end
