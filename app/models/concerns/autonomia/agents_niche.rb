# frozen_string_literal: true

# O nicho dos agentes (#1429) como atributo da conta, só para o campo do super admin (AgentsNicheField) ler e o
# update do Administrate gravar. Quem precisa do nicho lê Autonomia::Agents::Nicho.for(account).
module Autonomia::AgentsNiche
  extend ActiveSupport::Concern

  def agents_niche
    Autonomia::Agents::Nicho.for(self)
  end

  # Recebe { nicho:, perfil: } do formulário. Valor fora da lista não muda nada; as outras chaves de
  # internal_attributes ficam intactas.
  def agents_niche=(valor)
    valor = valor.to_h.with_indifferent_access
    Autonomia::Agents::Nicho.atribuir(self, nicho: valor[:nicho], perfil: valor[:perfil])
  end
end
