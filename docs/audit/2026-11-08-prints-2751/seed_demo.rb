# Seed da demo da G32 (#2751): conta 1 com as flags de produção, funil, página de agendamento, as automações que usam
# o gatilho da reunião do card, o lembrete antes da reunião e a condição "contato tem reunião marcada", e duas execuções
# reais (o lembrete e o card ganho que acorda com a reunião). Só no banco da demo (rails runner do bin/demo seed).
abort 'só em development' unless Rails.env.development?
abort 'banco fora do kit' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')

ENV['CRM_CALENDAR_MEETINGS_ENABLED'] = 'true'
ENV['CRM_KANBAN_ENABLED'] = 'true'
ActiveJob::Base.queue_adapter = :test
FILA = ActiveJob::Base.queue_adapter
DRENAR = [EventDispatcherJob, Autonomia::Automacao::AvancarJob, Autonomia::Automacao::EventoDoCardJob,
          Autonomia::Automacao::TempoDaAutomacaoJob].freeze

def drenar
  200.times do
    job = FILA.enqueued_jobs.find { |item| DRENAR.include?(item[:job]) }
    return unless job

    FILA.enqueued_jobs.delete(job)
    job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
  end
  raise 'fila não esvaziou'
end

conta = Account.find(1)
fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
conta.update!(locale: 'pt_BR', reporting_timezone: fuso.name)

# Flags: todas as do features.yml, menos as duas que ficaram fora em produção (07/11).
fora = %w[customer_base instagram_assisted_onboarding]
nomes = YAML.load_file(Rails.root.join('config/features.yml')).pluck('name') - fora
ligar = nomes.select { |nome| conta.respond_to?("feature_#{nome}=") }
conta.enable_features!(*ligar)
puts "flags ligadas: #{ligar.size}"

john = conta.users.find_by!(email: 'john@acme.inc')
Current.user = john
Current.account = conta
recepcao = User.find_by(email: 'recepcao@demo.invalid') ||
           User.create!(name: 'Recepção', email: 'recepcao@demo.invalid', password: SecureRandom.hex(16) + 'Aa1!', confirmed_at: Time.current)
AccountUser.find_or_create_by!(account: conta, user: recepcao) { |au| au.role = :agent }

canal = Channel::Whatsapp.new(account: conta, phone_number: '+5511900002751', provider: 'whatsapp_cloud',
                              provider_config: { 'api_key' => 'demo', 'phone_number_id' => '2751', 'business_account_id' => '2751' },
                              message_templates: [{ 'name' => 'endereco_entrevista', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                                    'category' => 'UTILITY',
                                                    'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, sua entrevista é {{2}}.' }] }])
canal.save!(validate: false)
inbox = Inbox.create!(account: conta, channel: canal, name: 'WhatsApp Clínica')
[john, recepcao].each { |pessoa| InboxMember.find_or_create_by!(user: pessoa, inbox: inbox) }

funil = conta.crm_pipelines.create!(name: 'Clientes', created_by: john, status: :active)
entrada = conta.crm_pipeline_stages.create!(pipeline: funil, name: 'Entrada', position: 0)
implantacao = conta.crm_pipeline_stages.create!(pipeline: funil, name: 'Implantação', position: 1)
entrevistas = conta.crm_agent_booking_profiles.create!(
  page_version: Crm::AgentBookingProfile::NEW_PAGE, title: 'Entrevistas', duration_minutes: 30, timezone: fuso.name,
  default_assignee: recepcao, locations: [{ 'type' => 'whatsapp_video' }], enabled: true, close_holidays: false
)

def ligada(conta, john, nome, receita)
  automacao = Autonomia::Automacao::Definicao.create!(account: conta, nome: nome, origem: 'manual')
  automacao.salvar_versao!(receita: receita, autor: john)
  recusa = automacao.reload.assumir_e_religar!(john, versao_id: automacao.versao_ativa_id)
  raise "#{nome} não ligou: #{recusa.motivo} #{recusa.problemas}" if recusa

  automacao
end

lembrete = ligada(conta, john, 'Lembrete da entrevista', {
                    'gatilho' => { 'tipo' => 'card.antes_da_reuniao', 'antes' => { 'valor' => 1, 'unidade' => 'dias' },
                                   'pagina_id' => entrevistas.id },
                    'passos' => [{ 'id' => 'lembra', 'tipo' => 'mensagem', 'texto' => ['Lembrete'],
                                   'modelo' => { 'nome' => 'endereco_entrevista', 'idioma' => 'pt_BR',
                                                 'variaveis' => [[{ '$valor' => 'contato.nome' }], [{ '$valor' => 'reuniao.inicio' }]] } }]
                  })
ligada(conta, john, 'Reunião marcada pela página', {
         'gatilho' => { 'tipo' => 'card.reuniao_marcada', 'funil_id' => funil.id, 'pagina_id' => entrevistas.id },
         'passos' => [{ 'id' => 'confirma', 'tipo' => 'mensagem', 'texto' => ['Recebemos o seu horário. Até lá!'] }]
       })
cliente_novo = ligada(conta, john, 'Cliente novo vai para Implantação', {
                        'gatilho' => { 'tipo' => 'card.ganho', 'funil_id' => funil.id },
                        'passos' => [
                          { 'id' => 'marcou', 'tipo' => 'esperar_ate',
                            'condicao' => { 'campo' => { '$valor' => 'contato.tem_reuniao_marcada' }, 'op' => 'igual', 'valor' => true },
                            'prazo' => { 'valor' => 30, 'unidade' => 'dias' }, 'se_vencer' => [] },
                          { 'id' => 'implantacao', 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/move', 'descricao' => 'Mover o card',
                            'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => { 'stage_id' => implantacao.id } }
                        ]
                      })
# Ligadas há 2 horas: o lembrete de amanhã cedo já está na janela de 1 dia e não é "passado" ao ligar.
Autonomia::Automacao::Definicao.where(account: conta).update_all(ligada_em: 2.hours.ago)
drenar

cliente = conta.contacts.create!(name: 'Júlia Prado', phone_number: '+5511900012751')
contact_inbox = ContactInbox.create!(contact: cliente, inbox: inbox, source_id: '5511900012751')
conversa = Conversation.create!(account: conta, inbox: inbox, contact: cliente, contact_inbox: contact_inbox, status: :open)
Message.create!(conversation: conversa, account: conta, inbox: inbox, message_type: :incoming, sender: cliente, content: 'Oi, quero marcar')
drenar

def novo_card(conta, john, funil, entrada, cliente, conversa, inbox, titulo)
  Crm::Cards::Creator.new(account: conta, user: john, params: {
                            pipeline_id: funil.id, stage_id: entrada.id, contact_id: cliente.id, owner_id: john.id,
                            conversation_id: conversa.id, inbox_id: inbox.id, title: titulo, currency: 'BRL'
                          }).perform
  drenar
  conta.crm_cards.find_by!(title: titulo)
end

def marca(conta, card, pagina, quando, fuso)
  params = { title: 'Entrevista', starts_at: quando, ends_at: quando + 30.minutes, timezone: fuso.name, extra_guests: [],
             location_type: 'whatsapp_video', booking_profile_id: pagina.id }
  Crm::Meetings::InternalCreator.new(account: conta, card: card, inbox: nil, scheduled_by: pagina.default_assignee,
                                     params: params).perform
  drenar
end

# Execução 1: o card ganho espera a reunião do contato; a reunião cai num card novo e ele vai para Implantação.
ganho = novo_card(conta, john, funil, entrada, cliente, conversa, inbox, 'Contrato da Júlia')
Crm::Cards::Closer.new(card: ganho, actor: john, result: 'won').perform
drenar
amanha = (Time.current + 23.hours).change(min: 0)
marca(conta, novo_card(conta, john, funil, entrada, cliente, conversa, inbox, 'Júlia - Entrevistas'), entrevistas, amanha, fuso)

# Execução 2: a varredura do lembrete (1 dia antes da entrevista de amanhã).
Autonomia::Automacao::TempoJob.perform_now
drenar

Autonomia::Automacao::Execucao.where(automacao_id: [lembrete.id, cliente_novo.id]).find_each do |execucao|
  puts "execução #{execucao.id} (#{execucao.automacao_id}): #{execucao.estado}"
end
puts "card ganho na etapa: #{ganho.reload.stage.name}"
puts "ids: lembrete=#{lembrete.id} cliente_novo=#{cliente_novo.id} conta=#{conta.id}"
