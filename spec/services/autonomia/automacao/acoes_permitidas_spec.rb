require 'rails_helper'

# O CI cobra lib/operator_guide/automacao-recursos.yml, a lista de ações que viram passo da Automação livre
# (#2414 F3.2, ADR-001 2.1 e D13).
RSpec.describe Autonomia::Automacao::AcoesPermitidas do
  let(:permitidas) { described_class }
  let(:formatos) { Autonomia::Guide::Formatos.todos }
  let(:recursos_do_catalogo) { formatos.keys.map { |acao| permitidas.recurso_de(acao) }.uniq }

  def liberadas(*acoes) = acoes.map { |acao| permitidas.permitida?(acao) }

  it 'classifica todo recurso do catálogo do Guia, uma vez só' do
    classificados = permitidas.classificados

    expect(recursos_do_catalogo - classificados).to be_empty
    expect(classificados - recursos_do_catalogo).to be_empty
    expect(classificados.tally.select { |_recurso, vezes| vezes > 1 }).to be_empty
  end

  it 'dá um motivo a cada recurso liberado e a cada grupo de fora' do
    expect(permitidas.lista['passo'].values.pluck('motivo')).to all(be_present)
    expect(permitidas.lista['fora'].pluck('motivo')).to all(be_present)
  end

  it 'só libera ação que existe, no recurso em que está, com formato completo' do
    permitidas.lista['passo'].each do |recurso, bloco|
      bloco['acoes'].each_key do |acao|
        expect(formatos[acao]).to be_present, "#{acao} não existe no catálogo"
        expect(permitidas.recurso_de(acao)).to eq(recurso), "#{acao} não é de #{recurso}"
        expect(formatos[acao]['completo']).to be(true), "#{acao} tem formato incompleto"
      end
    end
  end

  it 'não libera ação sem desfazer nem ação que só se faz na tela' do
    liberadas = permitidas.acoes.keys

    expect(liberadas & Autonomia::Guide::Acoes::SEM_DESFAZER).to be_empty
    expect(liberadas.select { |acao| Autonomia::Guide::Acoes.fora_do_catalogo?(acao) }).to be_empty
  end

  # #2660 D1: o DELETE de item simples que o desfazer alcança entra, um a um, depois de ler o controller (apaga ou
  # arquiva o registro pelo model, dentro da requisição). DELETE novo na lista só passa entrando aqui.
  describe 'a trava do DELETE (D1)' do
    let(:delete_liberados) do
      ['DELETE contacts/:contact_id/notes/:id', 'DELETE contacts/:contact_id/customer', 'DELETE companies/:company_id/contacts/:id',
       'DELETE crm/follow_ups/:id', 'DELETE crm/booking_invites/:id',
       # Lote D.
       'DELETE teams/:team_id/team_members', 'DELETE canned_responses/:id', 'DELETE custom_filters/:id', 'DELETE crm/saved_views/:id',
       'DELETE agent_capacity_policies/:agent_capacity_policy_id/inbox_limits/:id',
       'DELETE agent_capacity_policies/:agent_capacity_policy_id/users/:id', 'DELETE crm/service_schedules/:id',
       'DELETE conversations/:conversation_id/participants',
       # Lote C.
       'DELETE campaign_journey/drafts/:id', 'DELETE inboxes/:inbox_id/whatsapp_api_message_templates/:id',
       'DELETE autonomia/prospecting/lists/:id/leads/:lead_id', 'DELETE autonomia/prospecting/saved_presets/:id',
       # Lote F.
       'DELETE brand_kits/:id', 'DELETE notifications/:id']
    end
    let(:deletes) { permitidas.acoes.keys.select { |acao| acao.start_with?('DELETE ') } }

    it 'só libera o DELETE de item simples que o desfazer alcança, conferido um a um' do
      expect(deletes).to match_array(delete_liberados)
    end

    it 'nenhum DELETE de estrutura nem sem desfazer', :aggregate_failures do
      expect(deletes.map { |acao| permitidas.recurso_de(acao) } & permitidas::ESTRUTURA).to be_empty
      expect(deletes & Autonomia::Guide::Acoes::SEM_DESFAZER).to be_empty
    end

    it 'a política de distribuição e a caixa do funil ficam fora mesmo assim: param a distribuição e a criação de card' do
      fora = ['DELETE assignment_policies/:id', 'DELETE inboxes/:inbox_id/assignment_policy', 'DELETE crm/pipelines/:pipeline_id/inboxes/:inbox_id']

      expect(liberadas(*fora)).to all(be(false))
    end
  end

  it 'nunca libera apagar funil, etapa, caixa, agente, etiqueta, atributo, time ou portal (F3.11, D1)' do
    apagar_estrutura = formatos.keys.select do |acao|
      acao.start_with?('DELETE ') && permitidas::ESTRUTURA.include?(permitidas.recurso_de(acao))
    end

    expect(apagar_estrutura).to include('DELETE labels/:id', 'DELETE crm/stages/:id', 'DELETE inboxes/:id', 'DELETE teams/:id',
                                        'DELETE portals/:id', 'DELETE autonomia/agents/:id')
    expect(apagar_estrutura.select { |acao| permitidas.permitida?(acao) }).to be_empty
  end

  it 'deixa fora usuários, funções, conta, integrações, webhooks, tokens e as IAs (ADR-001 2.1)' do
    # #2660 D3 e D4: o agente de IA (ligar e desligar) e os ajustes da IA do funil saíram do `sempre`.
    expect(permitidas.sempre_fora).to include('agents', 'custom_roles', 'api/v1/accounts', 'webhooks', 'integrations/slack',
                                              'whatsapp/authorizations', 'crm/integration_tokens', 'crm/ai_suggestions',
                                              'autonomia/agents/tools', 'autonomia/agents/instruction_versions')
    expect(permitidas.lista['passo'].keys & permitidas.sempre_fora).to be_empty
    expect(permitidas.permitida?('DELETE agents/:id')).to be(false)
  end

  it 'só exige, fixa ou proíbe campo que a ação aceita' do
    permitidas.acoes.each do |acao, opcoes|
      campos = Array(opcoes['exige']) + opcoes.fetch('fixos', {}).keys + Array(opcoes['proibe']).map { |campo| campo.split('.').first }
      expect(campos - formatos[acao].fetch('campos', {}).keys).to be_empty, acao
    end
  end

  it 'pede descrição ao criar etiqueta e atributo (F3.10)' do
    expect(permitidas.exige('POST labels')).to eq(['description'])
    expect(permitidas.exige('POST custom_attribute_definitions')).to eq(['attribute_description'])
  end

  # #2633: a pergunta única de "ação de funil", do salvar e do motor; o recurso sai da lista.
  it 'de_funil? só nas ações permitidas de recurso crm/', :aggregate_failures do
    expect(permitidas.de_funil?('PATCH crm/cards/:id')).to be(true)
    expect(permitidas.de_funil?('POST conversations/:id/toggle_priority')).to be(false)
    expect(permitidas.de_funil?('DELETE crm/pipelines/:id')).to be(false)
  end

  describe '#2660 lote A: retorno e agenda' do
    it 'mexe no retorno que já existe; criar continua só pelo passo nativo (D2)', :aggregate_failures do
      expect(%w[complete cancel reschedule dismiss_reminder].map { |gesto| permitidas.permitida?("POST crm/follow_ups/:id/#{gesto}") })
        .to all(be(true))
      expect(permitidas.permitida?('POST crm/follow_ups')).to be(false)
      expect(permitidas.de_funil?('POST crm/follow_ups/:id/complete')).to be(true)
    end

    it 'não troca o modo nem o texto do envio automático pela rota crua', :aggregate_failures do
      expect(permitidas.proibidos('PATCH crm/follow_ups/:id', { 'automation_mode' => 'auto_send_message' })).to eq(['automation_mode'])
      expect(permitidas.proibidos('PUT crm/follow_ups/:id', { 'metadata' => { 'message_body' => 'Oi' } })).to eq(['metadata'])
      expect(permitidas.proibidos('PATCH crm/follow_ups/:id', { 'title' => 'Ligar de novo', 'due_at' => '2026-12-01T10:00:00Z' }))
        .to be_empty
    end

    it 'na reunião, só registra se aconteceu', :aggregate_failures do
      expect(permitidas.permitida?('POST crm/meetings/:id/record_outcome')).to be(true)
      expect(liberadas('POST crm/meetings', 'PATCH crm/meetings/:id', 'POST crm/meetings/:id/sync')).to all(be(false))
    end

    it 'na página de agendamento, deixa fora o texto ao cliente, passar reuniões e apagar', :aggregate_failures do
      expect(permitidas.proibidos('PATCH crm/booking_pages/:id', { 'booking_page' => { 'notice_texts' => {} } }))
        .to eq(['booking_page.notice_texts'])
      expect(permitidas.proibidos('PUT crm/booking_pages/:id', { 'invite_text' => 'Agende aqui' })).to eq(['invite_text'])
      expect(permitidas.permitida?('POST crm/booking_pages/:id/publish')).to be(true)
      expect(permitidas.permitida?('POST crm/booking_pages/reassign')).to be(false)
      expect(permitidas.permitida?('DELETE crm/booking_pages/:id')).to be(false)
    end

    it 'gera o link de agendamento sem mandar' do
      expect([permitidas.permitida?('POST crm/booking_invites'), permitidas.permitida?('POST crm/booking_invites/:id/deliver')])
        .to eq([true, false])
    end
  end

  describe '#2660 lote D: configuração do atendimento' do
    it 'cria e altera time, SLA e as políticas, sem apagar', :aggregate_failures do
      expect(liberadas('POST teams', 'PATCH sla_policies/:id', 'POST assignment_policies', 'PUT agent_capacity_policies/:id')).to all(be(true))
      expect(liberadas('DELETE teams/:id', 'DELETE sla_policies/:id', 'DELETE agent_capacity_policies/:id')).to all(be(false))
    end

    it 'põe e tira gente um a um; trocar a lista inteira fica fora' do
      expect(liberadas('PATCH teams/:team_id/team_members', 'PATCH conversations/:conversation_id/participants',
                       'PUT conversations/:conversation_id/participants')).to all(be(false))
    end

    it 'no funil, só restaura e liga caixa: criar e alterar esperam o formato completo', :aggregate_failures do
      expect(permitidas.permitida?('POST crm/pipelines/:id/restore')).to be(true)
      expect(liberadas('POST crm/pipelines', 'PATCH crm/pipelines/:id')).to all(be(false))
      expect(permitidas.permitida?('POST crm/pipelines/:pipeline_id/inboxes')).to be(true)
    end

    it 'no CRM da caixa, ligar o CRM e a IA de assunto ficam fora; a visão salva não muda de posição', :aggregate_failures do
      expect(permitidas.proibidos('PATCH crm/inbox_settings/:inbox_id', { 'crm_enabled' => false, 'subject_ai_mode' => 'auto' }))
        .to eq(%w[crm_enabled subject_ai_mode])
      expect(permitidas.proibidos('PATCH crm/saved_views/:id', { 'position' => 1 })).to eq(['position'])
    end

    it 'as metas ficam fora: zerar a meta apaga com delete_all' do
      expect(permitidas.permitida?('PUT crm/metas')).to be(false)
    end
  end

  describe '#2660 lote E: IA do CRM (D3 e D4)' do
    let(:agente) { 'PATCH autonomia/agents/:id' }

    it 'liga e desliga o agente de IA: o status só ativo ou pausado, o rascunho fica fora', :aggregate_failures do
      expect(permitidas.fora_da_lista(agente, { 'enabled' => true, 'status' => 'active' })).to be_empty
      expect(permitidas.fora_da_lista(agente, { 'status' => 'paused' })).to be_empty
      expect(permitidas.fora_da_lista(agente, { 'status' => 'draft' }).map(&:first)).to eq([:um_de])
    end

    it 'não configura o agente: tudo além de ligar e desligar é proibido', :aggregate_failures do
      configurar = %w[name agent_type mode tone greeting fallback_message handoff_rule human_card actuation instruction starter_questions config]

      expect(permitidas.proibidos(agente, configurar.index_with('x'))).to match_array(configurar)
      expect(permitidas.proibidos('PUT autonomia/agents/:id', { 'instruction' => 'Fale assim' })).to eq(['instruction'])
      expect(liberadas('POST autonomia/agents', 'DELETE autonomia/agents/:id', 'PATCH autonomia/agents/:id/avatar')).to all(be(false))
    end

    it 'os ajustes da IA do funil saem do sempre, mas esperam o formato completo (D4)', :aggregate_failures do
      expect(permitidas.sempre_fora).not_to include('crm/ai_settings')
      expect(liberadas('PATCH crm/pipelines/:pipeline_id/ai_settings', 'PUT crm/pipelines/:pipeline_id/ai_settings')).to all(be(false))
    end

    it 'no assunto da conversa, troca e mantém; a sugestão da IA e o repasse ficam fora', :aggregate_failures do
      expect(liberadas('POST crm/conversations/:conversation_id/focus', 'POST crm/conversations/:conversation_id/repasse/manter'))
        .to all(be(true))
      expect(liberadas('POST crm/conversations/:conversation_id/subject_suggestions/:suggestion_id/accept',
                       'POST crm/conversations/:conversation_id/subject_suggestions/:suggestion_id/dismiss',
                       'POST crm/conversations/:conversation_id/repasse')).to all(be(false))
    end

    it 'no decisor, as respostas e a lista de exemplos não mudam pelo alterar; testar fica fora', :aggregate_failures do
      expect(permitidas.proibidos('PATCH autonomia/decisores/:id', { 'respostas' => [], 'exemplos' => [] })).to eq(%w[respostas exemplos])
      expect(permitidas.permitida?('POST autonomia/decisores/:id/exemplos')).to be(true)
      expect(permitidas.permitida?('POST autonomia/decisores/:id/teste')).to be(false)
    end

    it 'aprovar sugestão de pergunta frequente fica fora: grava o que o agente diz ao cliente' do
      expect(liberadas('POST autonomia/agents/:agent_id/faq_suggestions/:id/approve', 'POST captain/faq_suggestions/:id/approve'))
        .to all(be(false))
    end
  end

  describe '#2660 lote C: rascunho de campanha e prospecção' do
    it 'monta a campanha em rascunho; disparar, agendar, retomar, pausar e apagar ficam fora', :aggregate_failures do
      expect(liberadas('POST campaign_journey/drafts', 'POST email_campaigns/campaigns', 'PATCH email_campaigns/campaigns/:id',
                       'POST email_campaigns/campaigns/:id/duplicate')).to all(be(true))
      expect(liberadas('POST campaign_journey/campaigns', 'POST email_campaigns/campaigns/:id/send_now',
                       'POST email_campaigns/campaigns/:id/schedule', 'POST email_campaigns/campaigns/:id/resume',
                       'POST email_campaigns/campaigns/:id/pause', 'DELETE email_campaigns/campaigns/:id')).to all(be(false))
    end

    it 'o modelo do WhatsApp é só o local; o oficial da Meta fica fora' do
      expect(liberadas('POST inboxes/:inbox_id/whatsapp_api_message_templates', 'POST inboxes/:inbox_id/whatsapp_templates'))
        .to eq([true, false])
    end

    it 'na prospecção, o lead vira contato ou card; buscar pago, enriquecer e recusar ficam fora', :aggregate_failures do
      expect(liberadas('POST autonomia/prospecting/leads/:id/contact', 'POST autonomia/prospecting/leads/crm_cards',
                       'POST autonomia/prospecting/leads/contacts')).to all(be(true))
      expect(liberadas('POST autonomia/prospecting/searches', 'POST autonomia/prospecting/leads/:id/enrichment',
                       'PATCH autonomia/prospecting/leads/:id', 'POST autonomia/prospecting/leads/discard')).to all(be(false))
    end

    it 'a lista não leva as etiquetas do segmento e o ajuste não encurta o cache pago', :aggregate_failures do
      expect(permitidas.proibidos('POST autonomia/prospecting/lists', { 'metadata' => {} })).to eq(['metadata'])
      expect(permitidas.proibidos('PATCH autonomia/prospecting/settings', { 'cache_ttl_seconds' => 60 })).to eq(['cache_ttl_seconds'])
    end
  end

  describe '#2660 lote F: conteúdo e painel (D5)' do
    it 'o artigo sai sempre como rascunho, sem a posição nem o rascunho paralelo', :aggregate_failures do
      expect(permitidas.fixos('POST portals/:portal_id/articles')).to eq('status' => 'draft')
      expect(permitidas.fora_da_lista('PATCH portals/:portal_id/articles/:id', { 'status' => 'published' }).map(&:first)).to eq([:fixo])
      expect(permitidas.proibidos('PUT portals/:portal_id/articles/:id', { 'position' => 1, 'draft_content' => 'x' }))
        .to eq(%w[position draft_content])
    end

    it 'em lote, muda a categoria e volta a rascunho; publicar, apagar e traduzir ficam fora', :aggregate_failures do
      status = 'PATCH portals/:portal_id/articles/bulk_actions/update_status'

      expect(permitidas.fora_da_lista(status, { 'ids' => [1], 'status' => 'published' }).map(&:first)).to eq([:um_de])
      expect(permitidas.fora_da_lista(status, { 'ids' => [1], 'status' => 'draft' })).to be_empty
      expect(liberadas('DELETE portals/:portal_id/articles/bulk_actions/delete_articles',
                       'POST portals/:portal_id/articles/bulk_actions/translate')).to all(be(false))
    end

    it 'o portal e o layout de e-mail ficam fora (D5); o link rastreado espera o formato completo' do
      expect(liberadas('POST portals', 'PATCH portals/:id', 'PATCH portals/:id/archive', 'POST ctwa_tracked_links')).to all(be(false))
      expect(permitidas.lista['passo'].keys).not_to include('branded_email_layouts')
    end

    it 'a identidade visual não baixa logo de fora; a macro é criada, não executada', :aggregate_failures do
      expect(permitidas.proibidos('PATCH brand_kits/:id', { 'logo_source_url' => 'https://exemplo.com/logo.png' })).to eq(['logo_source_url'])
      expect(liberadas('POST macros', 'POST macros/:id/execute', 'DELETE macros/:id')).to eq([true, false, false])
    end

    it 'no cuidado dos comentários, só corrige a foto; ligar e as prévias pagas ficam fora' do
      expect(liberadas('PUT seus_posts/posts/:post_id/cuidado/foto', 'PUT seus_posts/posts/:post_id/cuidado',
                       'POST seus_posts/posts/:post_id/cuidado/previa', 'PUT crm/meta_ads_connection/ads/:ad_id/cuidado/foto',
                       'PUT crm/meta_ads_connection/ads/:ad_id/cuidado')).to eq([true, false, false, true, false])
    end

    it 'na notificação, uma por vez; ler e apagar todas ficam fora' do
      expect(liberadas('PATCH notifications/:id', 'POST notifications/read_all', 'POST notifications/destroy_all'))
        .to eq([true, false, false])
    end
  end
end
