# Demo em tela real dos protótipos de automação no CRM (#2499 F6.3/F6.4/F6.5 e #2710). Só para o banco da demo
# (bin/demo seed). As automações e a reunião vêm do adaptador falso do painel; aqui só entram os cards reais que as
# jornadas abrem:
#   - funil "Vendas (demo 2414)" com cinco etapas;
#   - Maria Souza, já cliente, com um card ganho em 03/11 e um card novo aberto ("Agendou pela página");
#   - Pedro Lima, com um card aberto em "Proposta enviada".
# Repetível: os cards levam external_id "demo-2414-*" e são recriados a cada rodada.
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

contato = lambda do |nome, email, tipo|
  registro = account.contacts.find_or_initialize_by(email: email)
  registro.update!(name: nome, contact_type: tipo)
  registro
end
maria = contato.call('Maria Souza', 'maria.souza@exemplo.com.br', :customer)
pedro = contato.call('Pedro Lima', 'pedro.lima@exemplo.com.br', :lead)

Crm::Card.where(account: account).where('external_id LIKE ?', "#{TAG}-%").find_each(&:destroy!)

criar = lambda do |chave, titulo, pessoa, nome_da_etapa, status, valor, closed_at = nil|
  Crm::Card.create!(account: account, pipeline: pipeline, stage: etapa[nome_da_etapa], title: titulo, contact: pessoa,
                    status: status, value_cents: valor * 100, currency: 'BRL', owner: user, closed_at: closed_at,
                    external_id: "#{TAG}-#{chave}", entered_stage_at: Time.zone.now)
end

ganho = criar.call('ganho', 'Plano anual', maria, 'Venda fechada', :won, 2400, Time.zone.local(2026, 11, 3, 15, 30))
novo = criar.call('novo', 'Agendou pela página', maria, 'Novo contato', :open, 0)
proposta = criar.call('proposta', 'Proposta de serviço', pedro, 'Proposta enviada', :open, 1800)

puts "funil #{pipeline.id} (#{pipeline.name}); etapa Novo contato #{etapa['Novo contato'].id}"
puts "card ganho #{ganho.id}, card novo #{novo.id}, card com proposta #{proposta.id}"
