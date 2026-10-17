# #1428 (tema 6, parte 2) — os textos que o "Mudar conversando" do piloto mostra ao dono (catálogo
# autonomia.agents.ajuste, en e pt_BR), no idioma de quem conversa: o da pessoa que abriu a conversa, quando ela
# escolheu um, e senão o da conta. A pergunta do que faltou, a do conflito e o resumo do que entrou são montados aqui
# com o `pedido` e o `resumo` que o Construtor escreveu na lista: nenhum texto da conferência chega ao dono.
module Autonomia::Agents::Builder::TextosDoAjuste
  module_function

  def texto(chave, locale, **)
    I18n.t("autonomia.agents.ajuste.#{chave}", locale: locale, **)
  end

  # O idioma de quem conversa (ui_settings da pessoa, como o painel faz) e, sem ele, o da conta.
  def idioma(usuario, account)
    [usuario&.ui_settings.to_h['locale'], account&.locale].map(&:to_s).find { |locale| disponivel?(locale) } ||
      I18n.default_locale
  end

  def disponivel?(locale)
    locale.present? && I18n.available_locales.map(&:to_s).include?(locale)
  end

  # A pergunta ao dono quando ficou item sem aplicar, com os pedidos que o Construtor listou. A explicação da correção
  # (texto do Construtor) vem no lugar da pergunta genérica.
  def pergunta_do_que_faltou(conferencia, locale, explicacao: nil)
    pedidos = Autonomia::Agents::Builder::AjustePorLista.nao_atendidos(conferencia).pluck('pedido').compact_blank.uniq
    inicio = pedidos.any? ? texto(:nao_consegui, locale, pedidos: pedidos.join('; ')) : texto(:nao_consegui_tudo, locale)
    [inicio, explicacao.to_s.strip.presence || texto(:de_outro_jeito, locale)].join(' ')
  end

  # Tudo entrou, mas a conferência viu conflito com o resto do agente: o dono decide.
  def pergunta_do_conflito(mudancas, locale)
    texto(:conflito, locale, pedidos: mudancas.pluck('pedido').compact_blank.uniq.join('; '))
  end

  # O que entrou, pelos resumos do Construtor, quando parte da escrita foi desfeita.
  def o_que_entrou(mudancas, locale)
    texto(:entrou, locale, resumos: mudancas.pluck('resumo').compact_blank.uniq.join('; '))
  end
end
