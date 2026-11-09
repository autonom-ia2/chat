# Demo em tela real do bloco "Endereço e telefone" do agente (#1479 / #2723), com o backend novo. Só para o banco da
# demo (bin/demo seed).
#
# Quatro agentes fictícios na conta 1:
#   - "Recepção Clínica Exemplo": modo manual, com página de agendamento (página nova) de local presencial;
#   - "Recepção sem agenda": modo manual, sem página;
#   - "Atendente Loja Exemplo": conversando (modo guiado), com a mesma página presencial;
#   - "Atendente sem agenda": conversando, sem página.
# Nenhum tem endereço/telefone gravado: o bloco começa vazio.
#
# Repetível: apaga os agentes e a página que a rodada anterior criou (pelos nomes abaixo) e cria de novo.
abort 'seed só roda no banco da demo' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')

account = Account.find(1)
user = User.find_by!(email: 'john@acme.inc')

NOMES = ['Recepção Clínica Exemplo', 'Recepção sem agenda', 'Atendente Loja Exemplo', 'Atendente sem agenda'].freeze
PAGINA = 'Consulta presencial (demo 1479)'.freeze

Autonomia::Agents::Agent.where(account: account, name: NOMES).find_each(&:destroy!)
account.crm_agent_booking_profiles.where(title: PAGINA).find_each(&:destroy!)

pagina = account.crm_agent_booking_profiles.create!(
  title: PAGINA, page_version: Crm::AgentBookingProfile::NEW_PAGE, enabled: true, assignment_mode: :fixed,
  default_assignee: user, duration_minutes: 45, timezone: 'America/Sao_Paulo',
  locations: [{ 'type' => 'in_person', 'label' => 'Consultório Centro',
                'address' => 'Rua Barão de Jaguara, 1000, sala 12, Centro, Campinas - SP' }]
)

criar = lambda do |nome, modo, com_pagina|
  config = com_pagina ? { 'booking_page_id' => pagina.id } : {}
  Autonomia::Agents::Agent.create!(
    account: account, created_by: user, name: nome, mode: modo, agent_type: 'reception', status: :draft,
    instruction: 'Atenda com cordialidade e responda dúvidas sobre horários e localização.', config: config
  )
end

agentes = [
  criar.call(NOMES[0], :manual, true),
  criar.call(NOMES[1], :manual, false),
  criar.call(NOMES[2], :guided, true),
  criar.call(NOMES[3], :guided, false)
]

puts "pagina #{pagina.id}"
agentes.each { |agente| puts "agente #{agente.id} #{agente.mode} #{agente.name} pagina=#{agente.config['booking_page_id'].inspect}" }
