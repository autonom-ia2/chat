# "Um turno, uma ordem" (#1606, ponto 2): o dono da conversa mudou no meio de um turno, então o turno é refeito pelo
# dono novo em vez de morrer calado. Dois caminhos chegam aqui, e só um enfileira (PosseDoTurno, SET NX por destino):
# - :responder     — o Responder do dono antigo viu, com estado fresco, que outro vínculo ativo da caixa virou dono;
# - :evento_troca  — o `crm.ai.responsible_agent_changed` (Sync do CRM e PassarParaIa), depois do commit.
#
# Só refaz o turno que ainda está em andamento: a última mensagem pública é do cliente e é a que a marca do debounce
# aponta. Pelo :responder, sem prazo: quem chama está com o turno na mão, depois da IA, que pode passar da janela do
# debounce. Pelo :evento_troca, a troca chega a qualquer hora, então só turno recente (AgentInbox#turno_em_andamento?).
# Pessoa atribuída, agente que não pode responder, conta fora da Fase 2: nada a refazer.
class Autonomia::Agents::Operate::ReenfileirarTurno
  ORIGENS = %i[responder evento_troca].freeze

  # O assinante do evento de troca (config/initializers/autonomia_turno.rb). A Fase 2 vem antes de qualquer leitura: conta
  # fora dela não consulta nem a última mensagem.
  def self.ao_trocar_dono(payload)
    conversation = payload.to_h[:conversation]
    return if conversation.blank?
    return false unless fase2?(conversation.account)

    ultima = ultima_mensagem_publica(conversation)
    return unless ultima&.incoming?

    call(conversation: conversation, message_id: ultima.id, origem: :evento_troca)
  # Roda depois do commit de quem trocou o dono (o Sync do CRM, o PassarParaIa), dentro do instrument dele: propagar não
  # desfaz a troca já gravada, só derrubaria quem chamou e os outros assinantes do evento. Fica no log e no rastreador.
  rescue StandardError => e
    Rails.logger.warn("[autonomia][turno] reenfileirar_falhou conv=#{conversation&.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: conversation&.account).capture_exception
    nil
  end

  def self.fase2?(account)
    ::Autonomia::Agents::Config.enabled?(account) && ::Autonomia::Agents::Fase2.ligada?(account)
  end

  def self.ultima_mensagem_publica(conversation)
    conversation.messages.where(private: false, message_type: %i[incoming outgoing]).reorder(:created_at, :id).last
  end

  # `quem_perdeu`: o vínculo que perdeu o turno (caminho :responder); a posse dele é solta.
  def self.call(conversation:, message_id:, origem:, quem_perdeu: nil)
    new(conversation, message_id, origem, quem_perdeu).call
  end

  def initialize(conversation, message_id, origem, quem_perdeu)
    raise ArgumentError, "origem fora da lista: #{origem}" unless ORIGENS.include?(origem)

    @conversation = conversation
    @message_id = message_id.to_i
    @origem = origem
    @quem_perdeu = quem_perdeu
  end

  # -> true quando enfileirou o turno para o dono novo.
  def call
    return false unless @message_id.positive? && self.class.fase2?(@conversation.account)

    soltar_posse_de_quem_perdeu
    destino = ::Autonomia::Agents::Operate.eligible_agent_inbox(@conversation.reload)
    return false unless destino && turno_em_andamento?(destino)
    return barrado(destino) unless ::Autonomia::Agents::Operate::PosseDoTurno.tomar?(@conversation.id, @message_id, destino.id)

    enfileirar(destino)
    true
  end

  private

  def soltar_posse_de_quem_perdeu
    ::Autonomia::Agents::Operate::PosseDoTurno.soltar(@conversation.id, @message_id, @quem_perdeu.id) if @quem_perdeu
  end

  def turno_em_andamento?(destino)
    ultima = self.class.ultima_mensagem_publica(@conversation)
    return false unless ultima&.id == @message_id && ultima.incoming?
    return ::Autonomia::Agents::Operate::ReplyJob.turno_pendente?(@conversation, @message_id) if @origem == :responder

    destino.turno_em_andamento?(@conversation, ultima)
  end

  def barrado(destino)
    telemetria(:reenfileiramento_barrado, destino)
    false
  end

  # Depois do commit: chamado de dentro do lock do Responder, o settle novo não pode ler a conversa antes de a
  # transação de quem chamou terminar. Leva a posse junto: o settle enfileirado já é o dono deste turno.
  def enfileirar(destino)
    telemetria(:turno_reenfileirado, destino)
    conversation_id = @conversation.id
    message_id = @message_id
    ActiveRecord.after_all_transactions_commit do
      ::Autonomia::Agents::Operate::ReplyJob.perform_later(conversation_id, message_id, 'settle', destino.id)
    end
  end

  def telemetria(evento, destino)
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(evento, conversation_id: @conversation.id, msg: @message_id,
                                                                      origem: @origem, agent_inbox: destino.id)
  end
end
