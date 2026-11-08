require 'administrate/field/base'

# Segmento e nicho da conta (#1429, #1550), em cartões, sem <select>. `data` é o Autonomia::Agents::Nicho::Escolha efetivo.
class AgentsNicheField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => %i[nicho perfil canal] }
  end

  # O cartão marcado: "padrao" quando a conta segue a instalação (#1429, voltar ao padrão).
  def nicho
    data.padrao? ? Autonomia::Agents::Nicho::PADRAO : data.nicho
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

  # O padrão da instalação primeiro (#1429); depois geral e seguros, como no mockup aprovado (#1550).
  def nichos
    [Autonomia::Agents::Nicho::PADRAO, Autonomia::Agents::Nicho::GERAL, Autonomia::Agents::Nicho::SEGUROS]
  end

  def perfis
    Autonomia::Agents::Nicho::PERFIS
  end

  def canais
    Autonomia::Agents::Nicho::CANAIS
  end

  # Prévia do formulário: como um card fechado (ganho, perdido) aparece para a equipe da conta, no idioma dela, com o
  # pacote do perfil (nil = geral). Lê o mesmo catálogo das requisições, então mostra o texto real.
  def previa(locale, perfil = nil)
    camadas = perfil ? [Autonomia::Agents::Nicho::SEGUROS, "#{Autonomia::Agents::Nicho::SEGUROS}/#{perfil}"] : []
    %w[won lost].map do |status|
      chave = "crm.export.statuses.#{status}"
      (camadas.any? && Autonomia::Segmentos::Catalogo.procurar(locale, chave, [], nil, camadas)) || I18n.t(chave, locale: locale)
    end
  end

  # Desligadas as palavras por segmento na instalação, o formulário avisa que a escolha só fica guardada.
  def pacotes_ligados?
    Autonomia::Segmentos::Pacotes.enabled?
  end
end
