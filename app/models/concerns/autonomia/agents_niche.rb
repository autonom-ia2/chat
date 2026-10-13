# frozen_string_literal: true

# Leitura e escrita do nicho dos agentes (#1429) como atributo da conta, para o campo do super admin
# (AgentsNicheField). Guarda em `internal_attributes`, sem coluna nova em tabela do Chatwoot.
module Autonomia::AgentsNiche
  extend ActiveSupport::Concern

  def agents_niche
    Autonomia::Agents::Nicho.da_conta(self)
  end

  # Recebe { nicho:, perfil: } do formulário. Valor fora da lista não grava nada.
  def agents_niche=(valor)
    valor = valor.to_h.with_indifferent_access
    escolhido = Autonomia::Agents::Nicho.normalizar(valor[:nicho], valor[:perfil])
    return if escolhido.blank?

    self.internal_attributes = internal_attributes.to_h.merge(Autonomia::Agents::Nicho::INTERNAL_ATTR_KEY => escolhido)
  end
end
