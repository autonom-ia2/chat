# A varredura dos gatilhos de tempo da Automação livre (#2499, PR3). O TempoJob roda a cada RITMO e enfileira um
# TempoDaAutomacaoJob por automação ligada com gatilho de tempo; cada um acha os alvos da janela e chama a Partida com
# a marca do fato.
#
# - Janela de 1 dia para trás: o que ficou mais de 1 dia sem varredura (uma pane longa) não roda depois, para o
#   cliente não receber de uma vez tudo o que estava atrasado. É proteção contra defeito, não freio de uso.
# - Nada mora em memória: um deploy no meio não perde a ocorrência (a varredura seguinte ainda a acha na janela) e a
#   marca única (automacao_id, evento) não deixa repetir a que já rodou.
# - Ligar não age no passado: a ocorrência anterior a ligar (ou a salvar a versão ativa) não roda.
#   A janela de 1 dia é só para pane; não é o que ligar alcança.
# - Fuso: o da conta (`reporting_timezone`, o dos relatórios e do CRM); sem ele, o do servidor.
module Autonomia::Automacao::Tempo
  RITMO = 15.minutes
  JANELA = 1.day

  module_function

  def fuso(conta) = ActiveSupport::TimeZone[conta.reporting_timezone.to_s] || Time.zone

  # Desde quando a versão ativa está ligada: o mais recente entre ligar e salvar a versão (quem ligou salva por cima sem
  # desligar). A automação ligada antes da coluna ligada_em fica só com a hora da versão.
  def ligada_desde(definicao) = [definicao.ligada_em, definicao.versao_ativa&.created_at].compact.max

  # A rodada da varredura: o começo do intervalo de RITMO em que `agora` cai. Duas varreduras na mesma rodada são a
  # mesma (o TempoDaAutomacaoJob processa cada automação uma vez por rodada).
  def rodada(agora) = Time.zone.at((agora.to_i / RITMO.to_i) * RITMO.to_i)

  # Quem acha os alvos de cada gatilho de tempo.
  def busca(tipo)
    { 'card.parado' => Autonomia::Automacao::Tempo::Parado, 'card.data' => Autonomia::Automacao::Tempo::Data,
      'contato.data' => Autonomia::Automacao::Tempo::Data,
      'card.antes_da_reuniao' => Autonomia::Automacao::Tempo::AntesDaReuniao }.fetch(tipo)
  end
end
