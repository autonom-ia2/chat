# #1428 (tema 6, parte 2) — os textos que o "Mudar conversando" do piloto mostra ao dono, no idioma da conta
# (catálogo autonomia.agents.ajuste, en e pt_BR). A pergunta do que faltou e a do conflito são montadas aqui com o
# `pedido` que o Construtor escreveu na lista: nenhum texto da conferência chega ao dono.
module Autonomia::Agents::Builder::TextosDoAjuste
  module_function

  # Os textos ao dono, no idioma da conta (catálogo autonomia.agents.ajuste).
  def texto(chave, account, **)
    I18n.t("autonomia.agents.ajuste.#{chave}", locale: idioma(account), **)
  end

  def idioma(account)
    locale = account&.locale.to_s
    I18n.available_locales.map(&:to_s).include?(locale) ? locale : I18n.default_locale
  end

  # A pergunta ao dono quando ficou item sem aplicar, com os pedidos que o Construtor listou. A explicação da correção
  # (texto do Construtor) vem no lugar da pergunta genérica.
  def pergunta_do_que_faltou(conferencia, account, explicacao: nil)
    pedidos = Autonomia::Agents::Builder::AjustePorLista.nao_atendidos(conferencia).pluck('pedido').compact_blank
    inicio = pedidos.any? ? texto(:nao_consegui, account, pedidos: pedidos.join('; ')) : texto(:nao_consegui_tudo, account)
    [inicio, explicacao.to_s.strip.presence || texto(:de_outro_jeito, account)].join(' ')
  end

  # Tudo entrou, mas a conferência viu conflito com o resto do agente: o dono decide.
  def pergunta_do_conflito(mudancas, account)
    texto(:conflito, account, pedidos: mudancas.pluck('pedido').compact_blank.uniq.join('; '))
  end
end
