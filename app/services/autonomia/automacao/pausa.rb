# Por que a automação pausou sozinha (#2572, F3.7). Quem ligou perdeu o acesso, uma chave ou saiu da conta: o motor
# desliga a automação (Executor#pausar, Partida#pausar) e grava o motivo no registro da execução. Sem isto, a tela a
# mostrava igual a uma desligada à mão, e ninguém via que ligar de novo é assumir: ela passa a agir em nome de quem liga.
#
# Vale o registro de pausa mais novo desde a última vez que ligaram (`ligada_em`): depois de religar, a pausa antiga não
# conta. Os registros ficam 30 dias (Registro::RETENCAO); depois disso a pausa aparece como desligada.
module Autonomia::Automacao::Pausa
  # Os motivos com que o motor pausa (todos de quem ligou), em autonomia.automacao.motivos.
  MOTIVOS = %w[sem_quem_ligou quem_ligou_saiu_da_conta quem_ligou_sem_permissao quem_ligou_sem_acesso sem_permissao_funil
               sem_chave_de_funis quem_ligou_sem_permissao_card quem_ligou_sem_permissao_importar
               quem_ligou_sem_permissao_lista quem_ligou_sem_permissao_campanha webhook_sem_permissao].freeze

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
    ::Autonomia::Automacao::Registro.where(automacao_id: ids, motivo: MOTIVOS)
                                    .select('DISTINCT ON (automacao_id) automacao_id, motivo, created_at')
                                    .order(:automacao_id, id: :desc)
  end
end
