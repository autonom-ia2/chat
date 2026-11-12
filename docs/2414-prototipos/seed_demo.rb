# Demo em tela real das automações no CRM (#2499 F6.3/F6.4/F6.5). Só para o banco da demo (bin/demo seed). Cria os
# dados reais que as jornadas 1 e 2 abrem:
#   - funil "Vendas (demo 2414)" com cinco etapas;
#   - a regra antiga "Ligar no dia seguinte" em "Proposta enviada" (Crm::StageAutomation de verdade);
#   - Pedro Lima, com um card aberto em "Proposta enviada".
# As automações novas da etapa e do card são de verdade: monte-as no editor (README, "Preparar a demo"). A #2710 (reunião
# de quem já comprou) não está nesta branch. Repetível: os cards levam external_id "demo-2414-*" e são recriados.
abort 'seed só roda no banco da demo' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')

account = Account.find(1)
user = User.find_by!(email: 'john@acme.inc')
TAG = 'demo-2414'.freeze

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
# Rodadas antigas do seed marcavam o funil para o protótipo; a marca não serve mais.
pipeline.update!(metadata: pipeline.metadata.to_h.except('demo_prototipo_2414'))

contato = lambda do |nome, email|
  registro = account.contacts.find_or_initialize_by(email: email)
  registro.update!(name: nome, contact_type: :lead)
  registro
end
# E-mail pessoal (gmail): com domínio de empresa o painel cria a empresa pelo domínio e o card mostra a empresa.
pedro = contato.call('Pedro Lima', 'pedro.lima.demo2414@gmail.com')

antigos = Crm::Card.where(account: account).where('external_id LIKE ?', "#{TAG}-%")
# Rodadas antigas criavam reuniões nos cards da #2710: saem antes dos cards.
Crm::Meeting.where(card_id: antigos.select(:id)).destroy_all
antigos.find_each(&:destroy!)

regra = account.crm_stage_automations.find_or_initialize_by(stage: etapa['Proposta enviada'], name: 'Ligar no dia seguinte')
regra.update!(pipeline: pipeline, trigger_event: :on_enter, enabled: true, created_by: user)
regra.steps.destroy_all
regra.steps.create!(account: account, position: 0, delay_seconds: 1.day.to_i, action_type: :create_follow_up,
                    action_config: { 'title' => 'Ligar para o cliente' })

proposta = Crm::Card.create!(account: account, pipeline: pipeline, stage: etapa['Proposta enviada'], title: 'Proposta de serviço',
                             contact: pedro, status: :open, value_cents: 180_000, currency: 'BRL', owner: user,
                             external_id: "#{TAG}-proposta", entered_stage_at: Time.zone.now)

puts "funil #{pipeline.id} (#{pipeline.name}); etapa Proposta enviada #{etapa['Proposta enviada'].id}; regra #{regra.id}; Pedro #{proposta.id}"
