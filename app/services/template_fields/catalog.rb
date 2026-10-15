# Catálogo único dos campos que preenchem uma variável de modelo do WhatsApp (#1331, épico #1320, PRD §6).
#
# A chave diz DE QUEM é o dado, e acaba a ambiguidade de "company":
#   cliente.*          o contato (cliente = contact_type/customer_since, contrato do #1322)
#   empresa_cliente.*  a empresa do contato
#   negocio.*          o card do CRM
#   horario.*          a reunião do agendamento
#   minha_empresa.*    a conta, pelo rodapé do Kit da marca padrão (`brand_kits.appearance.footer`)
#   atendente.*        quem atende
#   publico.<coluna>   uma coluna extra da planilha do Público (o cabeçalho como está escrito)
#   fixo               um texto que a pessoa escreve
#
# Cada campo tem um tipo (texto, data, hora, moeda, link), que decide a formatação única em pt-BR
# (TemplateFields::Format), e um rótulo leigo (config/locales/template_fields.*.yml). Quem lê os valores são os
# resolvedores (TemplateFields::Resolver e os de cada contexto).
class TemplateFields::Catalog
  TYPES = %w[texto data hora moeda link].freeze
  DEFAULT_TYPE = 'texto'.freeze
  FIXED = 'fixo'.freeze
  AUDIENCE_PREFIX = 'publico.'.freeze
  FIELDS = {
    'cliente.nome' => 'texto', 'cliente.primeiro_nome' => 'texto', 'cliente.telefone' => 'texto',
    'cliente.email' => 'texto', 'cliente.cliente_desde' => 'data',
    'empresa_cliente.nome' => 'texto', 'empresa_cliente.cnpj' => 'texto',
    'negocio.titulo' => 'texto', 'negocio.funil' => 'texto', 'negocio.etapa' => 'texto', 'negocio.valor' => 'moeda',
    'negocio.responsavel' => 'texto', 'negocio.prazo' => 'data',
    'horario.data_hora' => 'data', 'horario.data' => 'data', 'horario.hora' => 'hora', 'horario.link_gestao' => 'link',
    'horario.link_codigo' => 'texto',
    'minha_empresa.nome' => 'texto', 'minha_empresa.endereco' => 'texto', 'minha_empresa.telefone' => 'texto',
    'minha_empresa.site' => 'link',
    'atendente.nome' => 'texto',
    FIXED => 'texto'
  }.freeze
  # O que uma campanha com Público sabe de cada pessoa: não há card, reunião nem atendente ali.
  AUDIENCE_GROUPS = %w[cliente empresa_cliente minha_empresa publico].freeze

  class << self
    def known?(key)
      FIELDS.key?(key.to_s) || audience_key?(key)
    end

    # column_types: { 'Vencimento' => 'data' } (CampaignImports::ColumnTypes). Coluna sem tipo é texto.
    def type(key, column_types: {})
      key = key.to_s
      return FIELDS[key] if FIELDS.key?(key)
      return unless audience_key?(key)

      column_type = column_types.to_h[audience_column(key)]
      TYPES.include?(column_type) ? column_type : DEFAULT_TYPE
    end

    def group(key)
      key.to_s.split('.', 2).first
    end

    def audience_key?(key)
      key.is_a?(String) && key.start_with?(AUDIENCE_PREFIX) && key.length > AUDIENCE_PREFIX.length
    end

    def audience_key(column)
      "#{AUDIENCE_PREFIX}#{column}"
    end

    def audience_column(key)
      key.delete_prefix(AUDIENCE_PREFIX)
    end

    # O rótulo leigo; o de uma coluna da planilha é o próprio cabeçalho.
    def label(key, locale: I18n.locale)
      key = key.to_s
      return audience_column(key) if audience_key?(key)

      I18n.t("template_fields.fields.#{key}", locale: locale)
    end

    def type_label(type, locale: I18n.locale)
      I18n.t("template_fields.types.#{TYPES.include?(type) ? type : DEFAULT_TYPE}", locale: locale)
    end

    # Campo que uma campanha com Público consegue preencher (o texto fixo tem origem própria no vínculo).
    def in_audience?(key)
      key = key.to_s
      key != FIXED && known?(key) && AUDIENCE_GROUPS.include?(group(key))
    end

    # [{ key:, type:, group:, label: }] dos campos fixos do catálogo, para a tela e para a sugestão do Jev.
    def fields(locale: I18n.locale, keys: FIELDS.keys)
      keys.map { |key| { key: key, type: type(key), group: group(key), label: label(key, locale: locale) } }
    end
  end
end
