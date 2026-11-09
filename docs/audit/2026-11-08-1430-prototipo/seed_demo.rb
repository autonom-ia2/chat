# Demo do protótipo #1430 (só banco da demo `chatwoot_kitdemo_*`).
# Conta 1 com as flags de produção (todas ligadas desde 07/11; ext_2 até a posição 31, que é a
# agente_ferramentas_delegadas), Agentes e Fase 2 ligados, a agente Ana e duas funções:
# - "Supervisão": vê e edita os agentes, sem a chave de ferramentas (o administrador entrega na jornada 1);
# - "Sistemas": vê os agentes e tem a chave "Gerenciar ferramentas" (a Paula usa na jornada 2).
abort 'banco errado' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')

conta = Account.find(1)
PROD = { feature_flags: 9_094_241_222_486_130_663, feature_flags_ext_1: 9_223_372_036_854_742_007 }.freeze
conta.update_columns(feature_flags: PROD[:feature_flags], feature_flags_ext_1: PROD[:feature_flags_ext_1],
                     feature_flags_ext_2: (1 << 31) - 1)
conta.reload
conta.internal_attributes = conta.internal_attributes.to_h.merge('autonomia_agents_enabled' => true)
conta.save!
Autonomia::Agents::Fase2.ligar!(conta)

john = User.find_by!(email: 'john@acme.inc')
ana = Autonomia::Agents::Agent.find_or_initialize_by(account_id: conta.id, name: 'Ana')
ana.assign_attributes(
  agent_type: 'support', mode: 'guided', status: 'active', enabled: true, created_by: john,
  tone: 'Simpática e direta.',
  instruction: 'Você é a Ana. Atende os clientes, tira dúvidas sobre entregas e confere o endereço pelo CEP.'
)
ana.save!

supervisao = CustomRole.find_or_initialize_by(account_id: conta.id, name: 'Supervisão')
supervisao.update!(description: 'Acompanha o time e ajusta os agentes.',
                   permissions: %w[conversation_manage autonomia_view autonomia_manage])
sistemas = CustomRole.find_or_initialize_by(account_id: conta.id, name: 'Sistemas')
sistemas.update!(description: 'Liga os agentes aos sistemas da empresa.',
                 permissions: %w[conversation_participating_manage autonomia_view autonomia_tools_manage])

paula = User.find_or_initialize_by(email: 'paula@acme.inc')
paula.assign_attributes(name: 'Paula Lima', display_name: 'Paula', confirmed_at: Time.current)
paula.password = SecureRandom.hex(16) + 'aA1!' if paula.new_record?
paula.save!
# Mesma senha do John (a do db/seeds.rb), sem passar a senha por aqui: o kit loga com ela.
paula.update_column(:encrypted_password, john.encrypted_password)
membro = AccountUser.find_or_initialize_by(account: conta, user: paula)
membro.update!(role: :agent, custom_role: sistemas)

puts "agentes=#{Autonomia::Agents::Config.enabled?(conta)} delegadas=#{conta.feature_enabled?('agente_ferramentas_delegadas')} " \
     "ana=#{ana.id} supervisao=#{supervisao.id} sistemas=#{sistemas.id} paula=#{paula.id}"
