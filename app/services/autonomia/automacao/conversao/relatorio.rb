# O relatório de conversão de uma conta (#2568, F9.1): "estas N regras viram estas N automações", com o que falta.
# Só leitura: lê as regras e as automações de etapa da conta e não grava nada em lugar nenhum.
#
#   Autonomia::Automacao::Conversao::Relatorio.new(conta).linhas   # um Resultado por regra/automação de etapa
#   Autonomia::Automacao::Conversao::Relatorio.new(conta).resumo   # contagens e faltas por fase
class Autonomia::Automacao::Conversao::Relatorio
  def initialize(conta)
    @conta = conta
  end

  def linhas
    @linhas ||= regras + etapas
  end

  def resumo
    {
      conta: @conta.id,
      antigas: linhas.size,
      ligadas: linhas.count(&:ligada),
      convertiveis_agora: linhas.count(&:convertivel?),
      sem_autor_conhecido: linhas.count { |linha| !linha.autor_conhecido },
      faltas_por_fase: faltas_por_fase
    }
  end

  private

  def regras
    @conta.automation_rules.order(:id).map { |regra| Autonomia::Automacao::Conversao::DaRegra.new(regra).resultado }
  end

  def etapas
    @conta.crm_stage_automations.includes(:steps).order(:id).map do |automacao|
      Autonomia::Automacao::Conversao::DaEtapa.new(automacao).resultado
    end
  end

  # Por fase, quantas antigas esperam por ela (uma antiga com três faltas da mesma fase conta uma vez).
  def faltas_por_fase
    linhas.flat_map(&:fases).tally.sort_by { |fase, _| fase }.to_h
  end
end
