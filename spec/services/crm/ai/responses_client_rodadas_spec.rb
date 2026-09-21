require 'rails_helper'

# O laço de ferramentas (#568).
#
# Antes havia UMA rodada: o modelo chamava, executávamos, e a segunda ida já
# saía sem ferramenta. Não dava para olhar o que voltou e pedir de novo — nem a
# página seguinte de uma lista, nem outro recurso numa pergunta que precisa de
# dois. O Guia da Plataforma pede mais rodadas; todo o resto continua em uma.
RSpec.describe Crm::Ai::ResponsesClient do
  let(:cliente) { described_class.new(credential: { api_key: 'chave-de-teste', source: 'spec' }) }
  let(:ferramentas) { [{ type: 'function', name: 'ler_da_conta' }] }

  # Uma resposta da OpenAI pedindo ferramenta, e outra respondendo de verdade.
  def pedindo_ferramenta
    { 'output' => [{ 'type' => 'function_call', 'name' => 'ler_da_conta', 'call_id' => 'c1', 'arguments' => '{}' }] }
  end

  def respondendo
    { 'output_text' => '{"reply":"pronto"}', 'output' => [] }
  end

  # `post_responses` é privado de propósito (monta cabeçalho e credencial). O
  # dublê fica nele porque o que está sendo medido é o LAÇO, não o HTTP.
  def responder_com(sequencia)
    corpos = []
    allow(cliente).to receive(:post_responses) do |body, **|
      corpos << body
      instance_double(HTTParty::Response, success?: true, parsed_response: sequencia.shift || respondendo)
    end
    corpos
  end

  it 'mantém UMA rodada por padrão: a segunda ida já vai sem ferramenta', :aggregate_failures do
    corpos = responder_com([pedindo_ferramenta, respondendo])
    executadas = 0

    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil,
                                      tools: ferramentas) do |_calls|
      executadas += 1
      [{ type: 'function_call_output', call_id: 'c1', output: 'ok' }]
    end

    expect(executadas).to eq(1)
    expect(corpos.size).to eq(2)
    expect(corpos.last[:tools]).to be_nil
  end

  it 'com mais rodadas, o modelo pode ler, olhar e ler de novo', :aggregate_failures do
    corpos = responder_com([pedindo_ferramenta, pedindo_ferramenta, respondendo])
    executadas = 0

    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil,
                                      tools: ferramentas, max_rodadas: 4) do |_calls|
      executadas += 1
      [{ type: 'function_call_output', call_id: 'c1', output: 'ok' }]
    end

    # Duas chamadas de ferramenta, e a terceira ida — já sem pedir nada — respondeu.
    expect(executadas).to eq(2)
    expect(corpos.size).to eq(3)
    expect(corpos[0][:tools]).to be_present
    expect(corpos[1][:tools]).to be_present
  end

  # O que garante que o laço termina mesmo com um modelo que insiste: a ida
  # final SEMPRE sai sem ferramenta, então ele responde com o que já leu.
  it 'termina quando o modelo insiste em chamar ferramenta', :aggregate_failures do
    corpos = responder_com(Array.new(4) { pedindo_ferramenta } + [respondendo])
    executadas = 0

    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil,
                                      tools: ferramentas, max_rodadas: 4) do |_calls|
      executadas += 1
      [{ type: 'function_call_output', call_id: 'c1', output: 'ok' }]
    end

    expect(executadas).to eq(4)
    expect(corpos.size).to eq(5)
    expect(corpos.last[:tools]).to be_nil
  end

  # Teto duro acima do que qualquer chamador pede: o painel do Guia é síncrono e
  # o Puma roda em modo single. Ninguém segura uma thread indefinidamente.
  it 'não passa do teto duro de rodadas, mesmo se pedirem mais' do
    insistentes = Array.new(described_class::MAX_RODADAS_DE_FERRAMENTA) { pedindo_ferramenta }
    corpos = responder_com(insistentes + [respondendo])

    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil,
                                      tools: ferramentas, max_rodadas: 99) do |_calls|
      [{ type: 'function_call_output', call_id: 'c1', output: 'ok' }]
    end

    expect(corpos.size).to eq(described_class::MAX_RODADAS_DE_FERRAMENTA + 1)
  end

  # O teto de rodadas impede laço infinito; ele NÃO protege a thread. Dez
  # rodadas lentas, a 120s de teto cada, são vinte minutos segurando uma das
  # cinco threads do Puma — e o painel do Guia é requisição síncrona. Estourando
  # o tempo, a última ida vai sem ferramenta e ele responde com o que já leu.
  it 'para de chamar ferramenta quando estoura o orçamento de tempo', :aggregate_failures do
    corpos = responder_com([pedindo_ferramenta, respondendo])
    # O relógio fica parado durante a primeira rodada (quatro leituras: o marco
    # inicial, a checagem, o início da chamada e o log) e depois salta para além
    # do orçamento inteiro — como se aquela rodada tivesse demorado demais.
    leituras = 0
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) do
      leituras += 1
      leituras <= 4 ? 0.0 : described_class::MAX_SEGUNDOS_DE_FERRAMENTA + 1.0
    end

    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil,
                                      tools: ferramentas, max_rodadas: 10) do |_calls|
      [{ type: 'function_call_output', call_id: 'c1', output: 'ok' }]
    end

    # Pediram DEZ rodadas e só uma saiu com ferramenta: quem parou foi o tempo,
    # não o teto de repetição. O fechamento vai sem ferramenta, como sempre.
    expect(corpos.size).to eq(2)
    expect(corpos.first[:tools]).to be_present
    expect(corpos.last[:tools]).to be_nil
  end

  it 'responde direto quando o modelo não pede ferramenta nenhuma' do
    corpos = responder_com([respondendo])

    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil,
                                      tools: ferramentas, max_rodadas: 4) { |_calls| [] }

    expect(corpos.size).to eq(1)
  end
end
