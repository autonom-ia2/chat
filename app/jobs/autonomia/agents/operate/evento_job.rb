# O TURNO DA LIA ACIONADO POR UM EVENTO DA COTAÇÃO (PR C). Quem dispara é `Tools::Evento.disparar`, que já
# adquiriu o slot da execução; aqui o evento vira palavra, e a palavra é do modelo.
#
# A ORDEM, antes de falar (cada espera é um reagendamento curto, com teto):
#   - a cadeia de entrega humanizada do turno que abriu a execução (`Tools::CadeiaDoTurno`), até
#     `MAX_PUBLISH_DEFERRALS`: falar no meio da frase que a Lia ainda está "digitando" embaralha a conversa;
#   - no evento de FECHO, a palavra do evento de começo e os arquivos aceitos que ainda não são mensagem (o
#     comparativo adiado; `depois_de` traz o que o encerramento adiou sem conseguir registrar o aceite), até
#     `MAX_DEPENDENCY_DEFERRALS`: a conclusão sai depois do PDF, e o desfecho não passa na frente do "estou
#     cuidando".
#
# FALHA DO TURNO (IA falhou, resposta vazia): UMA nova tentativa, com espera. Falhou de novo: o atendente é
# avisado pela notificação do Chatwoot (`bot_handoff!`) e por uma NOTA PRIVADA com o evento. O SINAL DE SILÊNCIO
# não é falha: é a Lia decidindo não falar (a pessoa se despediu, por exemplo). Só a nota privada, sem escalar
# (revisão da chat#588).
# Conversa com humano no comando, ou agente que deixou de poder falar: o modelo não roda, só a nota privada.
# Nunca frase pronta ao cliente.
#
# Execução MORTA (supersedida por um pedido novo, descartada, barrada pelo gate da conta) não aciona turno: o
# cliente já está noutro pedido.
class Autonomia::Agents::Operate::EventoJob < ApplicationJob
  queue_as :medium

  AsyncConfig = ::Autonomia::Agents::Tools::AsyncConfig
  # A espera antes da segunda tentativa: a falha de IA mais comum aqui é passageira (limite de taxa, timeout).
  ESPERA_DA_NOVA_TENTATIVA = 30.seconds
  TENTATIVAS = 2
  # A conclusão sem o arquivo sai com a marca de `valores_guardados` (`sem_o_arquivo`): o retry, ou o começo
  # atrasado, precisa reconhecer as duas marcas (revisão da chat#588).
  MARCAS_DO_TIPO = { 'concluida' => %w[concluida valores_guardados] }.freeze

  def perform(run_id, tipo, adiamentos = 0, tentativa = 0, depois_de = [])
    run = ::Autonomia::Agents::ToolRun.find_by(id: run_id)
    return if run.blank?

    evento = ::Autonomia::Agents::Tools::Evento.new(run: run, tipo: tipo)
    motivo = sem_turno(evento)
    return anotar(run, tipo, motivo) if motivo

    conversation = run.conversation
    passo = { adiamentos: adiamentos.to_i, tentativa: tentativa.to_i, depois_de: Array(depois_de).map(&:to_s) }
    return adiar(evento, passo) if esperar?(evento, conversation, passo)
    return anotar(run, tipo, 'comeco_superado') if comeco_superado?(evento, conversation)
    return anotar(run, tipo, 'ja_publicado') if ja_falou?(run, tipo, conversation)

    falar(sem_o_arquivo(evento, conversation, passo), conversation, passo)
  end

  private

  def ja_falou?(run, tipo, conversation)
    MARCAS_DO_TIPO.fetch(tipo.to_s, [tipo.to_s]).any? do |marca|
      ::Autonomia::Agents::Tools::Evento.new(run: run, tipo: marca).publicado?(conversation)
    end
  end

  # -> por que este evento não aciona turno nenhum, ou nil.
  def sem_turno(evento)
    return 'tipo_desconhecido' unless evento.valido?
    return 'execucao_morta' if evento.run.dead?

    'sem_conversa' if evento.run.conversation.blank?
  end

  def falar(evento, conversation, passo)
    agent_inbox = vinculo(evento.run, conversation)
    return aviso(evento).notar('inelegivel') if agent_inbox.nil?

    resultado = ::Autonomia::Agents::Operate::ResponderAoEvento.new(conversation: conversation, agent_inbox: agent_inbox,
                                                                    evento: evento).perform
    return anotar(evento.run, evento.tipo, 'falou') if resultado.status == :replied
    return aviso(evento).notar('inelegivel') if resultado.error == 'nao_elegivel'
    return aviso(evento).notar('silencio') if resultado.error == 'sinal'

    tentar_de_novo_ou_escalar(evento, agent_inbox, passo, resultado.error)
  end

  def tentar_de_novo_ou_escalar(evento, agent_inbox, passo, motivo)
    if passo[:tentativa] + 1 < TENTATIVAS
      anotar(evento.run, evento.tipo, "nova_tentativa causa=#{motivo.presence || '-'}")
      return reagendar(evento, passo.merge(tentativa: passo[:tentativa] + 1), ESPERA_DA_NOVA_TENTATIVA)
    end

    anotar(evento.run, evento.tipo, "escalado causa=#{motivo.presence || '-'}")
    aviso(evento).escalar(agent_inbox)
  end

  # O vínculo que pode falar AGORA: o contrato inteiro do atendimento (sem responsável, agente ligado e ativo,
  # allowlist) e o MESMO vínculo que aceitou a execução. nil em qualquer outro caso.
  def vinculo(run, conversation)
    agent_inbox = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation.reload)
    return nil if agent_inbox.nil? || agent_inbox.autonomia_agent_id != run.autonomia_agent_id
    return nil if run.agent_inbox_id.present? && run.agent_inbox_id != agent_inbox.id

    agent_inbox
  end

  def esperar?(evento, conversation, passo)
    adiamentos = passo[:adiamentos]
    cadeia_aberta = adiamentos < AsyncConfig::MAX_PUBLISH_DEFERRALS && ::Autonomia::Agents::Tools::CadeiaDoTurno.aberta?(evento.run, conversation)
    return true if cadeia_aberta
    return false if evento.comeco? || adiamentos >= AsyncConfig::MAX_DEPENDENCY_DEFERRALS

    comeco_sem_palavra?(evento.run, conversation) || arquivo_a_caminho?(evento.run, conversation, passo[:depois_de])
  end

  # O "ESTOU CUIDANDO" DEPOIS DO RESULTADO NÃO SAI (revisão da chat#588). O começo que atrasou (nova tentativa,
  # fila) não fala se o desfecho já falou ou se algum arquivo aceito já chegou à conversa. Só DISPARADO não basta:
  # o fecho espera a palavra do começo (`comeco_sem_palavra?`), e os dois esperariam um pelo outro.
  def comeco_superado?(evento, conversation)
    evento.comeco? && resultado_na_conversa?(evento.run, conversation)
  end

  def resultado_na_conversa?(run, conversation)
    fecho = run.handle.to_h[::Autonomia::Agents::Tools::Evento::FECHO_KEY].presence
    return true if fecho && ja_falou?(run, fecho, conversation)

    aceitos(run).any? { |token| ::Autonomia::Agents::Tools::EntregaPublicada.para(conversation, token).present? }
  end

  # O COMPARATIVO QUE NÃO CHEGOU NÃO É AFIRMADO (revisão da chat#588). Estourado o teto de espera com o arquivo
  # ainda ausente, a conclusão fala como resultado guardado: a Lia não diz "o PDF acima" sem PDF nenhum.
  def sem_o_arquivo(evento, conversation, passo)
    return evento unless evento.tipo == 'concluida' && arquivo_a_caminho?(evento.run, conversation, passo[:depois_de])

    ::Autonomia::Agents::Tools::Evento.new(run: evento.run, tipo: 'valores_guardados')
  end

  def aceitos(run)
    Array(run.handle.to_h[::Autonomia::Agents::Tools::EntregaAceita::CHAVE]).map(&:to_s)
  end

  # O evento de começo foi disparado e ainda não tem mensagem (pública ou a nota ao atendente).
  def comeco_sem_palavra?(run, conversation)
    return false if run.handle.to_h[::Autonomia::Agents::Tools::Evento::COMECO_KEY].blank?
    return false if resultado_na_conversa?(run, conversation)

    !::Autonomia::Agents::Tools::Evento.new(run: run, tipo: ::Autonomia::Agents::Tools::Evento::COMECO).publicado?(conversation)
  end

  # Algum arquivo que o publicador aceitou (a lista do aceite, `Tools::EntregaAceita`, e o que veio em
  # `depois_de`) ainda não é mensagem.
  def arquivo_a_caminho?(run, conversation, depois_de)
    (aceitos(run) | depois_de).any? do |token|
      ::Autonomia::Agents::Tools::EntregaPublicada.para(conversation, token).nil?
    end
  end

  def adiar(evento, passo)
    reagendar(evento, passo.merge(adiamentos: passo[:adiamentos] + 1), AsyncConfig::PUBLISH_DEFER_SECONDS.seconds)
  end

  def reagendar(evento, passo, espera)
    self.class.set(wait: espera).perform_later(evento.run.id, evento.tipo, passo[:adiamentos], passo[:tentativa], passo[:depois_de])
  end

  def aviso(evento)
    ::Autonomia::Agents::Operate::AvisoAoAtendente.new(evento: evento)
  end

  # Só ids e rótulos de lista fechada: nada do que o cliente escreveu, nada do que o modelo respondeu.
  def anotar(run, tipo, desfecho)
    Rails.logger.info("[autonomia][evento] run=#{run.id} tipo=#{tipo} #{desfecho}")
    nil
  end
end
