# Demo em tela real do painel de Anúncios da Meta (#2778 (mesmos dados do #2161)). Só para o banco da demo (bin/demo seed).
#
# Dados fictícios de um negócio genérico ("Loja Exemplo"): conexão pronta (Entrar com Facebook, conta de anúncios,
# Pixel, destino WhatsApp e funil avisando a Meta), 30 dias de gasto de 5 anúncios, conversas de WhatsApp vindas
# deles e cards num funil de vendas com propostas abertas e 2 vendas.
#
# Repetível: apaga o que a rodada anterior criou (marcado com DEMO_TAG) e cria de novo.
abort 'seed só roda no banco da demo' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')

DEMO_TAG = 'demo2778'.freeze
AD_ACCOUNT_ID = '990000000002161'.freeze
CAMPAIGN_ID = '120000000000002161'.freeze
ADSETS = { '120000000000021611' => 'Público 25-45 · São Paulo', '120000000000021612' => 'Remarketing 30 dias' }.freeze
# id => [nome, conjunto, gasto médio/dia, conversas no período, vendas, propostas abertas]
ADS = {
  '120000000000216101' => ['Vídeo depoimento de cliente', '120000000000021611', 38.0, 24, 2, 2],
  '120000000000216102' => ['Carrossel promoções da semana', '120000000000021611', 32.0, 21, 0, 4],
  '120000000000216103' => ['Foto vitrine nova coleção', '120000000000021612', 18.0, 12, 0, 1],
  '120000000000216104' => ['Stories oferta relâmpago', '120000000000021612', 12.0, 6, 0, 0],
  '120000000000216105' => ['Vídeo bastidores da loja', '120000000000021611', 9.0, 3, 0, 0]
}.freeze
NOMES = %w[Ana Bruno Carla Diego Elisa Fábio Gabriela Heitor Isabela João Larissa Marcos Natália Otávio Paula Rafael
           Sabrina Tiago Vanessa Wagner].freeze
SOBRENOMES = %w[Almeida Barbosa Cardoso Dias Ferreira Gomes Lima Martins Nunes Oliveira Pereira Rocha Santos Teixeira].freeze
PERGUNTAS = ['Oi! Vi o anúncio, ainda tem disponível?', 'Olá, quanto custa?', 'Bom dia, vocês entregam na zona sul?',
             'Oi, queria mais informações sobre a promoção', 'Tem em outras cores?', 'Aceita parcelamento?'].freeze

account = Account.find(1)
user = account.users.order(:id).first
zone = ActiveSupport::TimeZone['America/Sao_Paulo']
today = Time.current.in_time_zone(zone).to_date
rng = Random.new(2161)

# ---------- limpeza da rodada anterior ----------
Crm::Card.where(account_id: account.id).where('external_id LIKE ?', "#{DEMO_TAG}-%").destroy_all
Crm::MetaAdLink.where(account_id: account.id, ad_account_id: AD_ACCOUNT_ID).delete_all
account.conversations.where("additional_attributes ->> 'demo' = ?", DEMO_TAG).find_each(&:destroy!)
demo_contacts = account.contacts.where('identifier LIKE ?', "#{DEMO_TAG}-%")
demo_contacts.find_each(&:destroy!)
# Contact#destroy não leva o contact_inbox junto: os da demo saem pelo source_id (telefone 55119700xxxxx).
ContactInbox.where(inbox_id: account.inboxes.select(:id)).where('source_id LIKE ?', '55119700%').delete_all
Crm::MetaAdInsightDaily.where(account_id: account.id).delete_all
Crm::MetaAdObject.where(account_id: account.id).delete_all
Crm::MetaAdvisorAction.where(account_id: account.id).delete_all
Crm::MetaAdvisorRun.where(account_id: account.id).delete_all

# ---------- WhatsApp oficial ----------
inbox = account.inboxes.find_by(channel_type: 'Channel::Whatsapp')
unless inbox
  # rubocop:disable Rails/SkipsModelValidations
  Channel::Whatsapp.insert({ account_id: account.id, phone_number: '+5511900002161', created_at: Time.current, updated_at: Time.current })
  # rubocop:enable Rails/SkipsModelValidations
  channel = Channel::Whatsapp.find_by!(account_id: account.id, phone_number: '+5511900002161')
  inbox = Inbox.create!(channel: channel, account: account, name: 'WhatsApp Loja Exemplo')
end

# ---------- funil de vendas ligado ao WhatsApp e avisando a Meta ----------
pipeline = account.crm_pipelines.find_or_create_by!(name: 'Vendas Loja Exemplo') do |created|
  created.created_by = user
  created.status = :active
end
stage_defs = [['Novo contato', 'lead', false, false], ['Qualificado', 'qualified', false, false], ['Proposta enviada', 'opportunity', false, false],
              ['Negociação', 'negotiation', false, false], ['Venda fechada', nil, true, false], ['Perdido', nil, false, true]]
stages = stage_defs.each_with_index.to_h do |(name, type, won, lost), position|
  stage = account.crm_pipeline_stages.find_or_initialize_by(pipeline: pipeline, name: name)
  stage.update!(position: position, is_won_stage: won, is_lost_stage: lost, metadata: stage.metadata.to_h.merge('funnel_stage_type' => type).compact)
  [name, stage]
end
pipeline.update!(status: :active, counts_as_sale: true,
                 metadata: pipeline.metadata.to_h.merge('meta_sync' => { 'enabled' => true, 'pixel_id' => '880000000002161',
                                                                         'events' => { 'won' => true, 'moved' => true, 'lost' => false } }))
Crm::PipelineInbox.find_or_create_by!(account: account, pipeline: pipeline, inbox: inbox) { |link| link.created_by = user }

# ---------- conexão pronta ----------
connection = Crm::MetaAdsConnection.find_or_initialize_by(account_id: account.id)
connection.update!(
  mode: 'facebook_login', status: 'active', access_token: "demo-#{SecureRandom.hex(24)}", last_checked_at: Time.current, last_error: nil,
  ad_account_id: AD_ACCOUNT_ID, ad_account_name: 'Conta de anúncios Loja Exemplo', ad_account_timezone: 'America/Sao_Paulo',
  pixel_id: '880000000002161', pixel_name: 'Pixel Loja Exemplo', verified_at: 30.days.ago,
  destinations: { 'whatsapp' => true, 'site' => false },
  # Cargas já feitas e leitura de agora: o painel não enfileira leitura da Meta (o Sidekiq não roda na demo).
  insights_backfilled_at: Time.current, links_backfilled_at: Time.current, insights_synced_at: Time.current
)
# Trava de leitura que uma tela aberta pegou: sem Sidekiq ninguém a solta, e o painel mostraria "atualizando..." por
# 10 min. Passados 2 min do seed, a tela volta a pedir leitura e a pegar a trava: rode o seed de novo antes dos prints.
%w[today recent].each { |scope| Crm::MetaAds::Insights::Refresh.release(connection.id, scope) }

# ---------- nomes e imagens (cache da Graph) ----------
now = Time.current
Crm::MetaAdObject.create!(account: account, meta_object_id: CAMPAIGN_ID, object_type: 'campaign', name: 'Vendas pelo WhatsApp · Outubro', fetched_at: now)
ADSETS.each do |id, name|
  Crm::MetaAdObject.create!(account: account, meta_object_id: id, object_type: 'adset', name: name, campaign_id: CAMPAIGN_ID,
                            destination_type: 'WHATSAPP', fetched_at: now)
end
ADS.each_with_index do |(id, (name, adset_id)), index|
  Crm::MetaAdObject.create!(account: account, meta_object_id: id, object_type: 'ad', name: name, campaign_id: CAMPAIGN_ID, adset_id: adset_id,
                            thumbnail_url: "https://picsum.photos/seed/lojaexemplo#{index + 1}/600/600",
                            preview_url: 'https://www.facebook.com/', fetched_at: now)
end

# ---------- gasto diário, 30 dias ----------
rows = ADS.flat_map do |id, (_name, adset_id, daily, conversations)|
  (0..29).map do |back|
    date = today - back
    spend = (daily * rng.rand(0.6..1.4)).round(2)
    impressions = (spend * rng.rand(70..110)).to_i
    {
      account_id: account.id, ad_account_id: AD_ACCOUNT_ID, ad_id: id, adset_id: adset_id, campaign_id: CAMPAIGN_ID, date: date,
      currency: 'BRL', spend: spend, impressions: impressions, reach: (impressions * 0.8).to_i, link_clicks: (impressions * 0.02).to_i,
      frequency: 1.25, conversations_started: back < conversations ? 1 : 0, actions: [], attribution_window: '7d_click',
      fetched_at: now, created_at: now, updated_at: now
    }
  end
end
Crm::MetaAdInsightDaily.insert_all!(rows) # rubocop:disable Rails/SkipsModelValidations

# ---------- conversas vindas dos anúncios e cards ----------
seq = 0
ADS.each do |ad_id, (name, adset_id, _daily, conversations, sales, open_quotes)|
  conversations.times do |n|
    seq += 1
    touched_at = zone.local(today.year, today.month, today.day, 9) - rng.rand(0..28).days + rng.rand(0..600).minutes
    touched_at = [touched_at, 30.minutes.ago].min
    contact = account.contacts.create!(name: "#{NOMES[seq % NOMES.size]} #{SOBRENOMES[seq % SOBRENOMES.size]}",
                                       identifier: "#{DEMO_TAG}-#{seq}", phone_number: format('+55119%08d', 70_000_000 + seq))
    contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: format('55119%08d', 70_000_000 + seq))
    touch = { 'source_id' => ad_id, 'source_type' => 'ad', 'headline' => name, 'ctwa_clid' => "#{DEMO_TAG}-clid-#{seq}" }
    conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open,
                                        additional_attributes: { 'demo' => DEMO_TAG, 'campaign' => touch })
    conversation.update_columns(created_at: touched_at, last_activity_at: touched_at + 2.hours) # rubocop:disable Rails/SkipsModelValidations
    Message.create!(account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                    content: PERGUNTAS[seq % PERGUNTAS.size], created_at: touched_at)
    Message.create!(account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: user,
                    content: 'Olá! Tudo bem? Já te passo os detalhes.', created_at: touched_at + rng.rand(2..45).minutes)
    Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: "#{DEMO_TAG}-clid-#{seq}", ad_account_id: AD_ACCOUNT_ID,
                            ad_id: ad_id, adset_id: adset_id, campaign_id: CAMPAIGN_ID, origin: 'whatsapp', certainty: 'ad',
                            first_touch: true, touched_at: touched_at)

    stage, status, value = if n < sales
                             [stages['Venda fechada'], :won, rng.rand(1900..3200)]
                           elsif n < sales + open_quotes
                             [stages[n.even? ? 'Proposta enviada' : 'Negociação'], :open, rng.rand(300..1500)]
                           elsif n.odd?
                             [stages['Qualificado'], :open, 0]
                           end
    next unless stage

    Crm::Card.create!(account: account, pipeline: pipeline, stage: stage, title: "Pedido de #{contact.name}", currency: 'BRL', status: status,
                      value_cents: value * 100, contact: contact, inbox: inbox, primary_conversation: conversation, owner: user,
                      external_id: "#{DEMO_TAG}-#{seq}", entered_stage_at: touched_at + 1.day, last_message_at: touched_at + 1.day)
  end
end

puts "demo 2778: conexão #{connection.id}, #{ADS.size} anúncios, #{seq} conversas, " \
     "#{Crm::Card.where(account_id: account.id).where('external_id LIKE ?', "#{DEMO_TAG}-%").count} cards"
puts "anúncio do detalhe: #{ADS.keys.first}"
