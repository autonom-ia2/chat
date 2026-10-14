require 'administrate/field/base'

# Nicho dos agentes da conta (#1429), em cartões, sem <select>. `data` é o Autonomia::Agents::Nicho::Escolha efetivo.
class AgentsNicheField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => %i[nicho perfil] }
  end

  def nicho
    data.nicho
  end

  # O cartão de perfil marcado quando a conta está em geral: o perfil padrão, para quem trocar para seguros.
  def perfil
    data.perfil || Autonomia::Agents::Nicho::PERFIL_PADRAO
  end

  def padrao
    Autonomia::Agents::Nicho.padrao_da_instalacao
  end

  def nichos
    Autonomia::Agents::Nicho::NICHOS
  end

  def perfis
    Autonomia::Agents::Nicho::PERFIS
  end
end
