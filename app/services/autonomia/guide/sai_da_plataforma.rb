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
# - A transcrição da conversa vai por e-mail ao endereço que o pedido diz; o teste de campanha de e-mail também.
# - Apps de painel: a URL abre na tela da conversa e recebe os dados da conversa e do contato.
# - Ferramentas HTTP dos agentes de IA (Captain e Autonomia): o agente passa a mandar dado das conversas à URL; o teste
#   chama a URL na hora, do servidor.
# - App OAuth do e-mail da conta: quem reconectar a caixa manda o código de autorização ao app configurado.
# - Relatório de anúncios por WhatsApp: vai ao número que o pedido diz.
# - SAML: URL, certificado do provedor e `role_mappings` decidem quem entra, e com que papel, no próximo login.
# - Responder ou apagar comentário (posts e anúncios da Meta), em público ou no privado: sai na rede social na hora.
# - Criar issue no Linear: título e descrição vão para fora.
#
# O webhook da caixa API vai pela `CredencialDaCaixa`, junto do resto de como a caixa se conecta.
module Autonomia::Guide::SaiDaPlataforma
  ACOES = [
    'POST agents', 'POST agents/bulk_create',
    'POST webhooks', 'PATCH webhooks/:id', 'PUT webhooks/:id',
    'POST agent_bots', 'PATCH agent_bots/:id', 'PUT agent_bots/:id', 'POST inboxes/:id/set_agent_bot',
    'POST integrations/hooks', 'PATCH integrations/hooks/:id', 'PUT integrations/hooks/:id',
    'POST integrations/slack', 'PATCH integrations/slack', 'PUT integrations/slack',
    'POST conversations/:id/transcript', 'POST email_campaigns/campaigns/:id/test_send',
    'POST dashboard_apps', 'PATCH dashboard_apps/:id', 'PUT dashboard_apps/:id',
    'POST captain/custom_tools', 'PATCH captain/custom_tools/:id', 'PUT captain/custom_tools/:id', 'POST captain/custom_tools/test',
    'POST autonomia/agents/:agent_id/tools', 'PATCH autonomia/agents/:agent_id/tools/:id', 'PUT autonomia/agents/:agent_id/tools/:id',
    'POST autonomia/agents/:agent_id/tools/:id/test',
    'PATCH email_oauth_apps/:provider', 'PUT email_oauth_apps/:provider',
    'PATCH crm/meta_ads_connection/whatsapp_report', 'POST crm/meta_ads_connection/whatsapp_report/test',
    'POST saml_settings', 'PATCH saml_settings', 'PUT saml_settings', 'DELETE saml_settings',
    'POST seus_posts/posts/:post_id/comments/:comment_id/reply', 'POST seus_posts/posts/:post_id/comments/:comment_id/private_reply',
    'DELETE seus_posts/posts/:post_id/comments/:comment_id',
    'POST crm/meta_ads_connection/ads/:ad_id/facebook_comments/:comment_id/reply',
    'POST crm/meta_ads_connection/ads/:ad_id/instagram_comments/:comment_id/reply',
    'POST crm/meta_ads_connection/ads/:ad_id/instagram_comments/:comment_id/private_reply',
    'POST integrations/linear/create_issue'
  ].freeze
  # O papel de administrador, pelo nome ou pelo número do enum (`role: 1`, revisão do Codex).
  ADMINISTRADOR = ['administrator', AccountUser.roles['administrator'].to_s].freeze
  EDITAR_AGENTE = ['PATCH agents/:id', 'PUT agents/:id'].freeze

  module_function

  # `dados` com o corpo já como a plataforma vai recebê-lo (`SemVolta.pelo_que_faz?` normaliza antes).
  def vira_administrador?(acao, dados)
    return false unless dados && EDITAR_AGENTE.include?(acao)

    ADMINISTRADOR.include?(::Autonomia::Guide::Formatos::Conferencia.new(acao, dados[:corpo]).valores['role'].to_s)
  end
end
