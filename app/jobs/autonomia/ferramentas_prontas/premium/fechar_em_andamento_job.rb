# O VARREDOR DAS CONSULTAS PREMIUM "EM ANDAMENTO" (#2858, F7, revisor 12/11). O Experimente Premium roda num job próprio,
# fora do `ToolRun` do agente, e grava a linha "em andamento" antes de chamar a BigDataCorp
# (`Premium::Cobranca.em_andamento!`). Se o worker morre no meio da chamada, a linha sobra. Este job, agendado pela
# própria execução para depois do prazo máximo da consulta, fecha a que sobrou como entrega incerta: o custo do dataset
# fica na telemetria e nada conta para o cliente (`Cobranca.fechar_em_andamento!`). Só a conta da execução.
#
# Sem conta, é a varredura periódica (`config/schedule.yml`): pega a linha que ficou órfã porque o job agendado pela
# execução se perdeu (Redis reiniciado, deploy no meio), em todas as contas, pela mesma regra (revisor, 12/11).
class Autonomia::FerramentasProntas::Premium::FecharEmAndamentoJob < ApplicationJob
  queue_as :low

  Premium = Autonomia::FerramentasProntas::Premium
  # O prazo da consulta Premium mais lenta do catálogo (com a folga do prazo total, `Premium.prazo_maximo`; hoje 122 s,
  # #2946) mais a folga do varredor: a espera na fila e a gravação do resultado. Folga de desenho, não medida. A linha
  # nasce logo antes da chamada: dentro deste limite, a consulta ainda pode estar no ar e não fecha como entrega incerta.
  LIMITE = Premium.prazo_maximo.seconds + 2.minutes
  # Quando a execução agenda o varredor: um pouco depois do limite, para a linha já estar vencida.
  ESPERA = LIMITE + 30.seconds

  def perform(account_id = nil)
    antes_de = LIMITE.ago
    contas = account_id ? [account_id] : contas_com_linha_vencida(antes_de)
    contas.each { |conta| Premium::Cobranca.fechar_em_andamento!(conta, antes_de: antes_de) }
  end

  private

  def contas_com_linha_vencida(antes_de)
    Premium::Registro.where(resultado: Premium::Cobranca::EM_ANDAMENTO, created_at: ...antes_de).distinct.pluck(:account_id)
  end
end
