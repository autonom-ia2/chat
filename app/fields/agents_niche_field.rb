require 'administrate/field/base'

# Nicho dos agentes da conta (#1429), em cartões, sem <select>. Ver Autonomia::Agents::Nicho.
class AgentsNicheField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => %i[nicho perfil] }
  end

  def padrao
    Autonomia::Agents::Nicho.padrao_da_instalacao
  end

  def efetivo
    data || padrao
  end

  def nicho
    efetivo['nicho']
  end

  def perfil
    efetivo['perfil'] || Autonomia::Agents::Nicho::PERFIL_PADRAO
  end

  def nichos
    Autonomia::Agents::Nicho::NICHOS
  end

  def perfis
    Autonomia::Agents::Nicho::PERFIS
  end
end
