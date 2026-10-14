require 'administrate/field/base'

# Segmento e nicho da conta (#1429, #1550), em cartões, sem <select>. `data` é o Autonomia::Agents::Nicho::Escolha efetivo.
class AgentsNicheField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => %i[nicho perfil canal] }
  end

  def nicho
    data.nicho
  end

  # O cartão de perfil marcado quando a conta está em geral: o perfil padrão, para quem trocar para seguros.
  def perfil
    data.perfil || Autonomia::Agents::Nicho::PERFIL_PADRAO
  end

  # O cartão de canal marcado fora da insurtech: o canal padrão, para quem trocar para insurtech.
  def canal
    data.canal || Autonomia::Agents::Nicho::CANAL_PADRAO
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

  def canais
    Autonomia::Agents::Nicho::CANAIS
  end

  # Desligadas as palavras por segmento na instalação, o formulário avisa que a escolha só fica guardada.
  def pacotes_ligados?
    Autonomia::Segmentos::Pacotes.enabled?
  end
end
