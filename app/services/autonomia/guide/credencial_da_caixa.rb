# #3106 (revisão do Codex) — editar a caixa pode trocar a credencial do canal em uso: o token do Telegram refaz o
# webhook lá fora, a senha do e-mail passa a valer no IMAP. O desfazer devolve a coluna, não o que o provedor já
# trocou. Então trocar credencial não tem desfazer e passa pela confirmação da pessoa (`Acoes#desfazivel?`), como
# as rotas de credencial que já estão em `Acoes::SEM_DESFAZER`.
#
# Os nomes são os de como a caixa se conecta, que a própria plataforma já trata como credencial
# (`InboxCredentialGuard::CREDENTIAL_ATTRS`: logins, senhas, servidores de e-mail, o webhook da caixa API, para onde os
# eventos passam a ir), mais os segredos dos canais que não passam por aquele guarda (`encrypts` nos modelos de
# `Channel::*` e o token HMAC). A lista dos segredos é explícita porque o `encrypts` só vale com a criptografia ligada.
module Autonomia::Guide::CredencialDaCaixa
  ACOES = ['PATCH inboxes/:id', 'PUT inboxes/:id'].freeze
  SEGREDOS = %w[
    access_token refresh_token api_key business_management_token page_access_token user_access_token
    twitter_access_token twitter_access_token_secret hmac_token secret
  ].freeze
  CAMPOS = (::Api::V1::Accounts::Concerns::InboxCredentialGuard::CREDENTIAL_ATTRS + SEGREDOS).uniq.freeze

  module_function

  # `dados` com o corpo já como a plataforma vai recebê-lo (`SemVolta.pelo_que_faz?` normaliza antes).
  def troca?(acao, dados)
    return false unless dados && ACOES.include?(acao)

    canal = ::Autonomia::Guide::Formatos::Conferencia.new(acao, dados[:corpo]).valores['channel']
    canal.is_a?(Hash) && canal.keys.map(&:to_s).intersect?(CAMPOS)
  end
end
