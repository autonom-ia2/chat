# Agenda do aparelho pelo motor WAHA (#1865), incluído em Waha::Client. Quem decide salvar é o Waha::AgendaDoContato.
module Waha::Client::Agenda
  # `name` na resposta é o nome salvo na agenda do celular; `pushname` é o nome que a própria pessoa pôs no WhatsApp
  # dela e não conta.
  def contact(session:, chat_id:, timeout: Waha::Client::DEFAULT_TIMEOUT)
    query = URI.encode_www_form(contactId: chat_id, session: session)
    get("/api/contacts?#{query}", timeout: timeout)
  end

  # Cria ou atualiza o contato na agenda do aparelho (GOWS: app state `contact`, salvo na agenda do celular).
  # Provado no motor em 19/10/2026: cria contato novo e renomeia existente, sem mandar mensagem.
  def upsert_contact(session:, chat_id:, first_name:, last_name:, timeout: Waha::Client::DEFAULT_TIMEOUT)
    put("/api/#{session}/contacts/#{chat_id}", { firstName: first_name, lastName: last_name }, timeout: timeout)
  end
end
