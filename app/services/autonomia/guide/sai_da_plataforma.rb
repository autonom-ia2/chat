# #3106 (revisão de segurança) — escritas que mandam dado da conta para fora, ou dão acesso a alguém, de um jeito que o
# desfazer não recolhe: o que já saiu, saiu, e quem entrou já pôde agir. Entram em `Acoes::SEM_DESFAZER`, então pedem
# a confirmação da pessoa no Guia e o `confirmed` no MCP.
#
# - Agentes: criar manda o convite por e-mail e, se o e-mail já tem cadastro, dá o acesso na hora. Editar só pede
#   confirmação quando promove a administrador (`vira_administrador?`); nome, disponibilidade e papel personalizado
#   seguem com desfazer, como o Guia já faz (bateria C20).
# - Webhooks da conta: a URL recebe os eventos da conta, com dados do contato quando pedido.
# - Bots de agente e o bot da caixa: a `outgoing_url` do bot recebe as conversas da caixa.
# - Integrações (Slack, Dialogflow e as outras por `integrations/hooks`): ligam o envio de conversas a outro sistema.
#
# O webhook da caixa API vai pela `CredencialDaCaixa`, junto do resto de como a caixa se conecta.
module Autonomia::Guide::SaiDaPlataforma
  ACOES = [
    'POST agents', 'POST agents/bulk_create',
    'POST webhooks', 'PATCH webhooks/:id', 'PUT webhooks/:id',
    'POST agent_bots', 'PATCH agent_bots/:id', 'PUT agent_bots/:id', 'POST inboxes/:id/set_agent_bot',
    'POST integrations/hooks', 'PATCH integrations/hooks/:id', 'PUT integrations/hooks/:id',
    'POST integrations/slack', 'PATCH integrations/slack', 'PUT integrations/slack'
  ].freeze
  EDITAR_AGENTE = ['PATCH agents/:id', 'PUT agents/:id'].freeze

  module_function

  # `dados` com o corpo já como a plataforma vai recebê-lo (`SemVolta.pelo_que_faz?` normaliza antes).
  def vira_administrador?(acao, dados)
    return false unless dados && EDITAR_AGENTE.include?(acao)

    ::Autonomia::Guide::Formatos::Conferencia.new(acao, dados[:corpo]).valores['role'].to_s == 'administrator'
  end
end
