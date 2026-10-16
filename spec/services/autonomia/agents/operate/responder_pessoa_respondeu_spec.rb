require 'rails_helper'

# #1669 (b): a Ana, da equipe, responde o cliente sem se atribuir. Se ela respondeu DEPOIS da mensagem do cliente que o
# turno vai responder, a IA não responde aquela mensagem (silêncio `pessoa_respondeu`) — antes da IA, sem gastar; durante
# a IA, descartando; na entrega em pedaços, parando a cadeia. A IA não sai da conversa: a próxima mensagem do cliente é
# dela. Sem a Fase 2, igual à main. O caminho é o real (gatilho, settle, Responder, entrega), com a IA dublada.
RSpec.describe Autonomia::Agents::Operate::Responder, :um_turno do
  include_context 'with crm responsible agent'

  let(:humanizado) { 'false' }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: humanizado, AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    clear_enqueued_jobs
  end

  def turno_do_cliente(texto = 'Meu boleto venceu, e agora?')
    cliente_escreve(texto).tap { |mensagem| gatilho(mensagem) }
  end

  def ana_responde(texto = 'Te mando a segunda via ainda hoje.', **extras)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing,
                     sender: ana, content: texto, **extras)
  end

  def silencios(linhas, motivo)
    linhas.grep(/\[autonomia\]\[operate\] silencio .*motivo=#{motivo}\b/)
  end

  it 'a Ana responde antes da IA: a IA fica calada e o modelo nem é chamado' do
    ia_responde!
    turno_do_cliente
    ana_responde

    linhas = linhas_do_log { rodar_turno! }

    expect(Autonomia::Agents::Answerer).not_to have_received(:new)
    expect(respostas).to be_empty
    expect(silencios(linhas, 'pessoa_respondeu').size).to eq(1)
  end

  it 'a Ana responde durante a IA: a resposta da IA é descartada' do
    ia_responde!(durante: ->(_agente) { ana_responde })
    turno_do_cliente

    linhas = linhas_do_log { rodar_turno! }

    expect(Autonomia::Agents::Answerer).to have_received(:new).once
    expect(respostas).to be_empty
    expect(silencios(linhas, 'pessoa_respondeu').size).to eq(1)
  end

  it 'a IA segue na conversa: a próxima mensagem do cliente, depois da resposta da Ana, é respondida pela IA' do
    ia_responde!
    turno_do_cliente
    ana_responde
    rodar_turno!
    expect(respostas).to be_empty

    turno_do_cliente('E o valor muda?')
    rodar_turno!

    expect(respostas.sole).to have_attributes(sender_id: porta.id, content: 'Resposta de Porta.')
    expect(conversation.reload.assignee).to be_nil
  end

  it 'nota privada da Ana não conta como resposta ao cliente' do
    ia_responde!
    turno_do_cliente
    ana_responde('Vou ver isso.', private: true)

    rodar_turno!

    expect(respostas.sole.content).to eq('Resposta de Porta.')
  end

  it 'mensagem de robô depois do cliente não cala a IA (só pessoa conta)' do
    ia_responde!
    turno_do_cliente
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing,
                     sender: create(:agent_bot, account: account), content: 'Mensagem automática de outro sistema.')

    rodar_turno!

    expect(respostas.where(sender_id: porta.id).sole.content).to eq('Resposta de Porta.')
  end

  it 'regra de automação gravada em nome da Ana não conta como ela respondendo' do
    ia_responde!
    turno_do_cliente
    ana_responde('Recebemos sua mensagem.', content_attributes: { 'automation_rule_id' => 1 })

    rodar_turno!

    expect(respostas.sole.content).to eq('Resposta de Porta.')
  end

  {
    'follow-up do CRM' => { content_attributes: { 'crm_follow_up_id' => 7 } },
    'convite/lembrete do Agendamento' => { content_attributes: { 'crm_booking_invite_id' => 3 } },
    'aviso do Agendamento' => { content_attributes: { 'crm_booking_notice' => true } },
    'campanha' => { additional_attributes: { 'campaign_id' => 9 } },
    'campanha da API do WhatsApp' => { additional_attributes: { 'whatsapp_api_campaign_id' => 9 } }
  }.each do |envio, marcas|
    it "#{envio} gravado em nome da Ana não cala a IA" do
      ia_responde!
      turno_do_cliente
      ana_responde('Lembrete automático.', **marcas)

      rodar_turno!

      expect(respostas.sole.content).to eq('Resposta de Porta.')
    end
  end

  it 'mensagem da Ana que falhou no envio não cala a IA (o cliente não a recebeu)' do
    ia_responde!
    turno_do_cliente
    ana_responde.update!(status: :failed)

    rodar_turno!

    expect(respostas.sole.content).to eq('Resposta de Porta.')
  end

  it 'retry com a resposta já postada e a Ana respondendo durante a IA: é "já respondido", não silêncio da pessoa' do
    mensagem = cliente_escreve('Meu boleto venceu, e agora?')
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: porta,
                     content: 'Resposta anterior.', content_attributes: { autonomia_reply_to_message_id: mensagem.id })
    ia_responde!(durante: ->(_agente) { ana_responde })

    resultado = nil
    linhas = linhas_do_log do
      resultado = described_class.new(conversation: conversation, agent_inbox: vinculo_da_porta,
                                      reply_to_message_id: mensagem.id).perform
    end

    expect(resultado).to have_attributes(status: :replied, message: nil)
    expect(silencios(linhas, 'pessoa_respondeu')).to be_empty
  end

  describe 'resposta descartada pela pessoa depois da IA: consulta e handoff' do
    let(:despachante) { instance_double(Autonomia::Agents::Tools::AsyncDispatcher, dispatch!: 1, discard!: nil) }

    before do
      allow(Autonomia::Agents::Tools::AsyncDispatcher).to receive(:new).and_return(despachante)
      allow_any_instance_of(Autonomia::Agents::Tools::Delivery).to receive(:any_runs?).and_return(true) # rubocop:disable RSpec/AnyInstance
      allow(Autonomia::Agents::Operate::EventLogger).to receive(:handed_off)
      allow(Autonomia::Agents::Answerer).to receive(:new) do
        durante&.call
        resultado = Autonomia::Agents::AnswerResult.new(reply: 'Vou passar para a equipe.', confidence: 0.9,
                                                        handoff: { should: true, reason: 'pedido' }, used_knowledge: [],
                                                        answered_from_knowledge: false)
        instance_double(Autonomia::Agents::Answerer, answer: resultado)
      end
    end

    def responder_agora
      mensagem = cliente_escreve('Quero cotar e falar com alguém')
      described_class.new(conversation: conversation, agent_inbox: vinculo_da_porta, reply_to_message_id: mensagem.id).perform
    end

    context 'when a Ana responde durante a IA' do
      let(:durante) { -> { ana_responde } }

      it 'a consulta segue sem o aviso de começo ao cliente, e o handoff pedido pela IA não roda' do
        responder_agora

        expect(despachante).to have_received(:dispatch!).with(replied: true, expected_chunks: 0)
        expect(Autonomia::Agents::Operate::EventLogger).not_to have_received(:handed_off)
        expect(conversation.reload.ai_assignee).to eq(porta)
      end
    end

    context 'when a Ana se atribui durante a IA (contraprova do aviso: outro silêncio avisa, como hoje)' do
      let(:durante) { -> { conversation.update!(assignee: ana) } }

      it 'a consulta segue com o aviso de começo (replied: false)' do
        responder_agora

        expect(despachante).to have_received(:dispatch!).with(replied: false, expected_chunks: 0)
      end
    end

    context 'when ninguém da equipe responde (contraprova)' do
      let(:durante) { nil }

      it 'a resposta sai e o handoff pedido pela IA roda, como sempre' do
        responder_agora

        expect(despachante).to have_received(:dispatch!).with(replied: true, expected_chunks: 0)
        expect(Autonomia::Agents::Operate::EventLogger).to have_received(:handed_off)
      end
    end
  end

  describe 'sem a Fase 2' do
    before { Autonomia::Agents::Fase2.desligar!(account) }

    it 'igual à main: a Ana responde antes da IA e a IA responde mesmo assim' do
      ia_responde!
      turno_do_cliente
      ana_responde

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas.sole.content).to eq('Resposta de Porta.')
      expect(silencios(linhas, 'pessoa_respondeu')).to be_empty
    end

    it 'igual à main: a Ana responde durante a IA e a IA responde mesmo assim' do
      ia_responde!(durante: ->(_agente) { ana_responde })
      turno_do_cliente

      rodar_turno!

      expect(respostas.sole.content).to eq('Resposta de Porta.')
    end
  end

  describe 'resposta em áudio (deliver_voice)' do
    it 'a Ana responde durante a IA: nem o áudio nem o texto de reserva saem' do
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(described_class).to receive(:voice_reply_applies?).and_return(true)
      allow_any_instance_of(described_class).to receive(:synthesize_audio).and_return(nil)
      # rubocop:enable RSpec/AnyInstance
      ia_responde!(durante: ->(_agente) { ana_responde })
      turno_do_cliente

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas).to be_empty
      expect(silencios(linhas, 'pessoa_respondeu').size).to eq(1)
    end
  end

  describe 'entrega em pedaços (humanizada)' do
    let(:humanizado) { 'true' }
    let(:texto_longo) do
      ['Primeiro ponto: confirmei aqui o seu cadastro e está tudo certo com ele, sem pendência.',
       'Segundo ponto: a segunda via do boleto sai hoje à tarde, com o mesmo valor de antes.',
       'Terceiro ponto: se quiser pagar por Pix, me avise ainda hoje por aqui mesmo.'].join("\n\n")
    end

    it 'o texto vira mais de um pedaço (senão os cenários não testam a cadeia)' do
      expect(Autonomia::Agents::Operate::ReplyChunker.call(texto_longo).size).to be >= 2
    end

    it 'a Ana responde durante a IA: a cadeia nem começa' do
      ia_responde!(texto: texto_longo, durante: ->(_agente) { ana_responde })
      turno_do_cliente

      linhas = linhas_do_log do
        rodar_turno!
        rodar_turno!(UmTurnoHelper::CHUNK_JOB)
      end

      expect(respostas).to be_empty
      expect(silencios(linhas, 'pessoa_respondeu').size).to eq(1)
    end

    it 'a Ana responde depois da IA e antes do 1º pedaço: nenhum pedaço sai' do
      ia_responde!(texto: texto_longo)
      turno_do_cliente
      rodar_turno! # a IA responde e agenda a cadeia
      ana_responde

      linhas = linhas_do_log { rodar_turno!(UmTurnoHelper::CHUNK_JOB) }

      expect(respostas).to be_empty
      expect(linhas.grep(/motivo=pessoa_respondeu pedaco=0/).size).to eq(1)
      expect(jobs_de(UmTurnoHelper::REPLY_JOB)).to be_empty
    end

    it 'a Ana responde no meio da cadeia: o resto não sai' do
      ia_responde!(texto: texto_longo)
      turno_do_cliente
      rodar_turno!
      rodar_rodada!(UmTurnoHelper::CHUNK_JOB) # 1º pedaço
      expect(respostas.count).to eq(1)
      ana_responde

      linhas = linhas_do_log { rodar_turno!(UmTurnoHelper::CHUNK_JOB) }

      expect(respostas.count).to eq(1)
      expect(linhas.grep(/motivo=pessoa_respondeu pedaco=1/).size).to eq(1)
    end

    it 'sem a Fase 2, igual à main: a cadeia inteira sai mesmo com a Ana respondendo' do
      Autonomia::Agents::Fase2.desligar!(account)
      ia_responde!(texto: texto_longo)
      turno_do_cliente
      rodar_turno!
      ana_responde

      rodar_turno!(UmTurnoHelper::CHUNK_JOB)

      expect(respostas.count).to eq(Autonomia::Agents::Operate::ReplyChunker.call(texto_longo).size)
    end
  end
end
