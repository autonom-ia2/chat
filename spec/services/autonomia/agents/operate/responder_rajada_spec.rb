require 'rails_helper'

# Paridade da conversa (#3211), P1 no Responder: com `conversa_espera_a_fala`, a pergunta é a rajada inteira do cliente e,
# depois de falar, o fim previsto da fala fica gravado. Sem a opção, tudo como sempre. A IA é dublada; o Redis é o de teste.
RSpec.describe Autonomia::Agents::Operate::Responder, :um_turno do
  include_context 'with crm responsible agent'

  let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }
  let(:perguntas) { [] }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    # A moldura da equipe (Fase 2) muda o texto da pergunta; a rajada não depende dela.
    Autonomia::Agents::Fase2.desligar!(account)
    freeze_time
    limpar_a_fala!
    responde_com('Claro, te ajudo.')
  end

  after { limpar_a_fala! }

  def limpar_a_fala!
    Redis::Alfred.delete(fala.chave_ocupada(conversation.id))
    Redis::Alfred.delete(fala.chave_do_fim(conversation.id))
  end

  def liga!(*chaves)
    agente_da_porta.update!(config: agente_da_porta.config.to_h.merge(chaves.index_with(true)))
  end

  # Local: a IA responde `texto` e a pergunta que ela recebeu fica em `perguntas`.
  def responde_com(texto)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |query:, **|
      perguntas << query
      resposta = instance_double(Autonomia::Agents::Answerer)
      allow(resposta).to receive(:answer).and_return(
        Autonomia::Agents::AnswerResult.new(reply: texto, confidence: 0.9, handoff: { should: false, reason: nil },
                                            used_knowledge: [], answered_from_knowledge: false, raw_reply: texto)
      )
      resposta
    end
  end

  # Local: o Responder do vínculo da porta, lido de novo (pega a opção ligada no agente).
  def responder_de(mensagem)
    vinculo = Autonomia::Agents::AgentInbox.find(vinculo_da_porta.id)
    described_class.new(conversation: conversation.reload, agent_inbox: vinculo, reply_to_message_id: mensagem.id)
  end

  def settle_direto(mensagem) = responder_de(mensagem).perform

  # Local: cada mensagem ganha um created_at estritamente maior (o relógio anda 1 s antes de criá-la). `recent_messages`
  # ordena só por created_at; com horários iguais a ordem seria indefinida no Postgres.
  def escreve(texto)
    travel 1.second
    cliente_escreve(texto)
  end

  def fala_do_agente(indice)
    travel 1.second
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing,
                     content: "pedaço #{indice}", content_attributes: { 'autonomia_chunk_index' => indice })
  end

  it 'com a opção, a pergunta é a rajada inteira' do
    liga!('conversa_espera_a_fala')
    escreve('quero cotar')
    escreve('pra Portugal')
    ultima = escreve('saio dia 02/02')

    settle_direto(ultima)

    expect(perguntas.sole).to eq("quero cotar\npra Portugal\nsaio dia 02/02")
  end

  it 'sem a opção, só a última' do
    escreve('quero cotar')
    ultima = escreve('pra Portugal')

    settle_direto(ultima)

    expect(perguntas.sole).to eq('pra Portugal')
  end

  # Review Focus 3. Pega: pergunta vazia ou a já respondida quando a mensagem nova cai entre os pedaços de uma fala.
  it 'com a opção, mensagem nova entre os pedaços: a pergunta é ela, não a respondida' do
    liga!('conversa_espera_a_fala')
    escreve('oi')
    fala_do_agente(0)
    nova = escreve('e pra 2 pessoas?')
    fala_do_agente(1)
    fala_do_agente(2)

    settle_direto(nova)

    expect(perguntas.sole).to eq('e pra 2 pessoas?')
  end

  it 'grava o fim previsto da fala ao responder, com o turno', :aggregate_failures do
    liga!('conversa_espera_a_fala')
    mensagem = escreve('oi')
    settle_direto(mensagem)

    fim = fala.fim_previsto(conversation.id)

    # 'Claro, te ajudo.' = 16 caracteres; folga de 10 ms para o arredondamento em milissegundos.
    expect(fim).to be_between(Time.current + ((16 * 0.128) - 0.01).seconds, Time.current + ((16 * 0.192) + 0.01).seconds)
    expect(Redis::Alfred.get(fala.chave_do_fim(conversation.id))).to start_with("#{mensagem.id}:")
  end

  it 'silêncio não grava fim previsto' do
    liga!('conversa_espera_a_fala')
    responde_com('conversation_closed_for_now')

    settle_direto(escreve('ok'))

    expect(fala.fim_previsto(conversation.id)).to be_nil
  end

  it 'sem a opção, não grava' do
    settle_direto(escreve('oi'))

    expect(fala.fim_previsto(conversation.id)).to be_nil
  end
end
