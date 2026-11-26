# O TURNO DA BIA ACIONADO PELO AVISO DE PAGAMENTO (#3246b): `pagamento_confirmado` (com o voucher logo abaixo) ou
# `lembrete_de_pagamento`. Quem enfileira é a conferência automática (`Contratados::ConferirPagamentoJob`). É o par do
# `EventoJob` da Lia, e não o reaproveita: aquele vive de uma execução; este, da proposta guardada.
#
# A ORDEM, antes de falar:
#   1. evento morto (a cotação sumiu, a proposta foi trocada) ou sem conversa: só log. O `pagamento_confirmado` de uma
#      proposta trocada vira nota à equipe (um carrinho anterior foi pago), sem voucher;
#   2. turno do cliente em curso (`TurnoEmCurso`, ou a fala da cadeia de pedaços, `FalaEmCurso`): espera, com teto;
#   3. o voucher que já saiu ou que o turno do cliente já marcou (no lembrete: o pagamento que chegou ou foi cancelado,
#      ou a hora do lembrete que passou): não fala;
#   4. a fala do evento já postada (nova tentativa): não fala de novo; no `pagamento_confirmado`, o cartão do voucher
#      é reenfileirado pela âncora (o token barra o repetido);
#   5. elegibilidade (`Operate.eligible_agent_inbox`, o mesmo agente da cotação): inelegível vira nota, sem PDF. Vem
#      antes da janela: com humano no comando, a nota diz isso, e não que a janela fechou;
#   6. JANELA FECHADA (`can_reply_automatically?`): o modelo não roda. O `pagamento_confirmado` vira nota à equipe; o
#      lembrete, só log;
#   7. fala: turno do modelo com a nota do sistema (`ResponderAoEventoDaViagem`).
#
# FALHA DO TURNO (IA falhou, resposta vazia): UMA nova tentativa, com espera; falhou de novo, o `pagamento_confirmado`
# escala com nota, como o `EventoJob`, e o lembrete fica só na nota (sem passar a conversa: ninguém pediu nada). O sinal
# de silêncio não é falha: só a nota. Nunca frase pronta ao cliente.
class Autonomia::Agents::Operate::EventoDaViagemJob < ApplicationJob
  queue_as :medium

  AsyncConfig = ::Autonomia::Agents::Tools::AsyncConfig
  EventoDaViagem = ::Autonomia::Agents::Tools::EventoDaViagem
  ESPERA_DA_NOVA_TENTATIVA = 30.seconds
  TENTATIVAS = 2

  def perform(cotacao_id, tipo, gerada_em_i, adiamentos = 0, tentativa = 0)
    evento = EventoDaViagem.new(cotacao: ::Autonomia::Agents::CotacaoDeViagem.find_by(id: cotacao_id), tipo: tipo,
                                gerada_em_i: gerada_em_i)
    return anotar(cotacao_id, tipo, 'tipo_desconhecido') unless evento.valido?
    return morto(evento, cotacao_id) unless evento.vivo?

    conversation = evento.conversation
    return anotar(cotacao_id, tipo, 'sem_conversa') if conversation.blank?

    passo = { adiamentos: adiamentos.to_i, tentativa: tentativa.to_i }
    return adiar(evento, passo) if turno_do_cliente_em_curso?(conversation, passo[:adiamentos])

    seguir(evento, conversation, passo)
  end

  private

  def seguir(evento, conversation, passo)
    motivo = evento.motivo_para_calar
    return anotar(evento.cotacao.id, evento.tipo, motivo) if motivo
    return ja_publicado(evento, conversation) if evento.publicado?(conversation)

    agent_inbox = vinculo(evento.cotacao, conversation)
    return aviso(evento).notar('inelegivel') if agent_inbox.nil?
    return fora_da_janela(evento) unless conversation.can_reply_automatically?

    falar(evento, conversation, agent_inbox, passo)
  end

  # A nova tentativa que acha a fala do evento já postada (o run anterior morreu depois de postar, antes de enfileirar o
  # cartão): no `pagamento_confirmado`, o cartão do voucher gravado na âncora entra na fila pelo caminho de sempre
  # (`CartoesDoTurno.enfileirar`); o token barra o que já saiu.
  def ja_publicado(evento, conversation)
    anotar(evento.cotacao.id, evento.tipo, 'ja_publicado')
    ancora = evento.mensagem(conversation)
    return unless evento.pagamento_confirmado? && ancora && !ancora.private

    ::Autonomia::Agents::Operate::CartoesDoTurno.enfileirar(ancora)
  end

  # A proposta trocada: o `pagamento_confirmado` dela vira nota (o carrinho anterior foi pago); o resto, só log.
  def morto(evento, cotacao_id)
    return anotar(cotacao_id, evento.tipo, 'cotacao_sumiu') if evento.cotacao.nil?
    return anotar(cotacao_id, evento.tipo, 'proposta_trocada') unless evento.pagamento_confirmado?

    aviso(evento).notar('carrinho_substituido')
  end

  def fora_da_janela(evento)
    return anotar(evento.cotacao.id, evento.tipo, 'fora_da_janela') unless evento.pagamento_confirmado?

    aviso(evento).notar('fora_da_janela')
  end

  def falar(evento, conversation, agent_inbox, passo)
    resultado = ::Autonomia::Agents::Operate::ResponderAoEventoDaViagem.new(conversation: conversation, agent_inbox: agent_inbox,
                                                                            evento: evento).perform
    # `replied` sem mensagem: a guarda da hora de postar calou (a fala já estava lá, ou o voucher já saiu ou foi marcado).
    return anotar(evento.cotacao.id, evento.tipo, resultado.message ? 'falou' : 'calou_na_hora_de_postar') if resultado.status == :replied
    return aviso(evento).notar('inelegivel') if resultado.error == 'nao_elegivel'
    return aviso(evento).notar('silencio') if resultado.error == 'sinal'

    tentar_de_novo_ou_escalar(evento, agent_inbox, passo, resultado.error)
  end

  def tentar_de_novo_ou_escalar(evento, agent_inbox, passo, motivo)
    if passo[:tentativa] + 1 < TENTATIVAS
      anotar(evento.cotacao.id, evento.tipo, "nova_tentativa causa=#{motivo.presence || '-'}")
      return reagendar(evento, passo.merge(tentativa: passo[:tentativa] + 1), ESPERA_DA_NOVA_TENTATIVA)
    end

    return aviso(evento).notar('ia_falhou') unless evento.pagamento_confirmado?

    anotar(evento.cotacao.id, evento.tipo, "escalado causa=#{motivo.presence || '-'}")
    aviso(evento).escalar(agent_inbox)
  end

  # O vínculo que pode falar AGORA (o contrato inteiro do atendimento) e que é do agente da cotação. nil senão.
  def vinculo(cotacao, conversation)
    agent_inbox = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation.reload)
    return nil if agent_inbox.nil? || agent_inbox.autonomia_agent_id != cotacao.autonomia_agent_id

    agent_inbox
  end

  # O cliente escreveu e o agente está respondendo (a marca do turno, com a flag que a liga), ou a cadeia de pedaços de
  # algum turno ainda está "digitando" (a marca da fala, que a paridade da conversa liga). Nenhum dos dois é deste
  # evento: qualquer marca presente faz esperar, até o teto da dependência.
  def turno_do_cliente_em_curso?(conversation, adiamentos)
    return false if adiamentos >= AsyncConfig::MAX_DEPENDENCY_DEFERRALS

    ::Autonomia::Agents::Operate::TurnoEmCurso.em_curso?(conversation.id) ||
      ::Autonomia::Agents::Operate::FalaEmCurso.ocupada_por_outro?(conversation.id, nil)
  end

  def adiar(evento, passo)
    reagendar(evento, passo.merge(adiamentos: passo[:adiamentos] + 1), AsyncConfig::PUBLISH_DEFER_SECONDS.seconds)
  end

  def reagendar(evento, passo, espera)
    self.class.set(wait: espera).perform_later(evento.cotacao.id, evento.tipo, evento.gerada_em_i, passo[:adiamentos],
                                               passo[:tentativa])
  end

  def aviso(evento)
    ::Autonomia::Agents::Operate::AvisoDaViagem.new(evento: evento)
  end

  # Só ids e rótulos de lista fechada.
  def anotar(cotacao_id, tipo, desfecho)
    Rails.logger.info("[autonomia][evento_da_viagem] cotacao=#{cotacao_id} tipo=#{tipo} #{desfecho}")
    nil
  end
end
