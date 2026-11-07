# Seed da demo 2425-usar (protótipo "o texto está certo, usar mesmo assim" + "Ver o que eu li"). Só banco da demo.
raise 'banco fora da demo' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')

conta = Account.find(1)
Autonomia::Agents::Config.enable_for!(conta)
Autonomia::Agents::Fase2.ligar!(conta)

clara = Autonomia::Agents::Agent.kept.find_by(account: conta, name: 'Clara') || Autonomia::Agents::Agent.create!(
  account: conta, name: 'Clara', agent_type: 'support', mode: :guided, status: :active, enabled: true,
  instruction: 'Você é a Clara, da loja. Atenda os clientes com cordialidade.', tone: 'cordial',
  greeting: 'Oi! Aqui é a Clara.', fallback_message: 'Vou confirmar com a equipe e te retorno.',
  handoff_rule: 'Passe para a equipe o que não souber.', human_card: 'A Clara atende os clientes da loja.',
  config: { 'with_knowledge' => true }
)

# Um PDF digitado que a conferência reprovou como leitura ruim (o falso "ocr" da Issue #2425).
Autonomia::Agents::Source.where(autonomia_agent_id: clara.id, reference: 'manual-de-atendimento.pdf').destroy_all
fonte = Autonomia::Agents::Source.create!(
  account: conta, agent: clara, source_type: 'pdf', reference: 'manual-de-atendimento.pdf', kind: 'knowledge',
  status: :ready, review_status: 'needs_resend', reviewed_at: Time.current,
  metadata: { 'conferencia' => { 'problema' => 'ocr', 'amostra' => [] }, 'hash_do_texto' => 'demo' }
)
[
  'Sumário. 1. Horário de atendimento.......... 3. 2. Trocas e devoluções.......... 4. 3. Entregas.......... 6.',
  '1. Horário de atendimento. A loja abre de segunda a sexta, das 9h às 18h, e aos sábados, das 9h às 13h.',
  'Fora do horário, o cliente pode deixar a mensagem: a equipe responde no próximo dia útil, em ordem de chegada.',
  '2. Trocas e devoluções. O cliente tem 7 dias corridos a partir do recebimento para pedir a troca ou a devolução.',
  'O produto precisa estar na embalagem original, com a etiqueta, e acompanhado da nota fiscal.',
  '3. Entregas. Pedidos feitos até as 12h saem no mesmo dia. O prazo para a capital é de 1 a 2 dias úteis.',
  'Para o interior, o prazo é de 3 a 5 dias úteis. O frete é grátis nas compras acima de R$ 199.',
  '4. Pagamento. Aceitamos Pix, cartão de crédito em até 6 vezes sem juros e boleto à vista.'
].each_with_index do |texto, indice|
  Autonomia::Agents::KnowledgeEntry.create!(account: conta, agent: clara, source: fonte, status: :ready,
                                            chunk_index: indice, content: texto)
end
puts "agente=#{clara.id} fonte=#{fonte.id}"
