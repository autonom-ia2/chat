# Demo da F3 da vitrine (#2858): o agente já nasce com as ferramentas prontas. Só banco da demo `chatwoot_kitdemo_*`.
# Sem IA paga: a escolha do Construtor e a sugestão do cartão entram prontas no config, como o servidor as grava.
# - Helena: rascunho com instrução e a escolha do Construtor (fipe, cep, cpf); abre direto na Confira.
# - Bruno: agente que já atende, com a sugestão "Valor do carro" guardada com a assinatura atual.
# - Rui: agente comum com a função "Agentes", que cria agentes mas não tem a chave "Ferramentas dos agentes".
abort 'banco errado' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')

conta = Account.find(1)
abort 'flag do Construtor desligada' unless Autonomia::FerramentasProntas.construtor?(conta)
john = User.find_by!(email: 'john@acme.inc')

helena = Autonomia::Agents::Agent.find_or_initialize_by(account_id: conta.id, name: 'Helena')
helena.assign_attributes(agent_type: 'support', mode: 'guided', status: 'draft', enabled: false, created_by: john,
                         tone: 'Simpático e direto.',
                         instruction: 'Você é Helena. Cota seguro auto: pede o modelo e o ano do carro e o CEP de onde ele dorme.',
                         human_card: 'A Helena cota seguro auto pelo WhatsApp.')
limpo = helena.config.to_h.except('prontas_dispensadas', 'prontas_sugestao')
helena.config = limpo.merge('ferramentas_sugeridas' => %w[fipe cep cpf], 'response_window' => 'always')
helena.save!
helena.tools.where.not(fonte_pronta: nil).find_each(&:destroy!)

bruno = Autonomia::Agents::Agent.find_by!(account_id: conta.id, name: 'Bruno')
bruno.tools.where(fonte_pronta: 'fipe').find_each(&:destroy!)
sugestao = Autonomia::FerramentasProntas::SugestaoParaAgente
sugestao.gravar(bruno) do |config|
  { sugestao::SUGESTAO => { 'chaves' => %w[fipe], 'assinatura' => sugestao.assinatura(bruno), 'em' => Time.current.iso8601 },
    sugestao::DISPENSADAS => Array(config[sugestao::DISPENSADAS]) - %w[fipe] }
end

agentes = CustomRole.find_or_initialize_by(account_id: conta.id, name: 'Agentes')
agentes.update!(description: 'Cria e ajusta os agentes de IA.',
                permissions: %w[conversation_participating_manage autonomia_view autonomia_manage])
rui = User.find_or_initialize_by(email: 'rui@acme.inc')
rui.assign_attributes(name: 'Rui Prado', display_name: 'Rui', confirmed_at: Time.current)
rui.password = "#{SecureRandom.hex(16)}aA1!" if rui.new_record?
rui.save!
rui.update_column(:encrypted_password, john.encrypted_password) # rubocop:disable Rails/SkipsModelValidations
AccountUser.find_or_initialize_by(account: conta, user: rui).update!(role: :agent, custom_role: agentes)

puts "helena=#{helena.id} bruno=#{bruno.id} cartao=#{sugestao.para_tela(bruno.reload).inspect} rui=#{rui.id}"
