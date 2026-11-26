# A CONFERÊNCIA AUTOMÁTICA DE UMA PROPOSTA DO SEGURO VIAGEM (#3246b). Quem enfileira é a varredura
# (`VarreduraDoPagamentoJob`), que já reservou a linha. Uma chamada à Universal (`status_do_pagamento`) pelo carrinho da
# proposta guardada, e a decisão sob o lock da cotação, relendo a proposta:
#
#   - "Pago": grava `pago_em` (`Pagamento.pago_em`, o mesmo da `situacao_do_pagamento`) e `aviso_pago_em`, e depois do
#     commit enfileira o `pagamento_confirmado`. Se o `pago_em` ou o `voucher_enviado_em` já existem (a pessoa perguntou
#     e a ferramenta já cuidou), para. Se enfileirar falha, as duas chaves saem: a próxima varredura tenta de novo.
#   - "Cancelado": grava `situacao: cancelado`, sem evento. A varredura não confere mais.
#   - "Aguardando": o LEMBRETE, uma vez (`lembrete_em`), entre 12 h e 23 h depois da proposta (o link vence em 24 h, e a
#     proposta é reaproveitada até 23 h), com a hora da conta entre 8 h e 21 h, e só na proposta mais nova da conversa.
#
# AS PORTAS VÊM ANTES DA UNIVERSAL: a cotação existe e a proposta é a mesma da reserva; a conta está ligada; o agente
# atende; a ferramenta `situacao_do_pagamento` está disponível para ele (a porta do contratado: modelo disponível na conta
# e acesso à seguradora conferido). Porta fechada não chama a Universal.
#
# SEM NOVA TENTATIVA DO SIDEKIQ: a próxima varredura é a nova tentativa. O erro da Universal vai ao log só com os ids e o
# código, sem nota: a pessoa não pediu nada, e a equipe não precisa de uma nota a cada cinco minutos.
class Autonomia::Agents::Contratados::ConferirPagamentoJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  EventoDaViagem = ::Autonomia::Agents::Tools::EventoDaViagem
  Pagamento = ::Autonomia::Agents::Tools::Native::SeguroViagem::Pagamento
  LEMBRETE_A_PARTIR_DE = 12.hours
  LEMBRETE_ATE = 23.hours
  # A hora local da conta em que o lembrete pode sair: das 8 h até antes das 21 h.
  HORARIO_DO_LEMBRETE = (8...21)

  def perform(cotacao_id, gerada_em_i)
    cotacao = ::Autonomia::Agents::CotacaoDeViagem.find_by(id: cotacao_id)
    motivo = porta_fechada(cotacao, gerada_em_i)
    return anotar(cotacao_id, motivo) if motivo

    status = consultar(cotacao)
    decidir(cotacao, status, gerada_em_i) unless status.nil?
  end

  private

  def porta_fechada(cotacao, gerada_em_i)
    return 'cotacao_sumiu' if cotacao.nil?
    return 'proposta_trocada' if EventoDaViagem.gerada_em_i(cotacao.proposta) != gerada_em_i.to_i
    return 'conta_desligada' unless ::Autonomia::Agents::Config.enabled?(cotacao.account)
    return 'agente_inativo' unless cotacao.agent.atende_cliente?

    'sem_porta' unless ::Autonomia::Agents::Tools::Native::SituacaoDoPagamento.available_for?(cotacao.agent)
  end

  # -> o corpo do `StatusPagamento`, ou nil (erro da Universal, só no log).
  def consultar(cotacao)
    Pagamento.cliente(cotacao.agent).status_do_pagamento(Pagamento.carrinho(cotacao))
  rescue ::Autonomia::Seguradoras::Universal::Cliente::Erro => e
    anotar(cotacao.id, "erro_da_universal codigo=#{e.codigo}")
  end

  # Sob o lock da cotação, relendo a proposta: conta a conferência e aplica a decisão. Depois do commit, o evento.
  def decidir(cotacao, status, gerada_em_i)
    situacao = Pagamento.situacao(status)
    gravado = {}
    tipo = nil
    cotacao.with_lock do
      proposta = cotacao.proposta.to_h
      if EventoDaViagem.gerada_em_i(proposta) == gerada_em_i.to_i
        gravado, tipo = decisao(cotacao, proposta, situacao, status)
        cotacao.update!(proposta: proposta.merge(gravado, 'conferencias' => proposta['conferencias'].to_i + 1))
      end
    end
    anotar(cotacao.id, "conferido situacao=#{situacao} evento=#{tipo || '-'}")
    enfileirar(cotacao, tipo, gerada_em_i, gravado.keys) if tipo
  end

  # -> [o que gravar na proposta, o tipo do evento ou nil].
  def decisao(cotacao, proposta, situacao, status)
    case situacao
    when Pagamento::PAGO then pago(proposta, status)
    when Pagamento::CANCELADO then [{ 'situacao' => Pagamento::CANCELADO }, nil]
    else lembrete?(cotacao, proposta) ? [{ 'lembrete_em' => Time.current.iso8601 }, EventoDaViagem::LEMBRETE] : [{}, nil]
    end
  end

  def pago(proposta, status)
    return [{}, nil] if proposta['pago_em'].present? || proposta['voucher_enviado_em'].present?

    [{ 'pago_em' => Pagamento.pago_em(status), 'aviso_pago_em' => Time.current.iso8601 }, EventoDaViagem::PAGAMENTO_CONFIRMADO]
  end

  def lembrete?(cotacao, proposta)
    return false if proposta['lembrete_em'].present?

    idade = Time.current - EventoDaViagem.gerada_em(proposta)
    return false unless idade >= LEMBRETE_A_PARTIR_DE && idade < LEMBRETE_ATE
    return false unless HORARIO_DO_LEMBRETE.cover?(Time.current.in_time_zone(fuso(cotacao)).hour)

    mais_nova_com_proposta?(cotacao)
  end

  # A proposta mais nova da conversa (de qualquer agente): a mais velha não lembra de um link que a pessoa já trocou.
  def mais_nova_com_proposta?(cotacao)
    ::Autonomia::Agents::CotacaoDeViagem.where(conversation_id: cotacao.conversation_id)
                                        .where("proposta->>'codigo_carrinho' IS NOT NULL").maximum(:id) == cotacao.id
  end

  # Depois do commit. O que não entrou na fila (o adapter levantou ou recusou) desfaz as chaves desta decisão, sob o
  # lock, para a próxima varredura tentar de novo. O erro sobe (sem nova tentativa do Sidekiq, fica no log).
  def enfileirar(cotacao, tipo, gerada_em_i, chaves)
    enfileirado = false
    job = ::Autonomia::Agents::Operate::EventoDaViagemJob.perform_later(cotacao.id, tipo, gerada_em_i.to_i)
    enfileirado = job.respond_to?(:successfully_enqueued?) && job.successfully_enqueued?
  ensure
    desfazer(cotacao, chaves) unless enfileirado
  end

  def desfazer(cotacao, chaves)
    cotacao.with_lock { cotacao.update!(proposta: cotacao.proposta.to_h.except(*chaves)) }
    anotar(cotacao.id, 'evento_nao_enfileirado')
  end

  def fuso(cotacao)
    Crm::Timezone::Resolver.new(account: cotacao.account).zone_or_default
  end

  # Só ids, rótulos e códigos de lista fechada: nada do carrinho nem da resposta da Universal.
  def anotar(cotacao_id, desfecho)
    Rails.logger.info("[autonomia][pagamento_automatico] cotacao=#{cotacao_id} #{desfecho}")
    nil
  end
end
