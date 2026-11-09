# Seed da demo da G43 (#2700): uma automação que mandou ao número novo do contato, para o print do histórico.
# Só demo local (bin/demo seed). Os jobs ficam na fila de teste, e o avanço da execução roda aqui, um por vez.
ActiveJob::Base.queue_adapter = :test
conta = Account.find(1)
conta.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens', 'automacao_editor')
dona = conta.administrators.first
Current.user = dona
canal = Channel::Sms.create!(account: conta, phone_number: '+5511900000000', provider_config: {})
caixa = conta.inboxes.create!(name: 'SMS da loja', channel: canal)
caixa.add_members([dona.id])
bruno = conta.contacts.create!(name: 'Bruno Lima', phone_number: '+5511900000019')
antigo = ContactInbox.create!(contact: bruno, inbox: caixa, source_id: '+5511900000019')
conversa = conta.conversations.create!(inbox: caixa, contact: bruno, contact_inbox: antigo, status: :open)
definicao = Autonomia::Automacao::Definicao.create!(account: conta, nome: 'Cliente que trocou de número', origem: 'manual', ligada_por: dona)
passos = [{ 'id' => 'retomar', 'tipo' => 'mensagem', 'texto' => ['Oi, Bruno! O recado da renovação: sua apólice vence em 30 dias.'] }]
definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }, autor: dona)
definicao.update!(ativa: true)
# O número antigo morreu: a última mensagem da empresa nele falhou (G43 só troca com esse sinal).
conversa.messages.create!(account: conta, inbox: caixa, message_type: :outgoing, content: 'Sua apólice vence em 30 dias.',
                          status: :failed)
bruno.update!(phone_number: '+5511988880019')
Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == Autonomia::Automacao::AvancarJob }.each do |job|
  Autonomia::Automacao::AvancarJob.perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
end
registro = Autonomia::Automacao::Registro.where(automacao_id: definicao.id).last
puts "automacao=#{definicao.id} resultado=#{registro&.resultado} numero_novo=#{registro&.dados&.dig('numero_novo')}"
