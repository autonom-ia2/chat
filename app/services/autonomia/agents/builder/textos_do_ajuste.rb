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

  # A pergunta INTEIRA ao dono quando ficou item sem aplicar, com os pedidos que o Construtor listou. É a que fica na
  # conversa e na pendência do Construtor (o referente do turno seguinte). A explicação da correção (texto do
  # Construtor) vem no lugar da pergunta genérica.
  def pergunta_do_que_faltou(conferencia, locale, explicacao: nil)
    pedidos = lista(Autonomia::Agents::Builder::AjustePorLista.nao_atendidos(conferencia), 'pedido')
    inicio = pedidos.present? ? texto(:nao_consegui, locale, pedidos: pedidos) : texto(:nao_consegui_tudo, locale)
    [inicio, pergunta(explicacao, locale)].join(' ')
  end

  # #1850 — a mesma pergunta como a TELA mostra enquanto o cartão ⚠ do turno está lá: sem o que o cartão já mostra
  # (ResultadoDoAjuste.o_que_faltou, pelos grupos do cartão). Cita só o pedido que ficou fora do cartão; quando o cartão
  # mostra tudo o que faltou, só pergunta. Sem cartão, igual à inteira.
  def pergunta_na_tela(conferencia, locale, explicacao: nil)
    faltou = Autonomia::Agents::ResultadoDoAjuste.o_que_faltou(conferencia)
    inicio = if faltou[:fora_do_cartao].any?
               texto(:nao_consegui, locale, pedidos: faltou[:fora_do_cartao].join('; '))
             elsif !faltou[:mostrado]
               texto(:nao_consegui_tudo, locale)
             end
    [inicio, pergunta(explicacao, locale)].compact.join(' ')
  end

  def pergunta(explicacao, locale)
    explicacao.to_s.strip.presence || texto(:de_outro_jeito, locale)
  end

  # Tudo entrou, mas a conferência viu conflito com o resto do agente: o dono decide.
  def pergunta_do_conflito(mudancas, locale)
    texto(:conflito, locale, pedidos: lista(mudancas, 'pedido'))
  end

  # #1428 (entrega C) — os dois botões fixos da pergunta do conflito, que é do código (decisão do Rodrigo, 18/10).
  def opcoes_do_conflito(locale)
    [texto('opcoes_do_conflito.manter', locale), texto('opcoes_do_conflito.mudar', locale)]
  end

  # Tudo o que entrou não tinha sido pedido e foi desfeito.
  def desfiz_o_nao_pedido(itens, locale)
    texto(:desfiz_nao_pedido, locale, resumos: lista(itens, 'resumo'))
  end

  # O desfazer foi recusado (o agente mudou por outro caminho): o que não foi pedido ficou.
  def nao_desfiz(itens, locale)
    texto(:nao_desfiz, locale, resumos: lista(itens, 'resumo'))
  end

  # Os textos de um campo dos itens, sem repetição e sem o ponto final de cada um (o texto fixo põe o dele).
  def lista(itens, campo)
    Array(itens).map { |item| item[campo].to_s.strip.chomp('.') }.compact_blank.uniq.join('; ')
  end
end
