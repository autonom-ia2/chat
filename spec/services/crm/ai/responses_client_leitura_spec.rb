require 'rails_helper'

# #3225: o laço de ferramentas com a leitura da mensagem que chega no meio do turno (`leitura:`). Sem nada novo, as idas
# e o corpo de cada uma são os de sempre; a leitura da rodada entra depois das saídas; a leitura antes de enviar dá mais
# uma volta, com o rascunho como texto e com ferramenta; o relógio esgotado não dá volta; o agente sem ferramenta também
# passa por aqui; as idas da volta gravam o consumo com a etiqueta própria. A leitura é dublada: o que se mede é o laço.
RSpec.describe Crm::Ai::ResponsesClient do
  let(:cliente) { described_class.new(credential: { api_key: 'chave-de-teste', source: 'spec' }) }
  let(:ferramentas) { [{ type: 'function', name: 'cotar' }] }
  let(:leitura) do
    instance_double(Autonomia::Agents::Operate::LeituraNoTurno, feature_da_volta: 'agente_resposta_volta')
  end
  let(:mensagem_nova) { [{ role: 'user', content: [{ type: 'input_text', text: 'Conhece lá?' }] }] }

  before do
    voltas = 0
    allow(leitura).to receive(:voltas) { voltas }
    allow(leitura).to receive(:contar_volta!) { voltas += 1 }
    allow(leitura).to receive_messages(na_rodada: [], antes_de_enviar: [])
  end

  def pedindo_ferramenta
    { 'output' => [{ 'type' => 'function_call', 'name' => 'cotar', 'call_id' => 'c1', 'arguments' => '{}' }] }
  end

  def respondendo(texto = '{"reply":"pronto"}', raciocinio: false)
    saida = [{ 'type' => 'message', 'content' => [{ 'type' => 'output_text', 'text' => texto }] }]
    saida.unshift({ 'type' => 'reasoning', 'id' => 'rs_1', 'summary' => [] }) if raciocinio
    { 'output_text' => texto, 'output' => saida }
  end

  def responder_com(sequencia)
    corpos = []
    allow(cliente).to receive(:post_responses) do |body, **|
      corpos << body
      instance_double(HTTParty::Response, success?: true, parsed_response: sequencia.shift || respondendo)
    end
    corpos
  end

  def chamar(com_leitura: true, tools: ferramentas, **opcoes)
    extras = com_leitura ? { leitura: leitura } : {}
    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil, tools: tools, **extras, **opcoes) do |_calls|
      [{ type: 'function_call_output', call_id: 'c1', output: 'cotado' }]
    end
  end

  it 'sem nada novo: as idas e o corpo de cada uma são os de sem leitura', :aggregate_failures do
    sem = responder_com([pedindo_ferramenta, respondendo])
    chamar(com_leitura: false)
    com = responder_com([pedindo_ferramenta, respondendo])
    chamar

    expect(com).to eq(sem)
    expect(com.size).to eq(2)
    expect(leitura).not_to have_received(:contar_volta!)
  end

  it 'na rodada: lê antes de despachar e depois; o que chegou entra depois das saídas', :aggregate_failures do
    ordem = []
    antes = [{ role: 'developer', content: [{ type: 'input_text', text: 'antes' }] }]
    depois = [{ role: 'developer', content: [{ type: 'input_text', text: 'depois' }] }]
    allow(leitura).to receive(:na_rodada) do
      ordem << :leitura
      ordem.count(:leitura) == 1 ? antes : depois
    end
    corpos = responder_com([pedindo_ferramenta, respondendo])

    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil, tools: ferramentas,
                                      max_rodadas: 2, leitura: leitura) do |_calls|
      ordem << :ferramenta
      [{ type: 'function_call_output', call_id: 'c1', output: 'cotado' }]
    end

    expect(ordem).to eq(%i[leitura ferramenta leitura])
    tipos = corpos.last[:input].map { |item| item[:type] || item['type'] || item[:content].first[:text] }
    expect(tipos).to eq(%w[oi function_call function_call_output antes depois])
    # Com rodada sobrando, não é volta: a ida seguinte já ia com ferramenta.
    expect(leitura).not_to have_received(:contar_volta!)
  end

  it 'na rodada, sem rodada sobrando: a ida seguinte ganha ferramenta de novo (uma volta)', :aggregate_failures do
    allow(leitura).to receive(:na_rodada).and_return(mensagem_nova, [])
    corpos = responder_com([pedindo_ferramenta, respondendo])

    chamar

    expect(corpos.size).to eq(2)
    expect(corpos.last[:tools]).to eq(ferramentas)
    expect(leitura).to have_received(:contar_volta!).with(:rodada).once
  end

  it 'antes de enviar: mais uma ida, com o rascunho e o que chegou, e com ferramenta', :aggregate_failures do
    itens = [{ role: 'assistant', content: [{ type: 'output_text', text: 'rascunho' }] }] + mensagem_nova
    allow(leitura).to receive(:antes_de_enviar).and_return(itens, [])
    corpos = responder_com([respondendo('rascunho', raciocinio: true), respondendo('final')])

    resultado = chamar

    expect(resultado[:text]).to eq('final')
    expect(corpos.size).to eq(2)
    expect(corpos.last[:input].last(2)).to eq(itens)
    expect(corpos.last[:tools]).to eq(ferramentas)
    # O rascunho volta só como texto: os itens de raciocínio da ida anterior não são reenviados.
    expect(corpos.last[:input].map { |item| item['type'] || item[:type] }).not_to include('reasoning')
    expect(leitura).to have_received(:antes_de_enviar).with('rascunho', esgotado: false)
    expect(leitura).to have_received(:contar_volta!).with(:antes_de_enviar).once
  end

  it 'a volta chama ferramenta: uma rodada e o fechamento, sem ferramenta', :aggregate_failures do
    allow(leitura).to receive(:antes_de_enviar).and_return(mensagem_nova, [])
    corpos = responder_com([respondendo('rascunho'), pedindo_ferramenta, respondendo('final')])
    executadas = 0

    cliente.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil, tools: ferramentas,
                                      leitura: leitura) do |_calls|
      executadas += 1
      [{ type: 'function_call_output', call_id: 'c1', output: 'cotado' }]
    end

    expect(executadas).to eq(1)
    expect(corpos.map { |corpo| corpo[:tools].present? }).to eq([true, true, false])
  end

  it 'relógio do laço esgotado: a leitura sabe e não há volta', :aggregate_failures do
    corpos = responder_com([respondendo])

    chamar(max_segundos: -1)

    expect(corpos.size).to eq(1)
    expect(leitura).to have_received(:antes_de_enviar).with('{"reply":"pronto"}', esgotado: true)
  end

  it 'agente sem ferramenta: a volta antes de enviar passa pelo laço, sem ferramenta', :aggregate_failures do
    allow(leitura).to receive(:antes_de_enviar).and_return(mensagem_nova, [])
    corpos = responder_com([respondendo('rascunho'), respondendo('final')])

    expect(chamar(tools: nil)[:text]).to eq('final')
    expect(corpos.size).to eq(2)
    expect(corpos.map { |corpo| corpo.key?(:tools) }).to eq([false, false])
  end

  it 'o consumo das idas da volta vai com a etiqueta própria' do
    medido = described_class.new(credential: { api_key: 'k', source: 'spec' }, feature: 'agente_resposta', account: create(:account))
    allow(leitura).to receive(:antes_de_enviar).and_return(mensagem_nova, [])
    sequencia = [respondendo('rascunho'), respondendo('final')]
    allow(medido).to receive(:post_responses) do
      instance_double(HTTParty::Response, success?: true, parsed_response: sequencia.shift)
    end
    allow(Crm::Ai::UsageRecorder).to receive(:record)

    medido.create_with_tool_executor(model: 'm', instructions: 'i', input: 'oi', schema: nil, tools: nil, leitura: leitura) { [] }

    expect(Crm::Ai::UsageRecorder).to have_received(:record).with(hash_including(feature: 'agente_resposta')).once
    expect(Crm::Ai::UsageRecorder).to have_received(:record).with(hash_including(feature: 'agente_resposta_volta')).once
  end
end
