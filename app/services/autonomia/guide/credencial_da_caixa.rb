# #3106 (revisão do Codex) — editar a caixa pode trocar a credencial do canal em uso: o token do Telegram refaz o
# webhook lá fora, a senha do e-mail passa a valer no IMAP. O desfazer devolve a coluna, não o que o provedor já
# trocou. Então trocar credencial não tem desfazer e passa pela confirmação da pessoa (`Acoes#desfazivel?`), como
# as rotas de credencial que já estão em `Acoes::SEM_DESFAZER`.
#
# Os nomes são os campos de segredo dos canais (`encrypts` nos modelos de `Channel::*`, mais a configuração do
# provedor do WhatsApp e o token HMAC). A lista é explícita porque o `encrypts` só vale com a criptografia configurada.
module Autonomia::Guide::CredencialDaCaixa
  ACOES = ['PATCH inboxes/:id', 'PUT inboxes/:id'].freeze
  CAMPOS = %w[
    bot_token imap_password smtp_password access_token refresh_token auth_token api_key provider_config
    line_channel_secret line_channel_token business_management_token page_access_token user_access_token
    twitter_access_token twitter_access_token_secret hmac_token secret
  ].freeze

  module_function

  # `dados` com o corpo já como a plataforma vai recebê-lo (`SemVolta.pelo_que_faz?` normaliza antes).
  def troca?(acao, dados)
    return false unless dados && ACOES.include?(acao)

    canal = ::Autonomia::Guide::Formatos::Conferencia.new(acao, dados[:corpo]).valores['channel']
    canal.is_a?(Hash) && canal.keys.map(&:to_s).intersect?(CAMPOS)
  end
end
