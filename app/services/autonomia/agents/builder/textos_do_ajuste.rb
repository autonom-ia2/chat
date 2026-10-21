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

  NADA_NO_CARTAO = { pedidos: [], faltou_fora: false }.freeze

  # A pergunta ao dono quando ficou item sem aplicar. A explicação da correção (texto do Construtor) vem no lugar da
  # pergunta genérica. #1850: o que o cartão ⚠ da tela já mostra (`no_cartao`, de ResultadoDoAjuste.no_cartao) não se
  # repete aqui; quando o cartão mostra tudo o que faltou, a pergunta só pergunta.
  def pergunta_do_que_faltou(conferencia, locale, explicacao: nil, no_cartao: NADA_NO_CARTAO)
    pergunta = explicacao.to_s.strip.presence || texto(:de_outro_jeito, locale)
    [o_que_faltou(conferencia, locale, no_cartao), pergunta].compact.join(' ')
  end

  # O "Não consegui aplicar" só com os pedidos (do Construtor, na lista) que o cartão não mostra com ⚠. nil quando o
  # cartão já mostra tudo o que faltou (os pedidos ou a linha "uma parte não entrou"). A comparação é do texto do campo
  # `pedido`, como o cartão agrupa: nada de ler linguagem.
  def o_que_faltou(conferencia, locale, no_cartao)
    nao_atendidos = Autonomia::Agents::Builder::AjustePorLista.nao_atendidos(conferencia)
    pedidos = nao_atendidos.map { |item| item['pedido'].to_s.strip.chomp('.') }.compact_blank.uniq
    fora_do_cartao = pedidos - no_cartao[:pedidos]
    return texto(:nao_consegui, locale, pedidos: fora_do_cartao.join('; ')) if fora_do_cartao.any?

    texto(:nao_consegui_tudo, locale) unless pedidos.any? || no_cartao[:faltou_fora]
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
