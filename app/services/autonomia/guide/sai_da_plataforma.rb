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
  # Varredura do catálogo (#3106): o que fala com gente ou com provedor de fora na hora, e o desfazer não recolhe.
  # - Fala com o cliente: encaminhar, responder comentário, editar mensagem no WhatsApp, convites e lembretes de
  #   reunião, publicar post, campanha da jornada, resposta de presença por e-mail, convite de tester.
  # - Destino ou acesso dado no pedido: feed público de conversões, token de integração, participante de reunião,
  #   consulta a URL externa no teste da automação, robô externo que atende a caixa (webhook).
  # - Conexão com o provedor: sessão do WhatsApp (híbrida, convite, manual, Embedded Signup), webhook e chamadas na
  #   Meta, token da página, conector de seguros, apagar modelo na Meta, chamadas ao vivo e conferência.
  # - #3211: contratar o agente pronto do catálogo, que enfileira a semeadura da base com a chamada paga de embedding da
  #   própria conta (o desfazer apaga o agente, não devolve o que foi pago). O login dele na seguradora é só na tela
  #   (`AcessoDaSeguradora::SO_NA_TELA_DO_GUIA`).
  # Fica de fora, de propósito: o evento que toda escrita manda aos webhooks que a própria conta configurou, a IA da
  # plataforma, os jobs internos e quem da conta enxerga o quê (membros de caixa, time e conversa).
  FALA_COM_FORA = [
    'POST conversa_canal/encaminhamentos', 'POST conversations/:conversation_id/comentario/responder',
    'PATCH conversations/:conversation_id/messages/:id/content', 'POST crm/booking_invites/:id/deliver',
    'POST crm/booking_pages/:id/test_invite', 'POST crm/booking_stats/opened_not_booked/:invite_id/resend',
    'POST crm/meetings/:id/rebook_link', 'POST crm/meetings/:id/remind', 'POST crm/meetings',
    'POST crm/booking_pages/:id/meetings', 'POST crm/meta_ads_connection/posts', 'POST campaign_journey/campaigns',
    'POST campaign_journey/campaign_pauses/:id/resume', 'PATCH conversa_canal/convites_do_email/:id',
    'PUT conversa_canal/convites_do_email/:id', 'POST instagram/testers/invite', 'POST crm/google_conversion_feed',
    'POST crm/integration_tokens', 'POST integrations/dyte/add_participant_to_meeting',
    'POST autonomia/automacoes/testar_consulta', 'PUT autonomia/inboxes/:inbox_id/quem_atende',
    'POST whatsapp_hybrid_connections/:inbox_id/connect', 'POST whatsapp_hybrid_connections/:inbox_id/reconnect',
    'POST whatsapp_hybrid_connections/:inbox_id/pause', 'POST whatsapp_hybrid_connections/:inbox_id/resume',
    'POST whatsapp_hybrid_connections/:inbox_id/request_code', 'PATCH whatsapp_hybrid_connections/:inbox_id',
    'PUT whatsapp_hybrid_connections/:inbox_id', 'DELETE whatsapp_hybrid_connections/:inbox_id',
    'POST autonomia/invite_connection/:inbox_id/reconnect', 'POST whatsapp/manual/connect',
    'POST whatsapp/manual/:inbox_id/setup_webhook', 'POST whatsapp/authorization',
    'POST inboxes/:id/register_webhook', 'POST inboxes/:id/enable_whatsapp_calling',
    'POST inboxes/:id/disable_whatsapp_calling', 'POST callbacks/reauthorize_page',
    'POST autonomia/insurance/connection', 'POST autonomia/insurance/connection/reconnect',
    'POST autonomia/contratados/:modelo',
    'DELETE inboxes/:inbox_id/whatsapp_templates/:id', 'POST whatsapp_calls/:id/accept',
    'POST whatsapp_calls/:id/reject', 'POST whatsapp_calls/:id/terminate', 'POST inboxes/:inbox_id/conference'
  ].freeze
  # 2ª varredura (#3106): conectar ou desconectar provedor (desconectar revoga lá fora; a volta é conectar de novo),
  # validar chave no domínio que o pedido diz (Freshdesk), mudar ou cancelar reunião (avisa os convidados), anúncio
  # no ar ou criativo trocado na Meta, apagar comentário na rede social, vincular issue no Linear.
  # Fica de fora: publicar página, artigo ou perfil próprios e esconder comentário (o desfazer despublica), e o envio
  # agendado de follow-up e campanha (o desfazer cancela antes da hora).
  CONEXAO_E_PROVEDOR = [
    'POST waha_inboxes', 'POST waha_inboxes/:inbox_id/reconnect', 'POST channels/twilio_channel',
    'POST callbacks/register_facebook_page', 'POST crm/meta_ads_connection/pagina',
    'POST crm/meta_ads_connection/instagram', 'POST crm/meta_ads_lead_forms/pages/:page_id/receive',
    'DELETE crm/meta_ads_lead_forms/pages/:page_id/receive', 'DELETE integrations/linear',
    'DELETE integrations/hooks/:id', 'DELETE integrations/slack', 'DELETE integrations/notion',
    'DELETE integrations/shopify', 'DELETE email_oauth_apps/:provider', 'DELETE autonomia/insurance/connection',
    'DELETE crm/meta_ads_connection', 'DELETE crm/integration_tokens/:id', 'POST data_imports/validate_source',
    'POST data_imports', 'PATCH crm/meetings/:id', 'PUT crm/meetings/:id', 'DELETE crm/meetings/:id',
    'POST integrations/dyte/create_a_meeting', 'DELETE inboxes/:inbox_id/conference',
    'POST crm/meta_ads_connection/ads/:ad_id/status', 'PUT crm/meta_ads_connection/ads/:ad_id/creative',
    'DELETE crm/meta_ads_connection/ads/:ad_id/facebook_comments/:comment_id',
    'DELETE crm/meta_ads_connection/ads/:ad_id/instagram_comments/:comment_id',
    'DELETE conversations/:conversation_id/comentario', 'POST integrations/linear/link_issue'
  ].freeze
  TODAS = (ACOES + FALA_COM_FORA + CONEXAO_E_PROVEDOR).freeze

  # O papel de administrador, pelo nome ou pelo número do enum (`role: 1`, revisão do Codex).
  ADMINISTRADOR = ['administrator', AccountUser.roles['administrator'].to_s].freeze
  EDITAR_AGENTE = ['PATCH agents/:id', 'PUT agents/:id'].freeze

  module_function

  # `dados` com o corpo já como a plataforma vai recebê-lo (`PeloQueFaz.sem_volta?` normaliza antes).
  def vira_administrador?(acao, dados)
    return false unless dados && EDITAR_AGENTE.include?(acao)

    ADMINISTRADOR.include?(::Autonomia::Guide::Formatos::Conferencia.new(acao, dados[:corpo]).valores['role'].to_s)
  end
end
