# Por que a automação pausou sozinha (#2572, F3.7). Quem ligou perdeu o acesso, uma chave ou saiu da conta: o motor
# desliga a automação (Executor#pausar, Partida#pausar) e grava o motivo no registro da execução, marcado como pausa
# (Registro::PAUSOU). Sem isto, a tela a mostrava igual a uma desligada à mão, e ninguém via que ligar de novo é
# assumir: ela passa a agir em nome de quem liga. A marca, e não uma lista de motivos, diz o que é pausa: o motivo novo
# de um passo novo aparece sem mexer aqui.
#
# Vale o registro de pausa mais novo desde a última vez que ligaram (`ligada_em`): depois de religar, a pausa antiga não
# conta. Os registros ficam 30 dias (Registro::RETENCAO); depois disso a pausa aparece como desligada.
module Autonomia::Automacao::Pausa
  module_function

  # { automacao_id => motivo } das desligadas que pausaram desde a última vez que ligaram. Uma consulta para a lista.
  def das(automacoes)
    desligadas = automacoes.reject(&:ativa).select(&:ligada_em).index_by(&:id)
    return {} if desligadas.empty?

    ultimos(desligadas.keys).each_with_object({}) do |registro, pausas|
      pausas[registro.automacao_id] = registro.motivo if registro.created_at >= desligadas[registro.automacao_id].ligada_em
    end
  end

  def para_tela(motivo) = motivo && { motivo: motivo, frase: I18n.t("autonomia.automacao.motivos.#{motivo}") }

  # O registro de pausa mais novo de cada automação.
  def ultimos(ids)
    ::Autonomia::Automacao::Registro.de_pausa.where(automacao_id: ids)
                                    .select('DISTINCT ON (automacao_id) automacao_id, motivo, created_at')
                                    .order(:automacao_id, id: :desc)
  end
end
