# Demo da vitrine de ferramentas prontas (#2858 F2). Só banco da demo `chatwoot_kitdemo_*`.
# Conta 1 com as flags de produção, ext_2 até a posição 39 (a da vitrine), Agentes e Fase 2 ligados,
# nicho "seguros/corretora" (o pacote da conta, para o destaque do ramo), dois agentes (Ana e Bruno) e a Paula:
# agente comum com a função "Sistemas", que tem a chave "Ferramentas dos agentes" (autonomia_tools_manage).
abort 'banco errado' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')

conta = Account.find(1)
PROD = { feature_flags: 9_094_241_222_486_130_663, feature_flags_ext_1: 9_223_372_036_854_742_007 }.freeze
# Bits crus das flags, como em produção: sem callbacks nem validação de propósito (só a demo).
conta.update_columns(feature_flags: PROD[:feature_flags], feature_flags_ext_1: PROD[:feature_flags_ext_1], # rubocop:disable Rails/SkipsModelValidations
                     feature_flags_ext_2: (1 << 39) - 1)
conta.reload
conta.internal_attributes = conta.internal_attributes.to_h.merge(
  'autonomia_agents_enabled' => true,
  Autonomia::Agents::Nicho::NICHO_KEY => 'seguros',
  Autonomia::Agents::Nicho::PERFIL_KEY => 'corretora'
)
conta.save!
Autonomia::Agents::Fase2.ligar!(conta)

john = User.find_by!(email: 'john@acme.inc')
AGENTES = {
  'Ana' => ['support', 'Atende os clientes, tira dúvidas e ajuda na cotação.'],
  'Bruno' => ['sdr', 'Faz o primeiro contato com quem chegou pelo anúncio.']
}.freeze
agentes = AGENTES.map do |nome, (tipo, instrucao)|
  agente = Autonomia::Agents::Agent.find_or_initialize_by(account_id: conta.id, name: nome)
  agente.assign_attributes(agent_type: tipo, mode: 'guided', status: 'active', enabled: true, created_by: john,
                           tone: 'Simpático e direto.', instruction: "Você é #{nome}. #{instrucao}")
  agente.save!
  agente
end

sistemas = CustomRole.find_or_initialize_by(account_id: conta.id, name: 'Sistemas')
sistemas.update!(description: 'Liga os agentes aos sistemas da empresa.',
                 permissions: %w[conversation_participating_manage autonomia_view autonomia_tools_manage])

paula = User.find_or_initialize_by(email: 'paula@acme.inc')
paula.assign_attributes(name: 'Paula Lima', display_name: 'Paula', confirmed_at: Time.current)
paula.password = "#{SecureRandom.hex(16)}aA1!" if paula.new_record?
paula.save!
# Mesma senha do John (a do db/seeds.rb), sem passar a senha por aqui: o kit loga com ela.
paula.update_column(:encrypted_password, john.encrypted_password) # rubocop:disable Rails/SkipsModelValidations
AccountUser.find_or_initialize_by(account: conta, user: paula).update!(role: :agent, custom_role: sistemas)

puts "vitrine=#{conta.feature_enabled?('agente_ferramentas_prontas_vitrine')} pacote=#{Autonomia::Segmentos::Pacotes.nome(conta).inspect} " \
     "agentes=#{agentes.map { |a| "#{a.name}:#{a.id}" }.join(',')} paula=#{paula.id}"
