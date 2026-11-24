require 'rails_helper'

# Paridade da conversa (#3211), P1 e P2 no turno real (gatilho, settle, Responder, entrega), com a IA dublada:
# - P1 (`conversa_espera_a_fala`): o settle fica marcado para quando a fala anterior acaba, não para a janela fixa;
# - P2 (`conversa_em_fila`): com outro turno falando, o settle volta de 2 em 2 s sem responder, até o teto da fila; a
#   resposta superada por mensagem nova durante a IA é descartada, com ou sem Fase 2;
# - a fala ocupada por este turno sai por qualquer caminho (resposta, falha, opção desligada no meio), menos quando a
#   cadeia de pedaços fica com ela.
# Sem as opções, o turno é o de sempre: 6 s de debounce e as duas respostas fora da Fase 2.
RSpec.describe Autonomia::Agents::Operate::ReplyJob, :um_turno do
  include_context 'with crm responsible agent'

  let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
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

  def liga!(*chaves)
    agente_da_porta.update!(config: agente_da_porta.config.to_h.merge(chaves.index_with(true)))
  end

  it 'P1: settle marcado para quando a fala anterior acaba' do
    liga!('conversa_espera_a_fala')
    allow(fala).to receive(:fim_previsto).and_return(25.seconds.from_now)

    gatilho(cliente_escreve('oi'))

    expect(Time.zone.at(settles_na_fila.sole[:at])).to be_within(0.5.seconds).of(25.seconds.from_now)
    expect(conversation.reload.additional_attributes.dig('autonomia_debounce', 'espera_ms')).to eq(25_000)
  end

  it 'sem opção: 6 s, como hoje' do
    gatilho(cliente_escreve('oi'))

    expect(Time.zone.at(settles_na_fila.sole[:at])).to be_within(0.5.seconds).of(6.seconds.from_now)
  end

  it 'P2: outro turno falando, o settle volta em 2 s e não responde' do
    liga!('conversa_em_fila')
    fala.ocupar(conversation.id, 999_999)
    mensagem = cliente_escreve('oi')
    gatilho(mensagem)

    rodar_rodada!

    expect(respostas).to be_empty
    expect(Time.zone.at(settles_na_fila.sole[:at])).to be_within(0.5.seconds).of(2.seconds.from_now)

    fala.soltar(conversation.id, 999_999)
    rodar_turno!

    expect(respostas.count).to eq(1)
  end

  it 'P2: passado o teto da fila, responde mesmo com a marca de outro' do
    liga!('conversa_em_fila')
    fala.ocupar(conversation.id, 999_999)
    mensagem = cliente_escreve('oi')
    gatilho(mensagem)

    travel 6.seconds + 151.seconds
    settle(mensagem)

    expect(respostas.count).to eq(1)
  end

  it 'P2 sem Fase 2: mensagem nova durante a IA descarta a resposta velha; uma resposta só' do
    Autonomia::Agents::Fase2.desligar!(account)
    liga!('conversa_em_fila')
    primeira = cliente_escreve('oi')
    gatilho(primeira)
    segunda = nil
    ia_responde!(durante: ->(_) { segunda ||= cliente_escreve('quero cotar').tap { |m| gatilho(m) } })

    rodar_turno!

    expect(respostas.count).to eq(1)
    expect(respostas.sole.content_attributes['autonomia_reply_to_message_id']).to eq(segunda.id)
  end

  it 'sem opção e sem Fase 2: posta as duas, como hoje' do
    Autonomia::Agents::Fase2.desligar!(account)
    primeira = cliente_escreve('oi')
    gatilho(primeira)
    segunda = nil
    ia_responde!(durante: ->(_) { segunda ||= cliente_escreve('quero cotar').tap { |m| gatilho(m) } })

    rodar_turno!

    expect(respostas.count).to eq(2)
  end

  it 'durante a IA a fala é deste turno; depois, solta' do # Review Focus 2
    liga!('conversa_em_fila')
    mensagem = cliente_escreve('oi')
    durante = nil
    ia_responde!(durante: ->(_) { durante = Redis::Alfred.get(fala.chave_ocupada(conversation.id)) })

    gatilho(mensagem)
    rodar_turno!

    expect(durante).to eq(mensagem.id.to_s)
    expect(Redis::Alfred.get(fala.chave_ocupada(conversation.id))).to be_nil
  end

  it 'a IA falhou: solta a fala' do # Review Focus 2
    liga!('conversa_em_fila')
    allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(StandardError, 'caiu')

    gatilho(cliente_escreve('oi'))
    rodar_turno!

    expect(Redis::Alfred.get(fala.chave_ocupada(conversation.id))).to be_nil
  end

  it 'opção desligada no meio do turno: ainda solta' do # Review Focus 2
    liga!('conversa_em_fila')
    ia_responde!(durante: ->(agent) { agent.update!(config: agent.config.except('conversa_em_fila')) })

    gatilho(cliente_escreve('oi'))
    rodar_turno!

    expect(Redis::Alfred.get(fala.chave_ocupada(conversation.id))).to be_nil
  end

  it 'com pedaços: a cadeia fica com a fala' do
    # O "digitando" do canal não é o assunto aqui (mesma dublagem do reply_job_turno_em_curso_spec).
    allow_any_instance_of(Autonomia::Agents::Operate::TypingIndicator).to receive(:on) # rubocop:disable RSpec/AnyInstance
    with_modified_env(AI_HUMANIZE_DELIVERY: 'true') do
      liga!('conversa_em_fila')
      mensagem = cliente_escreve('oi')
      gatilho(mensagem)

      rodar_turno!

      expect(Redis::Alfred.get(fala.chave_ocupada(conversation.id))).to eq(mensagem.id.to_s)
    end
  end

  it 'Fase 2: depois da fila, com o assunto decidido, uma resposta e nenhum assunto_atrasou' do # Review Focus 4
    liga!('conversa_em_fila')
    contrato!(ordem: true)
    fala.ocupar(conversation.id, 999_999)
    mensagem = cliente_escreve('oi')
    gatilho(mensagem)

    rodar_rodada! # o settle do debounce (T+6 s): outro turno falando, volta em 2 s sem responder nem ler o assunto
    expect(respostas).to be_empty
    expect(Time.zone.at(settles_na_fila.sole[:at])).to be_within(0.5.seconds).of(2.seconds.from_now)

    # Enquanto espera na fila, o assunto é decidido; a fila libera depois do teto de 20 s do assunto (T+30 s).
    allow(contrato).to receive(:decidido_ate).with(conversation.id).and_return(mensagem.id)
    travel 24.seconds
    fala.soltar(conversation.id, 999_999)
    rodar_turno!

    expect(respostas.count).to eq(1)
    expect(Autonomia::Agents::AgentEvent.skipped_assunto_atrasou.where(conversation_id: conversation.id)).to be_empty
  end

  it 'Redis fora do ar: responde' do # Review Focus 5
    liga!('conversa_em_fila', 'conversa_espera_a_fala')
    allow(Redis::Alfred).to receive(:get).and_call_original
    allow(Redis::Alfred).to receive(:get).with(fala.chave_ocupada(conversation.id)).and_raise(Redis::CannotConnectError)

    gatilho(cliente_escreve('oi'))
    rodar_turno!

    expect(respostas.count).to eq(1)
  end
end
