require 'rails_helper'

# O passo "email" (#2414 G2): o e-mail ao contato pela caixa de e-mail da conta, numa conversa nova, pelo envio de
# sempre da caixa. E o laço com o autoresponder do outro lado, que a Escuta corta na entrada.
RSpec.describe Autonomia::Automacao::PassoDeEmail, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { create(:channel_email, account: account).inbox }
  let(:contato) { create(:contact, account: account, email: 'cliente@exemplo.com', name: 'Carla') }
  let(:whatsapp) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, contact: contato, inbox: whatsapp) }
  let(:passo) { email_passo('p1') }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  after { Current.reset }

  def email_passo(id, caixa_id: caixa.id, assunto: ['Seu pedido'], texto: ['Oi ', { '$valor' => 'contato.nome' }, ', seu pedido saiu.'])
    { 'id' => id, 'tipo' => 'email', 'caixa_id' => caixa_id, 'assunto' => assunto, 'texto' => texto }
  end

  def rodar(alvo, passos = [passo])
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, admin, passos), alvo) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def conversas_de_email = Conversation.where(inbox: caixa)

  describe 'envio' do
    it 'abre conversa nova na caixa de e-mail com o assunto e manda o texto com os valores, sem remetente e com a marca',
       :aggregate_failures do
      execucao = rodar(conversa)

      nova = conversas_de_email.sole
      mensagem = nova.messages.outgoing.sole
      expect(nova.contact).to eq(contato)
      expect(nova.contact_inbox.source_id).to eq('cliente@exemplo.com')
      expect(nova.additional_attributes['mail_subject']).to eq('Seu pedido')
      expect(mensagem.content).to eq('Oi Carla, seu pedido saiu.')
      expect(mensagem).to have_attributes(private: false, sender: nil)
      expect(mensagem.content_attributes).to include('automacao_id' => execucao.automacao_id, 'execucao_id' => execucao.id, 'passo' => 'p1')
      expect(registros(execucao)).to eq([['p1', 'ok', nil]])
      expect(conversa.messages.outgoing).to be_empty
    end

    # O envio é o da caixa, sem mailer novo: o SendReplyJob leva a mensagem ao ConversationReplyMailer (SMTP), que lê o
    # assunto da conversa e manda ao e-mail do contato (o próprio mailer tem spec para isso).
    it 'o e-mail sai pelo envio da caixa (SendReplyJob → ConversationReplyMailer) sem erro', :aggregate_failures do
      rodar(conversa)
      mensagem = conversas_de_email.sole.messages.outgoing.sole
      envio = instance_double(ActionMailer::MessageDelivery, deliver_now: instance_double(Mail::Message, message_id: 'mid-1'))
      mailer = instance_double(ConversationReplyMailer, email_reply: envio)
      allow(ConversationReplyMailer).to receive(:with).and_return(mailer)

      SendReplyJob.perform_now(mensagem.id)

      expect(mailer).to have_received(:email_reply).with(mensagem)
      expect(mensagem.reload).to have_attributes(status: 'sent', source_id: 'mid-1')
    end

    it 'cada envio abre conversa nova; a caixa que trava numa conversa só reaproveita a dela' do
      rodar(conversa)
      rodar(conversa)
      expect(conversas_de_email.count).to eq(2)

      caixa.update!(lock_to_single_conversation: true)
      rodar(conversa, [email_passo('p1', assunto: ['Outro assunto'])])
      expect(conversas_de_email.count).to eq(2)
      # O envio lê o assunto da conversa: a reaproveitada leva o deste envio.
      expect(conversas_de_email.order(:id).last.additional_attributes['mail_subject']).to eq('Outro assunto')
    end

    it 'o assunto em várias linhas vira uma linha só' do
      rodar(conversa, [email_passo('p1', assunto: ["Seu pedido\n  ", { '$valor' => 'contato.nome' }])])
      expect(conversas_de_email.sole.additional_attributes['mail_subject']).to eq('Seu pedido Carla')
    end

    it 'no card, manda ao contato do card' do
      funil = create_crm_pipeline(account: account, user: admin)
      card = Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Seguro auto', currency: 'BRL',
                               contact: contato)
      execucao = Autonomia::Automacao::Execucao.new(automacao: automacao_ligada(account, admin, [passo]), account: account)

      resultado = described_class.new(execucao: execucao, passo: passo, alvo: card).executar

      expect(resultado.tipo).to eq(:ok)
      expect(conversas_de_email.sole.contact).to eq(contato)
    end

    it 'card sem contato pula com contato_sem_email' do
      funil = create_crm_pipeline(account: account, user: admin)
      card = Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Sem contato', currency: 'BRL')
      execucao = Autonomia::Automacao::Execucao.new(automacao: automacao_ligada(account, admin, [passo]), account: account)

      resultado = described_class.new(execucao: execucao, passo: passo, alvo: card).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'contato_sem_email'])
      expect(conversas_de_email).to be_empty
    end

    it 'no contato, manda a ele' do
      execucao = Autonomia::Automacao::Execucao.new(automacao: automacao_ligada(account, admin, [passo]), account: account)

      resultado = described_class.new(execucao: execucao, passo: passo, alvo: contato).executar

      expect(resultado.tipo).to eq(:ok)
      expect(conversas_de_email.sole.contact).to eq(contato)
    end
  end

  describe 'pula, sem abrir conversa' do
    it 'contato sem e-mail' do
      contato.update!(email: nil)
      expect(registros(rodar(conversa))).to eq([%w[p1 pulado contato_sem_email]])
      expect(conversas_de_email).to be_empty
    end

    it 'contato que pediu para não receber' do
      contato.opt_out!(source: 'manual')
      expect(registros(rodar(conversa))).to eq([%w[p1 pulado contato_nao_recebe]])
      expect(conversas_de_email).to be_empty
    end

    it 'e-mail bloqueado na conta (devolução, reclamação, descadastro)' do
      EmailSuppression.create!(account: account, email: 'Cliente@Exemplo.com', reason: 'hard_bounce')
      expect(registros(rodar(conversa))).to eq([%w[p1 pulado email_bloqueado]])
      expect(conversas_de_email).to be_empty
    end

    it 'caixa de e-mail de outra conta, na execução, é como caixa que não existe' do
      de_fora = create(:channel_email).inbox
      execucao = Autonomia::Automacao::Execucao.new(automacao: automacao_ligada(account, admin, [passo]), account: account)

      resultado = described_class.new(execucao: execucao, passo: email_passo('p1', caixa_id: de_fora.id), alvo: conversa).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'caixa_de_email_indisponivel'])
      expect(Conversation.where(inbox: de_fora)).to be_empty
    end

    # A Receita recusa a caixa errada ao salvar; aqui a caixa muda depois de salva.
    it 'caixa que deixou de ser de e-mail depois de salva' do
      definicao = automacao_ligada(account, admin, [passo])
      caixa.update_column(:channel_type, 'Channel::Api') # rubocop:disable Rails/SkipsModelValidations

      execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }
      expect(registros(execucao)).to eq([%w[p1 pulado caixa_de_email_indisponivel]])
      expect(conversas_de_email).to be_empty
    end

    it 'valor vazio no assunto ou no texto' do
      contato.update!(name: '')
      execucao = rodar(conversa, [email_passo('p1', assunto: [{ '$valor' => 'contato.nome' }])])
      expect(registros(execucao)).to eq([%w[p1 pulado faltou_valor]])
      expect(conversas_de_email).to be_empty
    end

    it 'assunto que ficou em branco' do
      execucao = rodar(conversa, [email_passo('p1', assunto: ['   '])])
      expect(registros(execucao)).to eq([%w[p1 pulado texto_vazio]])
    end
  end

  # No OSS só o administrador liga automação; no EE, a função personalizada com automation_manage pode ligar sem estar
  # na caixa de e-mail. O passo pergunta a caixa, não a função.
  it 'quem ligou fora da caixa de e-mail não manda: o passo pede a pausa (sem_acesso), sem abrir conversa', :aggregate_failures do
    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: whatsapp)
    definicao = automacao_ligada(account, admin, [passo])
    definicao.update_column(:ligada_por_id, agente.id) # rubocop:disable Rails/SkipsModelValidations
    execucao = Autonomia::Automacao::Execucao.new(automacao: definicao.reload, account: account)

    resultado = described_class.new(execucao: execucao, passo: passo, alvo: conversa).executar

    expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'quem_ligou_sem_acesso'])
    expect(conversas_de_email).to be_empty

    create(:inbox_member, user: agente, inbox: caixa)
    expect(described_class.new(execucao: execucao, passo: passo, alvo: conversa).executar.tipo).to eq(:ok)
  end

  it 'a Receita recusa caixa que não é de e-mail da conta' do
    outra_conta = create(:channel_email).inbox
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [email_passo('p1', caixa_id: outra_conta.id)] }
    expect(Autonomia::Automacao::Receita.new(receita, conta: account).problemas)
      .to eq([I18n.t('autonomia.automacao.receita.caixa_de_email_invalida', passo: 'p1', id: outra_conta.id)])
  end

  it 'o esquema aceita assunto de até 150 letras escritas e recusa o mais longo' do
    receita = ->(assunto) { { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [email_passo('p1', assunto: [assunto])] } }
    expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call('a' * 150))).to be(true)
    expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call('a' * 151))).to be(false)
  end

  # O laço com o autoresponder: "mensagem recebida → manda e-mail". A resposta automática ("estou de férias") chega como
  # mensagem do contato na conversa de e-mail; a cadeia não a vê. Sem o corte da Escuta, cada resposta abriria outra
  # execução e outro e-mail, sem fim.
  describe 'laço com o autoresponder' do
    let(:recebida) { { 'campo' => { '$valor' => 'mensagem.tipo' }, 'op' => 'igual', 'valor' => 'recebida' } }
    let(:gatilho) { { 'tipo' => 'mensagem.criada', 'filtros' => [recebida] } }
    let(:conversa_de_email) { create(:conversation, account: account, contact: contato, inbox: caixa) }

    def chegou(conversa, auto_reply:)
      create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming, sender: contato,
                       content: 'Estou de férias até segunda.', content_attributes: { email: { auto_reply: auto_reply } })
    end

    def ouvir(mensagem)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::Escuta.mensagem_criada(mensagem) }
    end

    it 'a resposta automática não começa a automação; a mensagem de gente começa', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [passo], gatilho: gatilho)

      ouvir(chegou(conversa_de_email, auto_reply: true))
      expect(Autonomia::Automacao::Execucao.where(automacao: definicao)).to be_empty

      ouvir(chegou(conversa_de_email, auto_reply: false))
      expect(Autonomia::Automacao::Execucao.where(automacao: definicao).count).to eq(1)
    end

    it 'conversa reaberta: decide a última mensagem recebida, não a marca de quando ela nasceu', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [passo], gatilho: { 'tipo' => 'conversa.aberta' })
      conversa_de_email.update!(additional_attributes: { 'auto_reply' => true })
      execucoes = Autonomia::Automacao::Execucao.where(automacao: definicao)

      chegou(conversa_de_email, auto_reply: true)
      Autonomia::Automacao::Escuta.comecar(conversa_de_email, 'conversa.aberta')
      expect(execucoes).to be_empty

      chegou(conversa_de_email, auto_reply: false)
      Autonomia::Automacao::Escuta.comecar(conversa_de_email, 'conversa.aberta')
      expect(execucoes.count).to eq(1)
    end

    it 'a conversa que a resposta automática abriu não dispara "conversa criada"' do
      definicao = automacao_ligada(account, admin, [passo], gatilho: { 'tipo' => 'conversa.criada' })
      conversa_de_email.update!(additional_attributes: { 'auto_reply' => true })

      Autonomia::Automacao::Escuta.comecar(conversa_de_email, 'conversa.criada')
      expect(Autonomia::Automacao::Execucao.where(automacao: definicao)).to be_empty
    end
  end

  # O auto-laço sem autoresponder: "conversa criada → e-mail" abre uma conversa nova na caixa de e-mail, que é também
  # uma conversa criada. Quem segura é a cadeia comum (F1), que viaja no evento da conversa nova (CadeiaNoDespacho) até a
  # Escuta. Ponta a ponta, com o despacho de verdade (EventDispatcherJob) e a rodada (AvancarJob) drenados.
  describe 'auto-laço pelo despacho real' do
    let(:jobs) { [EventDispatcherJob, Autonomia::Automacao::AvancarJob] }
    let(:criada) { { 'tipo' => 'conversa.criada' } }
    let(:outra_caixa) { create(:channel_email, account: account, email: 'vendas@empresa.com').inbox }

    def envios = Message.where(account: account, message_type: :outgoing, private: false).where(inbox: [caixa, outra_caixa])

    def recusas(log, motivo) = log.count { |linha| linha.include?('[automacao][cadeia] recusada') && linha.include?("motivo=#{motivo}") }

    def drenar_ao_criar_conversa
      log = []
      registrar = lambda do |original, *args|
        log << args.first.to_s
        original.call(*args)
      end
      allow(Rails.logger).to receive(:info).and_wrap_original(&registrar)
      perform_enqueued_jobs(only: jobs) { create(:conversation, account: account, contact: contato, inbox: whatsapp) }
      log
    end

    it 'a automação não roda de novo na conversa que ela mesma abriu: 1 e-mail, 2 conversas', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [passo], gatilho: criada)

      log = drenar_ao_criar_conversa

      expect(envios.count).to eq(1)
      expect(Conversation.where(account: account).count).to eq(2)
      expect(Autonomia::Automacao::Execucao.where(automacao: definicao).count).to eq(1)
      expect(recusas(log, 'auto_disparo')).to eq(1)
      expect(log.grep(/recusada/).sole).to include("origem=automacao:#{definicao.id}")
    end

    it 'duas automações que se disparam param pela cadeia, sem fim', :aggregate_failures do
      automacao_ligada(account, admin, [passo], gatilho: criada)
      automacao_ligada(account, admin, [email_passo('p1', caixa_id: outra_caixa.id)], gatilho: criada)

      log = drenar_ao_criar_conversa

      # A 1ª conversa dispara as duas (2 e-mails). Em cada conversa nova, quem a abriu é recusada (auto_disparo) e a outra
      # roda (2 e-mails). Nas duas últimas, as duas já estão na cadeia: auto_disparo e laço, e nada mais sai.
      expect(envios.count).to eq(4)
      expect(Conversation.where(account: account).count).to eq(5)
      expect([recusas(log, 'auto_disparo'), recusas(log, 'laco')]).to eq([4, 2])
    end
  end

  # O ensaio (F5) diz por qual caixa e com que assunto sairia, sem abrir conversa; e a resposta automática não entra, pela
  # mesma régua da Escuta.
  describe 'ensaio' do
    def ensaio(gatilho, alvo)
      receita = { 'gatilho' => gatilho, 'passos' => [passo] }
      Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: admin, conversa_id: alvo.display_id).resultado[:conversas].sole
    end

    it 'mostra a caixa, o assunto e o texto, sem abrir conversa', :aggregate_failures do
      no = ensaio({ 'tipo' => 'conversa.criada' }, conversa)[:passos].sole

      expect(no).to include(tipo: 'email', faria: 'email')
      expect(no[:dados]).to eq(texto: 'Oi Carla, seu pedido saiu.', assunto: 'Seu pedido', caixa: caixa.name)
      expect(conversas_de_email).to be_empty
    end

    it 'o assunto em várias linhas aparece numa linha só, como sai no envio' do
      passo['assunto'] = ["Seu\n pedido  ", { '$valor' => 'contato.nome' }]
      expect(ensaio({ 'tipo' => 'conversa.criada' }, conversa)[:passos].sole[:dados][:assunto]).to eq('Seu pedido Carla')
    end

    it 'diz por que não sairia: contato sem e-mail, ou caixa que não existe mais', :aggregate_failures do
      contato.update!(email: nil)
      expect(ensaio({ 'tipo' => 'conversa.criada' }, conversa)[:passos].sole).to include(faria: 'contato_sem_email')

      contato.update!(email: 'cliente@exemplo.com')
      caixa.update_column(:channel_type, 'Channel::Api') # rubocop:disable Rails/SkipsModelValidations
      expect(ensaio({ 'tipo' => 'conversa.criada' }, conversa)[:passos].sole).to include(faria: 'caixa_de_email_indisponivel')
    end

    it 'a conversa de e-mail cuja última mensagem é resposta automática não entraria' do
      de_email = create(:conversation, account: account, contact: contato, inbox: caixa)
      create(:message, conversation: de_email, account: account, inbox: caixa, message_type: :incoming, sender: contato,
                       content: 'Estou de férias.', content_attributes: { email: { auto_reply: true } })

      expect(ensaio({ 'tipo' => 'mensagem.criada' }, de_email)).to include(entraria: false, motivo: 'resposta_automatica')
    end
  end
end
