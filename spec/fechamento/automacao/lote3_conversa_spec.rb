require 'rails_helper'

# Fechamento do épico #2414, lote 3 da auditoria de 07/11 (#2680): a conversa de quem não tem e a resposta em outra
# conversa. A dona monta e liga pela API da tela; o card do lead nasce pelo mesmo Creator do formulário (sem conversa e
# sem dono), e o resto chega pelo despacho da plataforma, um job por vez. Os exemplos inteiros ficam no pendentes_spec
# até as outras lacunas deles fecharem; aqui ficam os passos que este lote destrava:
# - ex. 2, passos 2 e 3: o lead do formulário recebe a mensagem e a espera lê a resposta dele;
# - ex. 6, passo 2: no dia do aniversário gravado no contato, a mensagem abre a conversa;
# - ex. 1, passo 3, e ex. 19, passos 2, 3 e 6: o WhatsApp recusa, o mesmo texto sai por e-mail, e a resposta que chega
#   na conversa do e-mail conta para a espera.
RSpec.describe 'Fechamento #2414 · lote 3: conversa de quem não tem', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Ana Imóveis') }
  let(:whatsapp) { create_crm_whatsapp_api_inbox(account: account, members: [dona]) }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:funil) { create_crm_pipeline(account: account, user: dona).first }

  before do
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    clear_enqueued_jobs
  end

  after { Current.reset }

  # Um job por vez, como no Sidekiq, com o job do evento do card e os da varredura de tempo no meio.
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob,
                Autonomia::Automacao::TempoDaAutomacaoJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def ligada(nome, gatilho, *passos)
    automacao = montar_automacao(dona, account, nome: nome, receita: { gatilho: gatilho, passos: passos })
    ligar_automacao(dona, account, automacao)
    automacao
  end

  def chega_mensagem(conversa, **atributos)
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, sender: conversa.contact, **atributos)
    drenar
  end

  def espera_resposta(id, prazo)
    { id: id, tipo: 'esperar_ate', prazo: prazo,
      condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true } }
  end

  def avisa_a_dona(id, texto) = { id: id, tipo: 'avisar', para: { pessoas: [dona.id] }, texto: [texto] }

  describe 'ex. 2: o lead do formulário, que nasce sem conversa e sem dono' do
    let(:ana) { account.contacts.create!(name: 'Ana Lima', phone_number: '+5511900000002') }

    def lead_chega
      Crm::Cards::Creator.new(account: account, user: nil,
                              params: { pipeline_id: funil.id, stage_id: funil.stages.first.id, contact_id: ana.id,
                                        source: Crm::MetaAds::LeadForms::Importer::SOURCE, title: 'Ana Lima' }).perform
      drenar
    end

    it 'a mensagem abre a conversa pela caixa escolhida, e a resposta da Ana acorda a espera de 2 h', :aggregate_failures do
      oi = { id: 'oi', tipo: 'mensagem', texto: ['Oi, ', { '$valor' => 'contato.nome' }, '! Vi que você pediu o apartamento do Jardim.'] }
      automacao = ligada('Lead do anúncio', { tipo: 'card.criado', funil_id: funil.id, conversa_nova: { caixa_id: whatsapp.id } },
                         oi, espera_resposta('espera', { valor: 2, unidade: 'horas' }), avisa_a_dona('respondeu', 'A Ana respondeu'))

      lead_chega
      card = account.crm_cards.find_by!(contact: ana)
      conversa = card.primary_conversation

      expect(conversa).to have_attributes(inbox_id: whatsapp.id, contact_id: ana.id)
      expect(conversa.messages.outgoing.sole.content).to eq('Oi, Ana Lima! Vi que você pediu o apartamento do Jardim.')
      expect(historico_de(automacao)).to eq([['oi', 'ok', nil], ['espera', 'ok', nil]])

      travel(20.minutes) { chega_mensagem(conversa, message_type: :incoming, content: 'Quero visitar no sábado') }

      expect(historico_de(automacao).last).to eq(['respondeu', 'ok', nil])
    end
  end

  describe 'ex. 6: o aniversário gravado no contato, que não tem conversa' do
    let(:cliente) { account.contacts.create!(name: 'Juliana', phone_number: '+5511900000006') }

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'nascimento', attribute_display_name: 'Nascimento',
                                           attribute_model: 'contact_attribute', attribute_display_type: 'date')
    end

    it 'no dia, a varredura começa no contato e a mensagem abre a conversa na caixa escolhida', :aggregate_failures do
      parabens = { id: 'parabens', tipo: 'mensagem', texto: ['Feliz aniversário, ', { '$valor' => 'contato.nome' }, '!'] }
      gatilho = { tipo: 'contato.data', campo: 'nascimento', dias: 0, quando: 'antes', hora: 0, conversa_nova: { caixa_id: whatsapp.id } }
      automacao = travel_to(1.week.ago) { ligada('Aniversário', gatilho, parabens) }
      cliente.update!(custom_attributes: { 'nascimento' => Time.zone.today.iso8601 })

      Autonomia::Automacao::TempoJob.perform_now
      drenar

      conversa = Conversation.find_by!(inbox: whatsapp, contact: cliente)
      expect(conversa.messages.outgoing.sole.content).to eq('Feliz aniversário, Juliana!')
      expect(historico_de(automacao)).to eq([['parabens', 'ok', nil]])
    end
  end

  describe 'ex. 1 (passo 3) e ex. 19 (passos 2, 3 e 6): o WhatsApp recusa, o mesmo texto vai por e-mail' do
    let(:bruno) { account.contacts.create!(name: 'Bruno', phone_number: '+5511900000019', email: 'bruno@exemplo.com.br') }
    let(:conversa) { create_crm_conversation(account: account, inbox: whatsapp, contact: bruno) }

    def receita_do_ramo
      aviso = { id: 'aviso', tipo: 'mensagem', texto: ['Oi, ', { '$valor' => 'contato.nome' }, '. Sua apólice vence em 30 dias.'] }
      chegou = { id: 'chegou', tipo: 'esperar_ate', prazo: { valor: 1, unidade: 'horas' },
                 condicao: { campo: { '$valor' => 'envio.situacao' }, op: 'diferente', valor: 'saiu' } }
      email = { id: 'email', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Sua apólice'],
                texto: [{ '$valor' => 'envio.texto' }, ' Qual é o seu número novo?'] }
      falhou = { id: 'falhou', tipo: 'se', condicao: { campo: { '$valor' => 'envio.situacao' }, op: 'igual', valor: 'falhou' },
                 entao: [email, espera_resposta('resposta', { valor: 3, unidade: 'dias' }), avisa_a_dona('numero', 'O Bruno respondeu o e-mail')],
                 senao: [] }
      [aviso, chegou, falhou]
    end

    it 'a recusa acorda a espera, o e-mail leva o texto, e a resposta na conversa do e-mail conta', :aggregate_failures do
      automacao = ligada('Renovação', { tipo: 'conversa.resolvida' }, *receita_do_ramo)
      conversa.resolved!
      drenar

      travel(2.minutes) do
        conversa.messages.outgoing.sole.update!(status: :failed)
        drenar
      end

      conversa_do_email = Conversation.find_by!(inbox: caixa_de_email, contact: bruno)
      expect(conversa_do_email.messages.outgoing.sole.content)
        .to eq('Oi, Bruno. Sua apólice vence em 30 dias. Qual é o seu número novo?')

      travel(1.day) { chega_mensagem(conversa_do_email, message_type: :incoming, content: 'Meu número novo é 11 98888-0000') }

      expect(historico_de(automacao).map(&:first)).to eq(%w[aviso chegou chegou falhou email resposta resposta numero])
      expect(historico_de(automacao).last).to eq(['numero', 'ok', nil])
    end
  end
end
