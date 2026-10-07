# O texto do aviso do Guia, montado SEM modelo (#935, D4): o nome da vigia e os números medidos.
#
# Quem explica e propõe é o Guia, quando a pessoa abre a conversa. Aqui só o fato, curto, no idioma
# da conta, e uma pergunta: o aviso pergunta, a pessoa decide.
class Autonomia::Guide::TextoDoAviso
  def initialize(account)
    locale = LOCALE_PREFERENCE_ALIASES.fetch(account.locale.to_s, account.locale.to_s)
    @locale = I18n.available_locales.map(&:to_s).include?(locale) ? locale : I18n.default_locale
  end

  # `sinais`: [{ vigia:, valor:, media: }]
  def do_pulso(sinais, mesmo_assunto:)
    I18n.with_locale(@locale) do
      return [linha(sinais.first), t('pergunta')].join("\n\n") if sinais.one?

      cabecalho = t(mesmo_assunto ? 'varios_mesmo_assunto' : 'varios', n: sinais.size)
      [cabecalho, sinais.map { |sinal| "- #{linha(sinal)}" }.join("\n"), t('pergunta')].join("\n\n")
    end
  end

  def resumo(adiados)
    I18n.with_locale(@locale) do
      itens = adiados.map { |aviso| "- #{aviso.texto.lines.first.to_s.strip.truncate(140)}" }
      [t('resumo', n: adiados.size), itens.join("\n"), t('pergunta')].join("\n\n")
    end
  end

  def pausada(vigia)
    I18n.with_locale(@locale) { t('pausada', nome: vigia.nome) }
  end

  def whatsapp_api_caiu(inbox)
    I18n.with_locale(@locale) { t('whatsapp_api_caiu', caixa: inbox.name) }
  end

  private

  def linha(sinal)
    vigia = sinal[:vigia]
    gatilho = vigia.gatilho
    valores = { nome: vigia.nome, valor: numero(sinal[:valor]) }
    return t('linha_media', **valores, media: numero(sinal[:media]), vezes: numero(gatilho['vezes_a_media'])) if gatilho.key?('vezes_a_media')
    return t('linha_acima', **valores, limite: numero(gatilho['acima_de'])) if gatilho.key?('acima_de')

    t('linha_abaixo', **valores, limite: numero(gatilho['abaixo_de']))
  end

  def numero(valor)
    decimal = valor.to_f.round(1)
    decimal == decimal.to_i ? decimal.to_i : decimal
  end

  def t(chave, **valores)
    I18n.t("autonomia.guide.avisos.#{chave}", **valores)
  end
end
