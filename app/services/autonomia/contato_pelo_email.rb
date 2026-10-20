# Contato pelo e-mail recebido (#1813): quando chega um e-mail do próprio contato, a IA lê o texto novo (com a
# assinatura, sem o histórico citado) e completa o contato com nome, e-mail e telefone. Só completa: nome só quando está
# vazio, é o e-mail ou o telefone; telefone e e-mail só quando vazios (Decisores::Aplicador). Tudo atrás da flag por
# conta `contato_pelo_email`; o custo é da chave de IA da conta (ou da instalação), pelo Crm::Ai::CredentialResolver.
#
# Fluxo: Autonomia::ContatoPeloEmailListener (message_created) → Autonomia::ContatoPeloEmailJob →
# Autonomia::ContatoPeloEmail::Completar (Freios: pausa, trava, teto) → Leitor (o modelo) → Decisores::Aplicador.
module Autonomia::ContatoPeloEmail
  FLAG = 'contato_pelo_email'.freeze

  module_function

  def ligado?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # O e-mail que o cliente mandou: entrada numa caixa de e-mail, não nota privada, com um contato como remetente.
  # A resposta automática marcada no cabeçalho (Auto-Submitted / X-Autoreply, lido pelo MailPresenter do Chatwoot)
  # não vai à IA: é o protocolo dizendo que nenhuma pessoa escreveu. Se o From é mesmo do contato, o Completar confere.
  def email_do_cliente?(message)
    message.present? && message.incoming? && !message.private? && message.inbox&.email? &&
      message.sender.is_a?(Contact) && !message.auto_reply_email?
  end
end
