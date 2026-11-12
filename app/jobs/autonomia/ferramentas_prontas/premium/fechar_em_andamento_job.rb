# O VARREDOR DAS CONSULTAS PREMIUM "EM ANDAMENTO" (#2858, F7, revisor 12/11). O Experimente Premium roda num job próprio,
# fora do `ToolRun` do agente, e grava a linha "em andamento" antes de chamar a BigDataCorp
# (`Premium::Cobranca.em_andamento!`). Se o worker morre no meio da chamada, a linha sobra. Este job, agendado pela
# própria execução para depois do prazo máximo da consulta, fecha a que sobrou como entrega incerta: o custo do dataset
# fica na telemetria e nada conta para o cliente (`Cobranca.fechar_em_andamento!`). Só a conta da execução.
class Autonomia::FerramentasProntas::Premium::FecharEmAndamentoJob < ApplicationJob
  queue_as :low

  Premium = Autonomia::FerramentasProntas::Premium
  # O prazo da consulta mais lenta (a sob demanda, com a folga do prazo total) mais a folga do varredor: a espera na
  # fila e a gravação do resultado. Folga de desenho, não medida.
  LIMITE = (Premium::Dataset::PRAZO_SOB_DEMANDA + Premium::ConsultaPaga::FOLGA).seconds + 2.minutes
  # Quando a execução agenda o varredor: um pouco depois do limite, para a linha já estar vencida.
  ESPERA = LIMITE + 30.seconds

  def perform(account_id)
    Premium::Cobranca.fechar_em_andamento!(account_id, antes_de: LIMITE.ago)
  end
end
