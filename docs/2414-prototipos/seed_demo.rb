# Demo em tela real dos protótipos de automação no CRM (#2499 F6.3/F6.4/F6.5 e #2710). Só para o banco da demo
# (bin/demo seed). Cria os dados reais que as jornadas abrem:
#   - funil "Vendas (demo 2414)" com cinco etapas e a marca `metadata.demo_prototipo_2414 = { etapa_id }`, que liga o
#     protótipo só neste funil (e só no build de desenvolvimento do painel);
#   - a regra antiga "Ligar no dia seguinte" em "Proposta enviada" (Crm::StageAutomation de verdade);
#   - Pedro Lima, com um card aberto em "Proposta enviada" (as automações novas do card saem do adaptador falso);
#   - #2710, variante 1 (o card ganho recebe a reunião, nenhum card novo nasce): Maria Souza, já cliente, com o card
#     ganho "Plano anual" e a reunião marcada pela página nele;
#   - #2710, variante 2 (card novo, casado pelo contato): Ana Costa, já cliente, com o card ganho "Plano mensal" e o
#     card novo que a página criou ("source" public_link) com a reunião.
# As reuniões são Crm::Meeting de verdade, daqui a 3 dias às 10h, com a atividade `meeting_scheduled` na linha do
# tempo: a Agenda do card e o "O que já aconteceu" mostram o que existe no banco. Repetível: os cards levam
# external_id "demo-2414-*" e são recriados a cada rodada.
abort 'seed só roda no banco da demo' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')

account = Account.find(1)
user = User.find_by!(email: 'john@acme.inc')
TAG = 'demo-2414'.freeze
MARCA = 'demo_prototipo_2414'.freeze

pipeline = account.crm_pipelines.find_or_create_by!(name: 'Vendas (demo 2414)') do |novo|
  novo.created_by = user
  novo.status = :active
end
etapas = [['Novo contato', false, false], ['Proposta enviada', false, false], ['Negociação', false, false],
          ['Venda fechada', true, false], ['Perdido', false, true]]
etapa = etapas.each_with_index.to_h do |(nome, ganho, perdido), posicao|
  registro = account.crm_pipeline_stages.find_or_initialize_by(pipeline: pipeline, name: nome)
  registro.update!(position: posicao, is_won_stage: ganho, is_lost_stage: perdido)
  [nome, registro]
end
pipeline.update!(metadata: pipeline.metadata.to_h.merge(MARCA => { 'etapa_id' => etapa['Proposta enviada'].id }))

comprou_em = 9.days.ago.change(hour: 15, min: 30)
contato = lambda do |nome, email, tipo|
  registro = account.contacts.find_or_initialize_by(email: email)
  registro.update!(name: nome, contact_type: tipo, customer_since: tipo == :customer ? comprou_em : nil)
  registro
end
maria = contato.call('Maria Souza', 'maria.souza@exemplo.com.br', :customer)
ana = contato.call('Ana Costa', 'ana.costa@exemplo.com.br', :customer)
pedro = contato.call('Pedro Lima', 'pedro.lima@exemplo.com.br', :lead)

antigos = Crm::Card.where(account: account).where('external_id LIKE ?', "#{TAG}-%")
Crm::Meeting.where(card_id: antigos.select(:id)).destroy_all
antigos.find_each(&:destroy!)

regra = account.crm_stage_automations.find_or_initialize_by(stage: etapa['Proposta enviada'], name: 'Ligar no dia seguinte')
regra.update!(pipeline: pipeline, trigger_event: :on_enter, enabled: true, created_by: user)
regra.steps.destroy_all
regra.steps.create!(account: account, position: 0, delay_seconds: 1.day.to_i, action_type: :create_follow_up,
                    action_config: { 'title' => 'Ligar para o cliente' })

criar = lambda do |chave, titulo, pessoa, nome_da_etapa, status, valor, closed_at: nil, source: nil|
  Crm::Card.create!(account: account, pipeline: pipeline, stage: etapa[nome_da_etapa], title: titulo, contact: pessoa,
                    status: status, value_cents: valor * 100, currency: 'BRL', owner: user, closed_at: closed_at,
                    source: source, external_id: "#{TAG}-#{chave}", entered_stage_at: Time.zone.now)
end

# A reunião que a página de agendamento marcou (source public_link), com a linha na linha do tempo.
reuniao = lambda do |card, pessoa|
  inicio = 3.days.from_now.change(hour: 10)
  meeting = Crm::Meeting.create!(account: account, card: card, created_by: user, title: "Reunião com #{pessoa.name}",
                                 starts_at: inicio, ends_at: inicio + 30.minutes, timezone: 'America/Sao_Paulo',
                                 provider: :internal, online_meeting_type: :no_online, status: :scheduled,
                                 source: 'public_link')
  Crm::ActivityLogger.new(
    card: card, actor: user, event_type: 'meeting_scheduled',
    payload: { meeting_id: meeting.id, title: meeting.title, starts_at: meeting.starts_at.iso8601,
               provider: meeting.provider, location_type: meeting.online_meeting_type, guests_count: 0,
               source: meeting.source }
  ).perform
  meeting
end

proposta = criar.call('proposta', 'Proposta de serviço', pedro, 'Proposta enviada', :open, 1800)

ganho_maria = criar.call('ganho-maria', 'Plano anual', maria, 'Venda fechada', :won, 2400, closed_at: comprou_em)
reuniao.call(ganho_maria, maria)

ganho_ana = criar.call('ganho-ana', 'Plano mensal', ana, 'Venda fechada', :won, 300, closed_at: comprou_em)
novo_ana = criar.call('novo-ana', 'Ana Costa - Agenda', ana, 'Novo contato', :open, 0, source: 'public_link')
reuniao.call(novo_ana, ana)

puts "funil #{pipeline.id} (#{pipeline.name}); etapa Proposta enviada #{etapa['Proposta enviada'].id}; regra #{regra.id}"
puts "Pedro #{proposta.id}; variante 1: ganho Maria #{ganho_maria.id}; variante 2: ganho Ana #{ganho_ana.id}, novo Ana #{novo_ana.id}"
