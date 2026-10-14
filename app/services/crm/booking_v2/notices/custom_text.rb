# Texto próprio de um aviso do agendamento (#1354): o dono escreve (ou pede à IA) o texto livre de cada aviso, com as
# chaves do catálogo de campos (`TemplateFields::Catalog`) na sintaxe `{{chave}}`, e o sistema preenche no envio. Vale
# só para o texto livre (WAHA ou conversa aberta); o modelo aprovado da Meta e o do canal API não mudam.
#
# Regras (as mesmas ao salvar, ao receber da IA e de novo no envio):
# - só as chaves de ALLOWED_KEYS; `{{horario.data_hora}}` obrigatória (todos os avisos de hoje são de horário);
#   `{{horario.link_gestao}}` não (#1517): sem ela, o link vai no botão ou na linha fixa (`Notices::Text`);
# - até MAX_LENGTH caracteres, sem chave malformada e sem colchete (o rótulo de campo da tela que não virou chave);
# - sem a linha de parar: ela é do sistema e vai sempre depois do texto (`Notices::Text#stop_line`).
# Leitura das chaves por `Ai::Redacao::Chaves` (split/index, sem regex).
class Crm::BookingV2::Notices::CustomText
  MAX_LENGTH = 500
  NAME = 'cliente.primeiro_nome'.freeze
  WHEN = 'horario.data_hora'.freeze
  LINK = 'horario.link_gestao'.freeze
  BUSINESS = 'minha_empresa.nome'.freeze
  ALLOWED_KEYS = [NAME, WHEN, LINK, BUSINESS].freeze
  REQUIRED_KEYS = [WHEN].freeze
  # O que a IA pode usar (#1517): tudo menos o link, que o sistema manda sozinho (botão ou linha fixa).
  AI_KEYS = (ALLOWED_KEYS - [LINK]).freeze
  # Chaves que, quando estão no texto, precisam de valor no envio.
  FILLED_KEYS = [LINK, WHEN].freeze
  # Os idiomas que têm a linha de parar escrita (config/locales/booking_v2.*.yml).
  STOP_LINE_LOCALES = %w[en pt_BR].freeze
  Chaves = Ai::Redacao::Chaves

  class << self
    # nil quando o texto serve; senão o motivo.
    def problem(text)
      text = text.to_s
      return :blank if text.strip.empty?
      return :too_long if text.length > MAX_LENGTH

      shape_problem(text) || keys_problem(Chaves.extrair(text)) || (:stop_line if carries_stop_line?(text))
    end

    # O texto pronto para o cliente, ou nil (texto inválido ou sem dia/hora ou link para preencher): quem chama cai no
    # texto padrão. Sem primeiro nome, o campo sai junto com a vírgula ou o espaço que ficaria sobrando ("Oi, !").
    def fill(text, resolver)
      return if problem(text)

      parts = Chaves.partes(text)
      values = parts.select(&:chave?).to_h { |part| [part.valor, resolver.value(part.valor).to_s] }
      return if FILLED_KEYS.any? { |key| values.key?(key) && values[key].blank? }

      join(parts, values).strip
    end

    # O texto põe o link de gestão (`{{horario.link_gestao}}`).
    def with_link?(text)
      Chaves.extrair(text.to_s).include?(LINK)
    end

    # O texto padrão com as chaves no lugar dos valores: ponto de partida na tela e "Voltar ao texto padrão". Sem o
    # link (#1517): quem edita a partir dele continua com o botão, ou com a linha fixa onde não há botão.
    def default_text(kind, locale:)
      I18n.t("crm.booking_v2.notices.#{kind}", name: ", {{#{NAME}}}", booker: '', when: "{{#{WHEN}}}", locale: locale)
    end

    def message(problem, kind:, locale:)
      notice = I18n.t("crm.booking_v2.notice_texts.kinds.#{kind}", locale: locale)
      I18n.t("crm.booking_v2.notice_texts.errors.#{problem}", locale: locale, max: MAX_LENGTH, notice: notice)
    end

    private

    # Chave malformada; colchete é o jeito de a tela mostrar um campo ("[Dia e hora do horário]"): sobrando, iria cru
    # ao cliente.
    def shape_problem(text)
      return :malformed if Chaves.malformado?(text)

      :bracket if text.include?('[') || text.include?(']')
    end

    def keys_problem(keys)
      return :unknown_field unless (keys - ALLOWED_KEYS).empty?

      :missing_when unless keys.include?(WHEN)
    end

    def carries_stop_line?(text)
      STOP_LINE_LOCALES.any? do |locale|
        prefix = I18n.t('crm.booking_v2.notices.stop_line', link: '', locale: locale).strip
        prefix.present? && text.include?(prefix)
      end || text.include?(Crm::BookingV2::Notices::Text::STOP_PARAM)
    end

    def join(parts, values)
      body = parts.reduce('') do |memo, part|
        next memo + part.valor unless part.chave?

        value = values[part.valor]
        value.present? ? memo + value : without_separator(memo)
      end
      tidy(body)
    end

    # Campo vazio (só o primeiro nome pode faltar): sai a vírgula ou o espaço logo antes dele.
    def without_separator(body)
      body.delete_suffix(', ').delete_suffix(',').delete_suffix(' ')
    end

    # Campo vazio no começo deixa ", " ou " " na frente do texto.
    def tidy(body)
      body.delete_prefix(',').lstrip
    end
  end
end
