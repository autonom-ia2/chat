# G10 (#2499): o gatilho de etiqueta (Autonomia::Automacao::EtiquetaMudou) guarda a etiqueta pelo nome, como a conversa
# e o contato. A Receita confere o nome ao salvar e ao ligar; depois disso, mexer na etiqueta da conta não pode deixar a
# automação ligada esperando um nome que não existe mais, sem disparar e sem avisar.
#
# - Renomear (Labels::UpdateService, que troca o nome nas conversas e nos contatos): o gatilho segue o nome novo, numa
#   versão nova (Definicao#seguir_etiqueta!), e a automação fica como estava. Renomear não é pôr nem tirar: nenhuma
#   execução começa.
# - Apagar (Labels::DestroyService, que tira a etiqueta das conversas e dos contatos): o gatilho nunca mais dispararia.
#   A automação ligada desliga (Definicao#desligar!), e religar mostra o porquê (`etiqueta_de_fora` da Receita). A
#   etiqueta recriada com o mesmo nome antes do job não desliga nada.
#
# Os dois rodam depois do serviço da plataforma (config/initializers/automacao_etiqueta_do_gatilho.rb), sem mudar o que
# ele faz nas conversas e nos contatos.
module Autonomia::Automacao::EtiquetaDoGatilho
  TIPOS = [*::Autonomia::Automacao::EtiquetaMudou::POSTA.values, *::Autonomia::Automacao::EtiquetaMudou::TIRADA.values].freeze

  module_function

  def renomeada(account_id, antiga:, nova:)
    com_a_etiqueta(account_id, antiga).find_each { |automacao| automacao.seguir_etiqueta!(antiga: antiga, nova: nova) }
  end

  def apagada(account_id, etiqueta)
    return if Label.exists?(account_id: account_id, title: etiqueta)

    com_a_etiqueta(account_id, etiqueta).where(ativa: true).find_each(&:desligar!)
  end

  # As automações da conta cuja versão ativa tem o gatilho de etiqueta com esse nome (o gatilho compara sem diferença
  # de maiúscula, Gatilhos::DE_TEXTO).
  def com_a_etiqueta(account_id, etiqueta)
    versoes = ::Autonomia::Automacao::Versao.where(account_id: account_id)
                                            .where("receita -> 'gatilho' ->> 'tipo' IN (?)", TIPOS)
                                            .where("LOWER(receita -> 'gatilho' ->> 'etiqueta') = LOWER(?)", etiqueta)
    ::Autonomia::Automacao::Definicao.where(account_id: account_id, versao_ativa_id: versoes.select(:id))
  end

  module AoRenomear
    def perform
      super.tap { ::Autonomia::Automacao::EtiquetaDoGatilho.renomeada(account_id, antiga: old_label_title, nova: new_label_title) }
    end
  end

  module AoApagar
    def perform
      super.tap { ::Autonomia::Automacao::EtiquetaDoGatilho.apagada(account_id, label_title) }
    end
  end
end
