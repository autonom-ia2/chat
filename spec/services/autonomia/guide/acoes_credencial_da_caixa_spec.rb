require 'rails_helper'

# #3106 (revisão do Codex): editar a caixa pode trocar a credencial do canal em uso. O token do Telegram refaz o
# webhook lá fora, e o desfazer devolve a coluna, não o que o provedor já trocou. Então a pessoa confirma antes.
RSpec.describe Autonomia::Guide::Acoes do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:acoes) { described_class.new(account: conta, user: admin) }
  let(:caixa) { create(:inbox, account: conta) }

  it 'trocar a credencial do canal pede confirmação, por PATCH ou PUT' do
    %w[PATCH PUT].each do |verbo|
      dados = { caminho: { id: caixa.id }, corpo: { channel: { bot_token: 'novo-token' } } }

      expect(acoes.desfazivel?("#{verbo} inboxes/:id", dados)).to be(false)
    end
  end

  # #3106 (revisão do Codex): trocar o webhook da caixa API manda os eventos seguintes para outro endereço.
  it 'trocar o webhook ou o servidor de e-mail da caixa pede confirmação' do
    webhook = { caminho: { id: caixa.id }, corpo: { channel: { webhook_url: 'https://outro-destino.example/webhook' } } }
    servidor = { caminho: { id: caixa.id }, corpo: { channel: { smtp_address: 'smtp.outro.example' } } }

    expect(acoes.desfazivel?('PATCH inboxes/:id', webhook)).to be(false)
    expect(acoes.desfazivel?('PUT inboxes/:id', servidor)).to be(false)
  end

  it 'trocar a sessão do WhatsApp da caixa pede confirmação; outro ajuste em additional_attributes segue direto' do
    sessao = { caminho: { id: caixa.id }, corpo: { channel: { additional_attributes: { session: '5511999990000' } } } }
    janela = { caminho: { id: caixa.id }, corpo: { channel: { additional_attributes: { agent_reply_time_window: 24 } } } }

    expect(acoes.desfazivel?('PATCH inboxes/:id', sessao)).to be(false)
    expect(acoes.desfazivel?('PATCH inboxes/:id', janela)).to be(true)
  end

  # #3106 (revisão de segurança): o que manda dado para fora da conta ou dá acesso a alguém.
  it 'webhook da conta, bot, integração e convite de agente pedem confirmação' do
    expect(acoes.desfazivel?('POST webhooks', { corpo: { url: 'https://fora.example/hook' } })).to be(false)
    expect(acoes.desfazivel?('PATCH agent_bots/:id', { caminho: { id: 1 }, corpo: { outgoing_url: 'https://fora.example' } }))
      .to be(false)
    expect(acoes.desfazivel?('POST integrations/hooks', { corpo: { app_id: 'slack' } })).to be(false)
    expect(acoes.desfazivel?('POST agents', { corpo: { name: 'Ana', email: 'ana@example.com', role: 'agent' } })).to be(false)
    expect(acoes.desfazivel?('POST conversations/:id/transcript', { caminho: { id: 1 }, corpo: { email: 'fora@example.com' } }))
      .to be(false)
    expect(acoes.desfazivel?('POST captain/custom_tools/test', { corpo: { endpoint_url: 'https://fora.example' } })).to be(false)
  end

  it 'trocar o SAML e responder comentário na rede social pedem confirmação' do
    expect(acoes.desfazivel?('PATCH saml_settings', { corpo: { role_mappings: { admins: { role: 1 } } } })).to be(false)
    expect(acoes.desfazivel?('POST seus_posts/posts/:post_id/comments/:comment_id/reply',
                             { caminho: { post_id: 1, comment_id: 2 }, corpo: { mensagem: 'Oi' } })).to be(false)
  end

  it 'o que fala com o cliente ou com o provedor na hora pede confirmação' do
    expect(acoes.desfazivel?('POST crm/meetings/:id/remind', { caminho: { id: 1 } })).to be(false)
    expect(acoes.desfazivel?('POST whatsapp_hybrid_connections/:inbox_id/reconnect', { caminho: { inbox_id: caixa.id } })).to be(false)
    expect(acoes.desfazivel?('POST crm/integration_tokens', { corpo: { name: 'Zapier' } })).to be(false)
  end

  it 'promover agente a administrador pede confirmação; trocar o nome segue direto' do
    agente = create(:user, account: conta, role: :agent)

    expect(acoes.desfazivel?('PATCH agents/:id', { caminho: { id: agente.id }, corpo: { role: 'administrator' } })).to be(false)
    expect(acoes.desfazivel?('PUT agents/:id', { caminho: { id: agente.id }, corpo: { role: 1 } })).to be(false)
    expect(acoes.desfazivel?('PATCH agents/:id', { caminho: { id: agente.id }, corpo: { name: 'Ana Souza' } })).to be(true)
  end

  it 'desconectar provedor, cancelar reunião e pôr anúncio no ar pedem confirmação' do
    expect(acoes.desfazivel?('DELETE integrations/slack')).to be(false)
    expect(acoes.desfazivel?('DELETE crm/meetings/:id', { caminho: { id: 1 } })).to be(false)
    expect(acoes.desfazivel?('POST crm/meta_ads_connection/ads/:ad_id/status', { caminho: { ad_id: '1' }, corpo: { status: 'ACTIVE' } }))
      .to be(false)
  end

  it 'criar caixa API com webhook pede confirmação; sem credencial segue direto' do
    com_webhook = { corpo: { name: 'API', channel: { type: 'api', webhook_url: 'https://fora.example/hook' } } }
    sem = { corpo: { name: 'Site', channel: { type: 'web_widget', website_url: 'https://loja.example' } } }

    expect(acoes.desfazivel?('POST inboxes', com_webhook)).to be(false)
    expect(acoes.desfazivel?('POST inboxes', sem)).to be(true)
  end

  it 'mudar o nome da caixa segue direto, com desfazer' do
    expect(acoes.desfazivel?('PATCH inboxes/:id', { caminho: { id: caixa.id }, corpo: { name: 'Vendas' } })).to be(true)
  end

  it 'a reação ao cliente pede confirmação' do
    expect(acoes.desfazivel?('POST conversations/:conversation_id/messages/:id/reaction')).to be(false)
    expect(acoes.desfazivel?('POST conversa_canal/reacoes')).to be(false)
  end
end
