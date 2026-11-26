require 'rails_helper'

# #3235: com a entrega em pedaços, o fim previsto da fala é a soma das esperas dos pedaços AGENDADOS (depois do
# RitmoDoCanal), presas como o ChunkedDeliveryJob as prende, e não uma estimativa pelo tamanho do texto. Antes, ~650
# caracteres previam ~104 s para uma entrega de 38 s, e a rajada seguinte esperava à toa. A caixa do cenário não é
# WhatsApp oficial: com o ritmo do canal, o 2º pedaço ganha a pausa a mais (responder_ritmo_do_canal_spec).
RSpec.describe Autonomia::Agents::Operate::Responder, :um_turno do
  include_context 'with crm responsible agent'

  let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'true', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    ia_responde!
    clear_enqueued_jobs
    freeze_time
    limpar_a_fala!
  end

  after { limpar_a_fala! }

  def limpar_a_fala!
    Redis::Alfred.delete(fala.chave_ocupada(conversation.id))
    Redis::Alfred.delete(fala.chave_do_fim(conversation.id))
  end

  def pedacos_quebrados(*esperas)
    allow(Autonomia::Agents::Operate::ReplyChunker).to receive(:call)
      .and_return(esperas.map.with_index { |espera, i| { 'text' => "pedaço #{i}", 'type' => 'text', 'delay_ms' => espera } })
  end

  def pedacos_agendados = ActiveJob::Arguments.deserialize(jobs_de(UmTurnoHelper::CHUNK_JOB).sole[:args])[3]

  # Pega: o fim calculado sobre os pedaços antes do ritmo do canal (o job espera os de depois).
  it 'o fim é agora mais a soma das esperas dos pedaços agendados, com o ritmo do canal', :aggregate_failures do
    pedacos_quebrados(5000, 4000)
    mensagem = cliente_escreve('oi')
    gatilho(mensagem)
    rodar_turno!

    expect(pedacos_agendados.pluck('delay_ms')).to eq([5000, 6000])
    expect(fala.fim_previsto(conversation.id)).to be_within(0.001.seconds).of(11.seconds.from_now)
    expect(Redis::Alfred.get(fala.chave_do_fim(conversation.id))).to start_with("#{mensagem.id}:")
  end

  # Pega: a soma sem o mesmo limite do job (0,1 s a 30 s por pedaço) prever uma fala mais longa ou mais curta que a real.
  it 'cada espera entra na soma presa como o job a prende' do
    desligar_paridade!(agente_da_porta, 'conversa_ritmo_do_canal')
    pedacos_quebrados(45_000, 20)
    gatilho(cliente_escreve('oi'))
    rodar_turno!

    expect(fala.fim_previsto(conversation.id)).to be_within(0.001.seconds).of(30.1.seconds.from_now)
  end

  it 'com a opção desligada, não grava o fim' do
    desligar_paridade!(agente_da_porta, 'conversa_espera_a_fala')
    pedacos_quebrados(5000, 4000)
    gatilho(cliente_escreve('oi'))
    rodar_turno!

    expect(fala.fim_previsto(conversation.id)).to be_nil
  end
end
