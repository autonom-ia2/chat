# Os `format` próprios da plataforma nos esquemas JSON (`JsonSchemaValidator`). Quem confere o
# formato padrão (`email`, `uri`) é a gem; aqui ficam só os que ela não tem.
module JsonSchemaFormatos
  # Um texto com e-mails separados por vírgula, como o `send_email_transcript` lê. Cada parte é um
  # e-mail ou uma variável que o motor troca por e-mail antes de mandar ({{contact.email}}).
  LISTA_DE_EMAILS = 'lista-de-emails'.freeze

  module_function

  def lista_de_emails?(texto, _schema = nil)
    partes = texto.to_s.split(',').map(&:strip)
    partes.any? && partes.all? { |parte| email?(parte) || variaveis_de_email.include?(variavel(parte)) }
  end

  def email?(parte)
    validador_de_email.valid?(parte)
  end

  def validador_de_email
    @validador_de_email ||= JSONSchemer.schema({ 'format' => 'email' })
  end

  # 'contact.email', 'inbox.email': os drops de EmailHelper#message_drops que respondem a `email`.
  def variaveis_de_email
    @variaveis_de_email ||= begin
      conversa = Struct.new(:contact, :inbox, :account).new
      drops = Object.new.extend(EmailHelper).message_drops(conversa)
      drops.filter_map { |nome, drop| "#{nome}.email" if drop.class.invokable?('email') }.freeze
    end
  end

  # '{{ contact.email }}' → 'contact.email', pelo parser do Liquid; outra coisa → nil.
  def variavel(parte)
    nos = Liquid::Template.parse(parte).root.nodelist
    busca = nos.first.name if nos.one? && nos.first.is_a?(Liquid::Variable) && nos.first.filters.empty?
    busca.is_a?(Liquid::VariableLookup) ? [busca.name, *busca.lookups].join('.') : nil
  rescue Liquid::SyntaxError
    nil
  end

  TODOS = { LISTA_DE_EMAILS => method(:lista_de_emails?) }.freeze
end
