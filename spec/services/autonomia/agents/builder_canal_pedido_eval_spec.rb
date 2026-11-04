require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (eval com provedor pago só com execução explícita e teto).
# Roda com `AUTONOMIA_EVAL_PAGO=1` e `OPENAI_API_KEY`, contra o modelo de produção do Construtor. Teto da rodada em
# `AUTONOMIA_EVAL_TETO_USD` (padrão 1,80): passou, a rodada para no meio e falha dizendo o gasto.
#
# #2490: o canal que o dono pede ao Construtor (`canal_pedido`) é leitura do MODELO, sem lista de palavras. Só se prova
# com o modelo: mesma instrução-mãe, mesmo input montado pelo Builder, mesmo schema e mesmo esforço de raciocínio da
# produção. A entrevista decide pela chamada ENXUTA (aviso LEAN_TURN_NOTE no fim do input); o fechamento, pela chamada
# completa, e é dela o valor que a Confira lê. Conversas inventadas, sem dado de cliente.
module AvaliacaoDoCanalPedido
  ABERTURA = 'Oi! Vamos montar seu agente. Me conta o que ele vai fazer e para quem.'.freeze

  # [falas do dono (a primeira responde a abertura; entre elas, uma pergunta do Construtor), canal esperado]
  ENTREVISTA = [
    [['Quero uma atendente pro Instagram da clínica, pra responder o direct das pacientes.'], 'instagram'],
    [['Sou corretora de seguro auto. O pessoal manda zap pra gente o dia todo, é lá que ela tem que responder.'], 'whatsapp'],
    [['Meus clientes me acham pelo Instagram, mas quero o agente respondendo no WhatsApp da loja.'], 'whatsapp'],
    [['Quero ele no site da imobiliária, naquele chat do canto da tela.'], 'site'],
    [['Ela vai atender no WhatsApp e no Instagram, os dois.'], 'nenhum'],
    [['Quero uma SDR para qualificar os leads da minha corretora de seguros.'], 'nenhum'],
    [['Quero um agente pro Instagram da pizzaria.', 'Pensando melhor, coloca no WhatsApp, o povo pede mais por lá.'],
     'whatsapp'],
    [['Um agente de suporte para a minha escola de inglês. Onde ele atende você decide, tanto faz.'], 'nenhum'],
    [['Preciso responder as mensagens que chegam na página da loja no Facebook.'], 'facebook'],
    [['Quero que ele responda os e-mails de pedido de orçamento da gráfica.'], 'email'],
    [['A gente vende muito pelo Instagram. Quero um agente que explique os planos de seguro viagem.'], 'nenhum'],
    [['Recepção da academia, no WhatsApp.', 'Seg a sex das 6h às 22h, sábado até 14h.'], 'whatsapp']
  ].freeze

  # O fechamento é a chamada que aplica o agente: o valor dela é o que fica no state.
  FECHAMENTO = [
    [['Quero a Bia atendendo no Instagram da loja de roupas, respondendo dúvida de tamanho e prazo de entrega.',
      'Pode fechar assim mesmo.'], 'instagram'],
    [['Quero a Bia para tirar dúvidas da loja de roupas.', 'Pode fechar assim mesmo.'], 'nenhum']
  ].freeze

  PERGUNTA_DO_MEIO = 'Entendi. E qual o horário de atendimento?'.freeze
end

RSpec.describe Autonomia::Agents::Builder do
  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  let(:account) { create(:account) }
  let(:teto) { ENV.fetch('AUTONOMIA_EVAL_TETO_USD', '1.80').to_f }
  let(:gasto) { { usd: 0.0 } }

  def thread_com(falas)
    thread = Autonomia::Agents::BuildThread.create!(account: account)
    thread.persist_start_options!(type: 'custom', with_knowledge: false)
    thread.save!
    thread.append_message!('assistant', AvaliacaoDoCanalPedido::ABERTURA)
    falas.each_with_index do |fala, i|
      thread.append_message!('assistant', AvaliacaoDoCanalPedido::PERGUNTA_DO_MEIO) if i.positive?
      thread.append_message!('user', fala)
    end
    thread
  end

  def leitura(falas, fechamento:)
    builder = described_class.new(account: account, build_thread: thread_com(falas))
    cliente = Crm::Ai::ResponsesClient.new(credential: { api_key: ENV.fetch('OPENAI_API_KEY') }, feature: 'eval_construtor')
    input = builder.send(:build_input)
    input += [{ role: 'developer', content: [{ type: 'input_text', text: described_class::LEAN_TURN_NOTE }] }] unless fechamento
    esforco = fechamento ? Autonomia::Agents::Config::BUILDER_REASONING_EFFORT : Autonomia::Agents::Config::BUILDER_REASONING_EFFORT_COLLECT
    raw = cliente.create(model: Autonomia::Agents::Config::BUILDER_MODEL, instructions: described_class::MOTHER_INSTRUCTION,
                         input: input, schema: described_class::BUILDER_SCHEMA, reasoning_effort: esforco)
    tokens = Crm::Ai::UsageRecorder.extract_tokens(raw[:usage])
    gasto[:usd] += Crm::Ai::UsageRecorder.cost_for(Autonomia::Agents::Config::BUILDER_MODEL, tokens)
    JSON.parse(raw[:text])['canal_pedido']
  end

  def avaliar(casos, fechamento:)
    casos.filter_map do |falas, esperado|
      raise "teto de US$ #{teto} atingido (gasto US$ #{gasto[:usd].round(4)})" if gasto[:usd] >= teto

      lido = leitura(falas, fechamento: fechamento)
      "#{falas.last.inspect}: esperado #{esperado}, lido #{lido.inspect}" unless lido == esperado
    end
  end

  it 'o Construtor lê o canal que o dono pediu, ou nenhum', :eval_pago do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1 e OPENAI_API_KEY' unless ligada

    erros = avaliar(AvaliacaoDoCanalPedido::ENTREVISTA, fechamento: false) +
            avaliar(AvaliacaoDoCanalPedido::FECHAMENTO, fechamento: true)
    puts "[eval canal_pedido] #{AvaliacaoDoCanalPedido::ENTREVISTA.size + AvaliacaoDoCanalPedido::FECHAMENTO.size} " \
         "cenas, gasto US$ #{gasto[:usd].round(4)}"

    expect(erros).to be_empty, "leituras erradas:\n#{erros.join("\n")}"
  end
end
