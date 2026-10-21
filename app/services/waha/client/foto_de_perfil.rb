# Foto de perfil do contato (#1934), como o próprio WhatsApp mostra. Só leitura. `refresh=false` usa o cache do motor
# QUANDO existe; contato que o motor ainda não consultou é uma consulta real ao WhatsApp (por isso o ritmo de quem
# chama, WhatsappHybrid::FotoDoContato). Devolve { "profilePictureURL" => url ou nil (sem foto ou escondida pela
# privacidade) }. A URL é temporária: quem usa baixa o arquivo (Avatar::AvatarFromUrlJob).
module Waha::Client::FotoDePerfil
  def profile_picture(session:, contact_id:, timeout: Waha::Client::DEFAULT_TIMEOUT)
    query = URI.encode_www_form(contactId: contact_id, session: session, refresh: false)
    get("/api/contacts/profile-picture?#{query}", timeout: timeout)
  end
end
