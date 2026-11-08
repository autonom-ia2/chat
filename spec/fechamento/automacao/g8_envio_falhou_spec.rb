require 'rails_helper'

# Fechamento do épico #2414, ex. 19 ("Cliente que sumiu do WhatsApp"): G8 (#2637, o gatilho da mensagem que falhou) e
# o número novo (#2700). A dona monta e liga pela API da tela; a recusa chega como a da Meta, depois do envio, e o
# resto pelo despacho da plataforma, um job por vez. O exemplo inteiro fica no pendentes_spec até as outras lacunas dele
# fecharem; aqui ficam os passos que este PR destrava:
# - começa: o WhatsApp recusa a mensagem que a equipe mandou;
# - passo 2: tem e-mail, então vai o mesmo conteúdo, com a pergunta do número novo;
# - passo 4: o recado sai pelo modelo "Retomar contato" no número novo, não na conversa do número antigo;
# - passos 5 e 7: espera o WhatsApp dizer se chegou; falhou de novo, avisa a Fernanda.
# O passo 3 (a IA tira o número da resposta e atualiza o contato) é de outra lacuna: aqui a equipe atualiza o telefone.
RSpec.describe 'Fechamento #2414 · G8: o envio que falhou', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:modelo_retomar) do
    { 'name' => 'retomar_contato', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, aqui é da corretora. Podemos continuar por aqui?' }] }
  end
  let(:fernanda) { create(:user, account: account, role: :administrator, name: 'Fernanda') }
  let(:canal) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [modelo_retomar])
  end
  let(:whatsapp) { canal.inbox.tap { |inbox| inbox.add_members([fernanda.id]) } }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:bruno) { account.contacts.create!(name: 'Bruno', phone_number: '+5511900000019', email: 'bruno@exemplo.com.br') }
  let(:conversa) do
    contact_inbox = ContactInboxBuilder.new(contact: bruno, inbox: whatsapp, source_id: nil).perform
    ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open'), contact_inbox: contact_inbox).perform.reload
  end

  before do
    stub_request(:post, ->(uri) { uri.host == 'graph.facebook.com' })
      .to_return(status: 200, body: { messages: [{ id: 'wamid.FECHAMENTO' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
    flags_do_piloto(account)
    clear_enqueued_jobs
  end

  after { Current.reset }

  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::AvancarJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def condicao(caminho, operador, valor = nil) = { campo: { '$valor' => caminho }, op: operador, valor: valor }.compact

  def avisa(id, texto) = { id: id, tipo: 'avisar', para: { pessoas: [fernanda.id] }, texto: [texto] }

  def receita
    email = { id: 'email', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Seu WhatsApp'],
              texto: [{ '$valor' => 'envio.texto' }, ' Seu WhatsApp mudou? Qual é o número novo?'] }
    resposta = { id: 'resposta', tipo: 'esperar_ate', prazo: { valor: 3, unidade: 'dias' },
                 condicao: condicao('conversa.cliente_respondeu', 'igual', true) }
    recado = { id: 'recado', tipo: 'mensagem', texto: ['Oi, podemos continuar por aqui?'],
               modelo: { nome: 'retomar_contato', idioma: 'pt_BR', variaveis: [[{ '$valor' => 'contato.nome' }]] } }
    chegou = { id: 'chegou', tipo: 'esperar_ate', prazo: { valor: 1, unidade: 'horas' }, condicao: condicao('envio.situacao', 'diferente', 'saiu') }
    de_novo = { id: 'de_novo', tipo: 'se', condicao: condicao('envio.situacao', 'igual', 'falhou'),
                entao: [avisa('resumo', 'O Bruno não recebe nem no número novo')], senao: [avisa('voltou', 'O Bruno voltou')] }
    { gatilho: { tipo: 'mensagem.falhou' },
      passos: [{ id: 'tem_email', tipo: 'se', condicao: condicao('contato.email', 'preenchido'), entao: [email, resposta, recado, chegou, de_novo],
                 senao: [] }] }
  end

  it 'a recusa leva o texto ao e-mail, o recado vai ao número novo, e a nova falha avisa a Fernanda', :aggregate_failures do
    conversa
    automacao = montar_automacao(fernanda, account, nome: 'Cliente que sumiu do WhatsApp', receita: receita)
    ligar_automacao(fernanda, account, automacao)
    aviso = create(:message, account: account, conversation: conversa, inbox: whatsapp, sender: fernanda, message_type: :outgoing,
                             content: 'Bruno, sua apólice vence em 30 dias.')
    drenar

    travel(2.minutes) do
      aviso.update!(status: :failed)
      drenar
    end

    conversa_do_email = Conversation.find_by!(inbox: caixa_de_email, contact: bruno)
    expect(conversa_do_email.messages.outgoing.sole.content).to eq('Bruno, sua apólice vence em 30 dias. Seu WhatsApp mudou? Qual é o número novo?')

    travel(1.day) do
      create(:message, account: account, conversation: conversa_do_email, inbox: caixa_de_email, sender: bruno, message_type: :incoming,
                       content: 'Troquei de número: 11 98888-0000')
      bruno.update!(phone_number: '+5511988880000')
      drenar
    end

    numero_novo = Conversation.where(inbox: whatsapp, contact: bruno).where.not(id: conversa.id).sole
    recado = numero_novo.messages.outgoing.sole
    expect(numero_novo.contact_inbox.source_id).to eq('5511988880000')
    expect(recado.content).to eq('Oi Bruno, aqui é da corretora. Podemos continuar por aqui?')
    expect(conversa.messages.outgoing.where.not(id: aviso.id)).to be_empty

    travel(1.day + 5.minutes) do
      recado.update!(status: :failed)
      drenar
    end

    expect(historico_de(automacao).map(&:first)).to eq(%w[tem_email email resposta resposta recado chegou chegou de_novo resumo])
    expect(historico_de(automacao).last).to eq(['resumo', 'ok', nil])
    expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).count).to eq(1)
  end
end
