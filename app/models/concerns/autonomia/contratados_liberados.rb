# frozen_string_literal: true

# A liberação dos agentes contratados (#3270) como atributo da conta, só para o campo do super admin
# (ContratadosLiberadosField) ler e o update do Administrate gravar. Quem precisa saber se a conta está liberada lê
# Autonomia::Agents::Contratados::Liberacao.liberado?(account, chave).
module Autonomia::ContratadosLiberados
  extend ActiveSupport::Concern

  def contratados_liberados
    Autonomia::Agents::Contratados::Liberacao.modelos(self)
  end

  # Recebe a lista de chaves marcadas no formulário (com o valor vazio do campo escondido, que desliga todas).
  def contratados_liberados=(valor)
    Autonomia::Agents::Contratados::Liberacao.atribuir(self, valor)
  end
end
