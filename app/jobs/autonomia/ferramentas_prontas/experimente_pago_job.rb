# O EXPERIMENTE PREMIUM EM SEGUNDO PLANO (#2858, F7, revisor 12/11): roda a consulta de um pedido
# (`Experimente::Pedido`) pela `Experimente::Pago` e grava o resultado no lugar dele, para a tela ler.
#
# Na fila das ferramentas (`AgentToolsQueue`), feita para esperar sistema de fora sem ocupar as outras. Sem retry: uma
# tentativa automática consultaria de novo, e a consulta é paga. O job recebe só o id: o texto digitado fica no estado
# do pedido, com prazo, e nunca nos argumentos do Sidekiq. Uma passada por pedido (`Pedido.reivindicar`): o job que o
# Sidekiq devolve à fila depois de começar para aqui, e a tela fica com "não deu para confirmar"; a linha da telemetria
# que sobrar, o `Premium::FecharEmAndamentoJob` fecha. O defeito vai ao rastreador e a tela recebe "não consegui
# consultar".
#
# Prazo para começar (revisor, 12/11): com a fila cheia, o job pode começar depois de a tela desistir, e a consulta
# seria feita e cobrada sem ninguém ver. O job que começa depois de `PRAZO_PARA_COMECAR` não consulta: a tela recebe
# "nao_comecou" (nada foi cobrado). O prazo sai dos outros: o da tela, menos a ida ao modelo antes da consulta e a
# consulta mais lenta (a sob demanda, com a folga).
class Autonomia::FerramentasProntas::ExperimentePagoJob < ApplicationJob
  queue_as AgentToolsQueue::FILA.to_sym
  sidekiq_options retry: false

  Pedido = Autonomia::FerramentasProntas::Experimente::Pedido
  Premium = Autonomia::FerramentasProntas::Premium
  NAO_COMECOU = 'nao_comecou'.freeze
  PRAZO_PARA_COMECAR = Pedido::PRAZO_DA_TELA - Autonomia::FerramentasProntas::Experimente::ComModelo::PRAZO_DO_MODELO.seconds -
                       (Premium::Dataset::PRAZO_SOB_DEMANDA + Premium::ConsultaPaga::FOLGA).seconds

  def perform(id)
    pedido = Pedido.ler(id)
    return if pedido.nil? || pedido['situacao'] != Pedido::CONSULTANDO || !Pedido.reivindicar(id)

    account = Account.find_by(id: pedido['conta'])
    return if account.nil?
    return Pedido.concluir!(id, account.id, 'situacao' => NAO_COMECOU) if atrasado?(pedido)

    consultar(id, pedido, account)
  end

  private

  def atrasado?(pedido)
    Time.current.to_f - pedido['aberto_em'].to_f > PRAZO_PARA_COMECAR.to_f
  end

  def consultar(id, pedido, account)
    resultado = Autonomia::FerramentasProntas::Experimente::Pago.new(
      account: account, fonte: pedido['fonte'], valor: pedido['valor'], confirmou_preco: pedido['confirmou_preco']
    ).call
    Pedido.concluir!(id, account.id, resultado)
  rescue StandardError => e
    # Só a classe do erro: a mensagem pode trazer o texto digitado (CPF, CNPJ).
    Rails.logger.error("[autonomia][prontas][experimente] defeito no job account=#{account.id} fonte=#{pedido['fonte']} #{e.class}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    Pedido.concluir!(id, account.id, 'situacao' => 'nao_consegui_consultar')
  end
end
