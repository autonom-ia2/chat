# "Um turno, uma ordem" (#1606): o caminho real do turno (gatilho, settle, Responder, entrega) com a IA dublada e os
# leitores do Multifunnel dublados pelo ADAPTADOR (Autonomia::Agents::ContratoDoFunil), nunca pela presença ou ausência
# da constante do CRM. Nada aqui chama rede nem IA real.
module UmTurnoHelper
  REPLY_JOB = 'Autonomia::Agents::Operate::ReplyJob'.freeze
  CHUNK_JOB = 'Autonomia::Agents::Operate::ChunkedDeliveryJob'.freeze

  def contrato
    Autonomia::Agents::ContratoDoFunil
  end

  # Padrão de cada exemplo: a regra do CRM diz que o turno não espera, não há marco e o funil não tem robô.
  def contrato!(ordem: false, marco: nil, robo: nil)
    allow(contrato).to receive(:ordem_do_turno?).and_return(ordem)
    allow(contrato).to receive(:decidido_ate).and_return(marco)
    allow(contrato).to receive(:robo_do_funil).and_return(robo)
  end

  # A IA responde "resposta de <agente>". `durante` roda no meio da chamada, com o agente que está respondendo: é onde
  # o dono muda, uma pessoa assume etc.
  def ia_responde!(durante: nil, texto: nil)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |agent:, **|
      resposta = double('Answerer') # rubocop:disable RSpec/VerifiedDoubles
      allow(resposta).to receive(:answer) do
        durante&.call(agent)
        Autonomia::Agents::AnswerResult.new(reply: texto || "Resposta de #{agent.name}.", confidence: 0.9,
                                            handoff: { should: false, reason: nil }, used_knowledge: [],
                                            answered_from_knowledge: false)
      end
      resposta
    end
  end

  def cliente_escreve(texto, conversa = conversation)
    create(:message, account: conversa.account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming,
                     content: texto)
  end

  def gatilho(mensagem, conversa = conversation)
    Autonomia::Agents::Operate::ReplyJob.perform_now(conversa.id, mensagem.id, 'trigger')
  end

  def settle(mensagem, posse = nil, conversa = conversation)
    Autonomia::Agents::Operate::ReplyJob.perform_now(conversa.id, mensagem.id, 'settle', posse)
  end

  def respostas(conversa = conversation)
    conversa.messages.outgoing.where(sender_type: 'AgentBot', private: false)
  end

  def jobs_de(classe)
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job].to_s == classe }
  end

  def settles_na_fila
    jobs_de(REPLY_JOB).select { |job| ActiveJob::Arguments.deserialize(job[:args])[2] == 'settle' }
  end

  # Roda só os jobs que estão na fila agora (os que eles enfileiram ficam para a próxima rodada), cada um na hora
  # marcada.
  def rodar_rodada!(classe = REPLY_JOB)
    jobs = jobs_de(classe)
    jobs.each do |job|
      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(job)
      travel_to(Time.zone.at(job[:at])) if job[:at] && Time.zone.at(job[:at]) > Time.current
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    jobs.size
  end

  # Roda a fila inteira, rodada a rodada, cada job na hora marcada. Teto contra laço.
  def rodar_turno!(classe = REPLY_JOB, teto: 15)
    rodadas = 0
    while jobs_de(classe).any?
      raise "fila de #{classe} não esvazia: laço?" if (rodadas += 1) > teto

      rodar_rodada!(classe)
    end
    rodadas
  end

  # O que o Sync do CRM faz ao trocar o dono: AssignmentService + o evento depois do commit.
  def trocar_dono!(robo, conversa = conversation)
    de = conversa.reload.ai_assignee
    Conversations::AssignmentService.new(conversation: conversa, assignee_id: robo.id, assignee_type: 'AgentBot').perform
    ActiveSupport::Notifications.instrument(Crm::Ai::ResponsibleAgentSync::EVENTO_TROCA,
                                            conversation: conversa, from_bot: de, to_bot: robo, agent: nil,
                                            transfer_id: nil, motivo: 'foco')
  end

  def limpar_posses!
    chaves = []
    Redis::Alfred.scan_each(match: 'autonomia:turno:*') { |chave| chaves << chave }
    chaves.each { |chave| Redis::Alfred.delete(chave) }
  end

  # Tudo o que as linhas do Operate e do turno escreveram no log durante o bloco.
  def linhas_do_log
    saida = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(saida)
    yield
    saida.string.lines
  ensure
    Rails.logger = original
  end
end

RSpec.configure do |config|
  config.include UmTurnoHelper, :um_turno
  config.after(:each, :um_turno) { limpar_posses! }
end
