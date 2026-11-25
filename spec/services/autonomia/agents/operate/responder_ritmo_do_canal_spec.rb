require 'rails_helper'

# Paridade da conversa (#3211), P5: com `conversa_ritmo_do_canal`, o delay de cada pedaço agendado ganha a pausa
# pós-envio. A caixa do cenário não é WhatsApp oficial: a espera dos pedaços fica cheia. A opção nasce ligada (menos na
# Lia); gravada `false`, os pedaços saem como antes.
RSpec.describe Autonomia::Agents::Operate::Responder, :um_turno do
  include_context 'with crm responsible agent'

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'true', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    ia_responde!
    allow(Autonomia::Agents::Operate::ReplyChunker).to receive(:call).and_return(
      [{ 'text' => 'A' * 70, 'type' => 'text', 'delay_ms' => 5000 }, { 'text' => 'B' * 70, 'type' => 'text', 'delay_ms' => 4000 }]
    )
    clear_enqueued_jobs
    freeze_time
  end

  def liga!(*chaves)
    agente_da_porta.update!(config: agente_da_porta.config.to_h.merge(chaves.index_with(true)))
  end

  def pedacos_agendados = ActiveJob::Arguments.deserialize(jobs_de(UmTurnoHelper::CHUNK_JOB).sole[:args])[3]

  it 'com a opção, o 2º pedaço espera a pausa a mais (caixa que não é WhatsApp oficial)' do
    liga!('conversa_ritmo_do_canal')
    gatilho(cliente_escreve('oi'))
    rodar_turno!

    expect(pedacos_agendados.pluck('delay_ms')).to eq([5000, 6000])
  end

  it 'sem a chave (padrão ligado), o 2º pedaço espera a pausa a mais' do
    gatilho(cliente_escreve('oi'))
    rodar_turno!

    expect(pedacos_agendados.pluck('delay_ms')).to eq([5000, 6000])
  end

  it 'opção desligada, como antes' do
    desligar_paridade!(agente_da_porta, 'conversa_ritmo_do_canal')
    gatilho(cliente_escreve('oi'))
    rodar_turno!

    expect(pedacos_agendados.pluck('delay_ms')).to eq([5000, 4000])
  end
end
