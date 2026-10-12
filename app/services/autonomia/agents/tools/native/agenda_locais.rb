# OS LOCAIS DA PÁGINA para as ferramentas da agenda (#1196, #1305), incluído pela `Native::Agenda`: quais a IA
# oferece (cliente sem e-mail não recebe Meet/Teams, que mandam o convite pelo provedor), o rótulo para falar e o
# e-mail que vai ao Booker. Dado da conversa e da página, nunca texto de pessoa.
module Autonomia::Agents::Tools::Native::AgendaLocais
  private

  def locais
    Array(pagina.locations).select { |item| item.is_a?(Hash) }
  end

  # Meet/Teams: o convite sai pelo provedor, que exige o e-mail do cliente (`Booker#validate_provider_location!`).
  def local_pede_email?(tipo)
    ::Crm::BookingPageSettings::CALENDAR_LOCATIONS.key?(tipo.to_s)
  end

  # O e-mail do contato da conversa; sem ele, o que o modelo mandou porque a ferramenta pediu. Dado, não texto de
  # pessoa: quem confere a forma é o `BookingInput` do Booker.
  def email_do_cliente
    conversa&.contact&.email.presence || params['email'].to_s.strip.presence
  end

  # Os locais que a IA oferece: na conversa de um cliente sem e-mail, só os que não precisam dele (se todos
  # precisam, todos, e a descrição avisa). Sem conversa (Testar), todos, como no atendimento de quem tem e-mail.
  def locais_oferecidos
    return locais if conversa.blank? || email_do_cliente.present?

    locais.reject { |local| local_pede_email?(local['type']) }.presence || locais
  end

  def rotulo_do_local(local)
    rotulo = ::Crm::BookingV2::LocationLabel.for(local, account: account) || local['type']
    local['address'].present? ? "#{rotulo}: #{local['address']}" : rotulo
  end

  def descricao_dos_locais
    locais_oferecidos.map { |local| "#{local['type']} (#{rotulo_do_local(local)}#{aviso_de_email(local)})" }.join('; ')
  end

  # Os locais em campos: tipo (o valor para `agendar_reuniao`), rótulo e se pede o e-mail de um cliente que não tem.
  def locais_em_campos
    locais_oferecidos.map do |local|
      { tipo: local['type'], rotulo: rotulo_do_local(local), pede_email_do_cliente: aviso_de_email(local).present? }
    end
  end

  def aviso_de_email(local)
    conversa.present? && email_do_cliente.blank? && local_pede_email?(local['type']) ? ', pede o e-mail do cliente' : ''
  end
end
