require 'rails_helper'

# #1630: uma pessoa passa a conversa para um agente de IA (PassarParaIa, `por: :pessoa`) e o agente que recebe lê tudo e
# decide se fala ou fica calado, num turno próprio, sem mensagem nova do cliente. Caminho real (passagem, evento, fila,
# Responder, entrega) e registro real das passagens; só a IA é dublada.
RSpec.describe Autonomia::Agents::Operate::AoReceberPassagem, :um_turno do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }
  let(:pedidos) { [] }
  let(:vinculo_area) { Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox) }
  let(:resposta_da_ia) { 'Oi, Joana! Sou da Área Suporte e sigo daqui.' }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    ligar!
    clear_enqueued_jobs
  end

  def ligar!(valor: true)
    account.update!(internal_attributes: account.internal_attributes.to_h.merge(described_class::LIGADA_KEY => valor))
  end

  # A IA dublada guarda o que recebeu (para conferir o contexto e o histórico) e responde `resposta_da_ia`.
  # `durante` roda no meio da chamada (quem escreve durante a IA); `passar_a_humanos` é o pedido de handoff do modelo.
  def ia_grava!(texto = nil, durante: nil, passar_a_humanos: false)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      pedidos << kwargs
      resposta = instance_double(Autonomia::Agents::Answerer)
      allow(resposta).to receive(:answer) do
        durante&.call
        Autonomia::Agents::AnswerResult.new(reply: texto || resposta_da_ia, confidence: 0.9, used_knowledge: [],
                                            handoff: { should: passar_a_humanos, reason: nil }, answered_from_knowledge: false)
      end
      resposta
    end
  end

  def ana_escreve(texto, **extras)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: ana,
                     content: texto, **extras)
  end

  # :pessoa — a Ana se atribui e passa; :crm — a Atribuição tira da porta (o robô); :ia — o agente da porta passa.
  def ana_passa!(agente = area, por: :pessoa)
    conversation.update!(assignee: ana) if por == :pessoa && conversation.reload.assignee_id.nil?
    origem = { pessoa: ana, crm: porta, ia: agente_da_porta }.fetch(por)
    Autonomia::Agents::PassarParaIa.call(conversation: conversation.reload, agent: agente, por: por, motivo: 'tela',
                                         origem: origem, pedida_por: por == :pessoa ? ana : nil)
  end

  def turnos_da_passagem
    jobs_de(UmTurnoHelper::REPLY_JOB).select { |job| ActiveJob::Arguments.deserialize(job[:args])[2] == described_class::FASE }
  end

  def silencios(linhas, motivo)
    linhas.grep(/\[autonomia\]\[operate\] silencio .*motivo=#{motivo}\b/)
  end

  def contexto
    pedidos.last[:contexto_do_turno].to_s
  end

  describe 'o turno da passagem' do
    before { ia_grava! }

    it 'exemplo 1: o cliente pediu e a Ana passou sem escrever: o agente responde uma vez, ancorado na passagem' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      linhas = linhas_do_log { ana_passa! }

      expect(turnos_da_passagem.size).to eq(1)
      rodar_turno!

      passagem = Crm::Passagens.ultima_aberta(conversation)
      expect(respostas.sole).to have_attributes(sender_id: espelho_area.id, content: resposta_da_ia)
      expect(respostas.sole.content_attributes['autonomia_passagem_id']).to eq(passagem.id)
      expect(linhas.grep(/turno_da_passagem conv=#{conversation.id} passagem=#{passagem.id}/).size).to eq(1)
      expect(contexto).to include('Ana Souza', 'passou esta conversa para você',
                                  'não assuma como suas as promessas', '`conversation_closed_for_now`')
    end

    it 'o evento repetido não abre outro turno (SET NX por passagem), e o mesmo job rodando de novo não posta de novo' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      job = turnos_da_passagem.sole
      described_class.abrir(conversation)
      expect(turnos_da_passagem.size).to eq(1)

      rodar_turno!
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))

      expect(respostas.count).to eq(1)
    end

    it 'exemplo 3: o modelo decide calar com o sinal: nada é postado e a telemetria registra' do
      ia_grava!('conversation_closed_for_now')
      cliente_escreve('Obrigado!')
      ana_passa!

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas).to be_empty
      expect(silencios(linhas, 'sinal').size).to eq(1)
      expect(linhas.grep(/sinal_na_passagem conv=#{conversation.id}/).size).to eq(1)
    end

    it 'nota privada nunca vai ao modelo; o que a Ana escreveu em público vai, marcado como dela' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_escreve('Cliente pediu 10% de desconto, não oferecer', private: true)
      ana_escreve('Vou te passar para nossa especialista.')
      ana_passa!

      rodar_turno!

      enviado = pedidos.last.values_at(:query, :history, :contexto_do_turno).to_s
      expect(enviado).not_to include('10% de desconto')
      expect(enviado).to include('Vou te passar para nossa especialista.')
    end

    it 'o cliente escreve antes de o turno rodar: o turno da passagem desiste e o turno da mensagem responde, com o contexto' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      turno = turnos_da_passagem.sole
      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(turno)
      travel 1.second
      mensagem = cliente_escreve('Alguém aí?')
      gatilho(mensagem)

      linhas = linhas_do_log do
        turno[:job].perform_now(*ActiveJob::Arguments.deserialize(turno[:args]))
        rodar_turno!
      end

      expect(silencios(linhas, 'cliente_escreveu').size).to eq(1)
      expect(respostas.sole.content_attributes['autonomia_reply_to_message_id']).to eq(mensagem.id)
      expect(contexto).to include('Ana Souza', 'passou esta conversa para você')
      expect(contexto).not_to include('conversation_closed_for_now')
    end

    it 'a Ana escreve de novo depois da passagem: a IA fica calada (ela está atendendo) e o modelo nem é chamado' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      travel 1.second
      ana_escreve('Ah, só mais uma coisa: a vistoria é amanhã.')

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas).to be_empty
      expect(pedidos).to be_empty
      expect(silencios(linhas, 'pessoa_respondeu').size).to eq(1)
    end

    it 'depois que o agente falou, o turno normal seguinte não recebe mais o contexto da passagem' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      rodar_turno!
      travel 1.second
      mensagem = cliente_escreve('Beleza, obrigado.')
      gatilho(mensagem)

      rodar_turno!

      expect(respostas.count).to eq(2)
      expect(contexto).not_to include('passou esta conversa para você')
    end
  end

  describe 'todas as passagens: pela Atribuição do CRM e por outro agente' do
    before { ia_grava! }

    it ':crm — a Atribuição passa com a pergunta do cliente sem resposta: o agente responde, e o contexto diz "a Atribuição"' do
      cliente_escreve('Vocês abrem sábado?')

      expect(ana_passa!(por: :crm).codigo).to eq(:passou)
      expect(turnos_da_passagem.size).to eq(1)
      rodar_turno!

      expect(respostas.sole).to have_attributes(sender_id: espelho_area.id)
      expect(contexto).to include('A Atribuição do CRM passou esta conversa para você', 'quem atendia antes')
      expect(contexto).not_to include('Ana Souza', 'Uma pessoa da equipe')
    end

    it ':ia — outro agente passa: o contexto diz o nome do agente, sem pessoa' do
      cliente_escreve('Quero falar com o suporte.')

      expect(ana_passa!(por: :ia).codigo).to eq(:passou)
      rodar_turno!

      expect(respostas.sole).to have_attributes(sender_id: espelho_area.id)
      expect(contexto).to include('O agente Porta passou esta conversa para você', '`conversation_closed_for_now`')
      expect(contexto).not_to include('Uma pessoa da equipe')
    end

    it ':crm — o turno normal logo depois recebe o contexto da Atribuição, sem o sinal de silêncio' do
      expect(ana_passa!(por: :crm).codigo).to eq(:passou)
      clear_enqueued_jobs
      gatilho(cliente_escreve('Quero falar com o suporte.'))

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(contexto).to include('A Atribuição do CRM passou esta conversa para você')
      expect(contexto).not_to include('conversation_closed_for_now')
    end

    it 'a Lia não recebe o turno da passagem também por :crm e :ia' do
      lia = criar_agente('Lia', agent_type: 'insurance_quote')
      Autonomia::Agents::Areas.vincular!(agent: lia, inbox: inbox)
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')

      expect(ana_passa!(lia, por: :crm).codigo).to eq(:passou)
      expect(ana_passa!(area, por: :ia).codigo).to eq(:passou) # Porta → Área, de volta a uma página: abre
      expect(turnos_da_passagem.size).to eq(1)
      expect(ActiveJob::Arguments.deserialize(turnos_da_passagem.sole[:args]).last).to eq(vinculo_area.id)
    end
  end

  describe 'turno da passagem que falha' do
    before { cliente_escreve('Quero cotar o seguro do meu Onix 2022.') }

    def chaves_da_passagem(passagem, mensagem)
      [described_class.chave(passagem.id),
       Autonomia::Agents::Operate::PosseDoTurno.chave(conversation.id, mensagem.id, vinculo_area.id)]
    end

    it 'IA fora: solta a chave da passagem e a posse da última mensagem, sem reenfileirar; um evento futuro pode tentar' do
      ia_grava!('')
      ana_passa!
      passagem = Crm::Passagens.ultima_aberta(conversation)

      linhas = linhas_do_log { rodar_turno! }

      expect(silencios(linhas, 'vazio').size).to eq(1)
      expect(chaves_da_passagem(passagem, conversation.messages.incoming.last).map { |chave| Redis::Alfred.exists?(chave) })
        .to eq([false, false])
      expect(jobs_de(UmTurnoHelper::REPLY_JOB)).to be_empty
      expect(described_class.abrir(conversation)).to be(true)
    end

    it 'exceção no turno: também solta a chave da passagem' do
      allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(StandardError, 'boom')
      ana_passa!
      passagem = Crm::Passagens.ultima_aberta(conversation)

      rodar_turno!

      expect(Redis::Alfred.exists?(described_class.chave(passagem.id))).to be(false)
      expect(respostas).to be_empty
    end

    it 'o turno que decidiu (respondeu ou calou) mantém a chave: a mesma passagem não abre de novo' do
      ia_grava!('conversation_closed_for_now')
      ana_passa!

      rodar_turno!

      expect(described_class.abrir(conversation)).to be(false)
    end
  end

  describe 'guardas do turno da passagem' do
    before do
      ia_grava!
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
    end

    it 'o cliente escreve durante a IA: a resposta da passagem é descartada (responde o turno da mensagem nova)' do
      ia_grava!(durante: -> { cliente_escreve('Alguém aí?') })
      ana_passa!

      linhas = linhas_do_log { rodar_rodada! }

      expect(respostas).to be_empty
      expect(silencios(linhas, 'turno_superado').size).to eq(1)
    end

    it 'a Ana escreve durante a IA: a resposta da passagem é descartada' do
      ia_grava!(durante: -> { ana_escreve('Esqueci: a vistoria é amanhã.') })
      ana_passa!

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas).to be_empty
      expect(silencios(linhas, 'pessoa_respondeu').size).to eq(1)
    end

    it 'a chave da conta desligada entre enfileirar e rodar: o turno não roda' do
      ana_passa!
      ligar!(valor: false)

      rodar_turno!

      expect(pedidos).to be_empty
      expect(respostas).to be_empty
    end

    it 'fora do horário/público do agente: só cala, sem devolver a conversa a humanos' do
      allow(Autonomia::Agents::Operate::EngagementGate).to receive(:new)
        .and_return(instance_double(Autonomia::Agents::Operate::EngagementGate, blocked_reason: 'schedule'))
      ana_passa!

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas).to be_empty
      expect(silencios(linhas, 'fora_do_engajamento').size).to eq(1)
      expect(conversation.reload).to have_attributes(ai_assignee: espelho_area, bot_handoff_waiting?: false)
    end

    it 'o modelo pede passar a humanos: a resposta sai, mas a conversa fica com o agente' do
      ia_grava!(passar_a_humanos: true)
      ana_passa!

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(conversation.reload).to have_attributes(ai_assignee: espelho_area, bot_handoff_waiting?: false)
    end

    it 'o settle atrasado da última mensagem do cliente não responde depois do turno da passagem (uma resposta só)' do
      mensagem = conversation.messages.incoming.last
      gatilho(mensagem) # a porta marcou o debounce; o settle dela fica preso na fila
      clear_enqueued_jobs
      travel 10.minutes # passou da janela: a troca de dono não refaz o turno
      ana_passa!
      expect(turnos_da_passagem.size).to eq(1)
      rodar_turno!

      linhas = linhas_do_log { settle(mensagem) }

      expect(respostas.count).to eq(1)
      expect(linhas.grep(/turno_em_curso conv=#{conversation.id} msg=#{mensagem.id}/).size).to eq(1)
    end

    it 'o settle da última mensagem chegou antes: o turno da passagem desiste' do
      mensagem = conversation.messages.incoming.last
      ana_passa!
      Autonomia::Agents::Operate::PosseDoTurno.tomar?(conversation.id, mensagem.id, vinculo_area.id, dono: 'job-do-settle')

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas).to be_empty
      expect(silencios(linhas, 'turno_em_curso').size).to eq(1)
    end

    it 'passada a janela do contexto, o turno normal não recebe mais o contexto da passagem' do
      ia_grava!('conversation_closed_for_now')
      ana_passa!
      rodar_turno!
      travel described_class::JANELA_DO_CONTEXTO + 1.minute
      ia_grava!
      gatilho(cliente_escreve('Voltei, e aí?'))

      rodar_turno!

      expect(contexto).not_to include('passou esta conversa para você')
    end
  end

  describe 'quando o turno da passagem não abre' do
    before { ia_grava! }

    it 'a Lia (insurance_quote) fica de fora: nada de turno da passagem nem de contexto' do
      lia = criar_agente('Lia', agent_type: 'insurance_quote')
      Autonomia::Agents::Areas.vincular!(agent: lia, inbox: inbox)
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')

      expect(ana_passa!(lia).codigo).to eq(:passou)

      expect(turnos_da_passagem).to be_empty
      expect(Redis::Alfred.exists?(described_class.chave(Crm::Passagens.ultima_aberta(conversation).id))).to be(false)
    end

    it 'com a chave da conta desligada, tudo como antes: nenhum turno, nenhuma leitura da passagem' do
      ligar!(valor: false)
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      allow(Crm::Passagens).to receive(:ultima_aberta).and_call_original

      ana_passa!
      rodar_turno!

      expect(turnos_da_passagem).to be_empty
      expect(respostas).to be_empty
      expect(Crm::Passagens).not_to have_received(:ultima_aberta)
    end

    it 'sem a Fase 2, a chave da conta sozinha não liga nada' do
      Autonomia::Agents::Fase2.desligar!(account)

      expect(described_class.ligada?(account.reload)).to be(false)
    end

    it 'outra passagem antes de o turno rodar: o turno da passagem antiga não fala por ninguém' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      antigo = turnos_da_passagem.sole
      clear_enqueued_jobs
      conversation.update!(assignee: ana)
      ana_passa!(agente_da_porta)

      antigo[:job].perform_now(*ActiveJob::Arguments.deserialize(antigo[:args]))

      expect(respostas).to be_empty
    end

    it 'troca de dono sem `por` (Sync do CRM, robô do n8n) não abre o turno da passagem' do
      cliente_escreve('Quero falar com o suporte.')

      trocar_dono!(espelho_area)

      expect(turnos_da_passagem).to be_empty
    end

    it 'evento de troca sem `por`, mesmo com passagem aberta para o agente: não abre o turno da passagem' do
      cliente_escreve('Quero falar com o suporte.')
      Crm::Passagens.registrar!(conversation: conversation, de: porta, para: area, pedida_por: nil, motivo: 'tela')

      trocar_dono!(espelho_area)

      expect(Crm::Passagens.ultima_aberta(conversation).para_id).to eq(area.id)
      expect(turnos_da_passagem).to be_empty
    end

    it 'turno do cliente em andamento quando a Ana passa: refaz o turno da mensagem e não abre outro (uma resposta só)' do
      mensagem = cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      gatilho(mensagem) # a porta marcou o debounce
      conversation.update!(assignee: ana)
      ana_passa!

      expect(turnos_da_passagem).to be_empty
      rodar_turno!

      expect(respostas.sole).to have_attributes(sender_id: espelho_area.id)
      expect(contexto).to include('passou esta conversa para você')
    end
  end
end
