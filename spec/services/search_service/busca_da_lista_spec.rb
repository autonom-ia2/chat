require 'rails_helper'

# #2211 — a busca dentro da lista de conversas. Cada exemplo cobre um defeito medido em produção (25/10): telefone com
# espaço não achava, nome sem acento não achava, a ordem era a da criação, a mesma pessoa aparecia várias vezes, a
# mensagem antiga e o áudio ficavam de fora. E as regras de acesso de hoje continuam valendo.
RSpec.describe SearchService::BuscaDaLista do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create_crm_agent(account: account, name: 'Ana Lopes').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agente]) }
  let(:outra_caixa) { create_crm_inbox(account: account, name: 'Outra caixa') }

  def servico(texto, quem: agente)
    SearchService.new(current_user: quem, current_account: account, params: { q: texto }, search_type: 'Lista')
  end

  def buscar(texto, quem: agente)
    servico(texto, quem: quem).perform
  end

  def com_funcao(permissoes)
    funcao = create(:custom_role, account: account, permissions: permissoes)
    agente.account_users.find_by!(account: account).update!(custom_role: funcao)
  end

  def contato(nome, telefone: nil)
    account.contacts.create!(name: nome, phone_number: telefone)
  end

  def conversa(pessoa, caixa: inbox, atividade: Time.current, status: :open)
    criada = create_crm_conversation(account: account, inbox: caixa, contact: pessoa)
    criada.update_columns(last_activity_at: atividade, status: Conversation.statuses[status]) # rubocop:disable Rails/SkipsModelValidations
    criada
  end

  def audio(alvo, transcricao)
    com_audio = mensagem(alvo, nil)
    anexo = com_audio.attachments.new(account: account, file_type: :audio, meta: { 'transcribed_text' => transcricao })
    anexo.file.attach(io: StringIO.new('audio'), filename: 'audio.ogg', content_type: 'audio/ogg')
    anexo.save!
    com_audio
  end

  def mensagem(alvo, texto, quando: Time.current)
    alvo.messages.create!(account: account, inbox: alvo.inbox, message_type: :incoming, content: texto, sender: alvo.contact,
                          created_at: quando)
  end

  before { Current.account = account }
  after { Current.account = nil }

  it 'não busca com texto vazio' do
    vazio = { conversations: [], messages: [], contacts: [], telefone_novo: nil, texto_livre_nas_caixas: [], email_novo: nil,
              caixas_para_comecar: [], parcial: [] }
    expect(buscar('  ')).to eq(vazio)
  end

  it 'o NUL na consulta não derruba a busca' do
    pessoa = contato('Bruna Teles')
    conversa(pessoa)
    expect(buscar("bru\u0000na")[:conversations].map(&:contact)).to eq([pessoa])
  end

  it 'usa só os primeiros 100 caracteres' do
    pessoa = contato('Bruna Teles')
    conversa(pessoa)
    expect(buscar("bruna #{'x' * 200}")[:conversations]).to be_empty
    expect(buscar("bruna#{' ' * 200}teles")[:conversations].map(&:contact)).to eq([pessoa])
  end

  it 'a seção que passa do tempo volta vazia e marcada como parcial, sem derrubar as outras' do
    pessoa = contato('Tiago Reis')
    mensagem(conversa(pessoa), 'tiago mandou a foto')
    stub_const('SearchService::BuscaDaLista::TEMPO_MAXIMO', '100ms')
    lento = servico('tiago')
    # Uma consulta de verdade que passa do teto: o Postgres cancela e a seção volta vazia.
    allow(lento).to receive(:mensagens_da_lista).and_return(Message.where('(SELECT true FROM pg_sleep(0.5))'))
    resultado = lento.perform
    expect(resultado[:parcial]).to eq([:messages])
    expect(resultado[:messages]).to eq([])
    expect(resultado[:conversations].map(&:contact)).to eq([pessoa])
    expect(ActiveRecord::Base.connection.select_value('SHOW statement_timeout')).not_to eq('100ms')
  end

  it '"#1234" acha a conversa pelo número' do
    alvo = conversa(contato('Vera Lúcia'))
    conversa(contato('Outra Pessoa'))
    resultado = buscar("##{alvo.display_id}")
    expect(resultado[:conversations]).to eq([alvo])
    expect(resultado[:contacts]).to be_empty
    expect(resultado[:telefone_novo]).to be_nil
  end

  it '"#1234" não acha conversa de caixa que a pessoa não tem' do
    alvo = conversa(contato('Vera Lúcia'), caixa: outra_caixa)
    expect(buscar("##{alvo.display_id}")[:conversations]).to be_empty
  end

  it 'deixa os outros tipos da busca como estavam' do
    expect(SearchService.new(current_user: agente, current_account: account, params: { q: 'x' }, search_type: 'Contact')
                        .perform.keys).to eq([:contacts])
  end

  describe 'telefone' do
    let!(:joao) { contato('João Prado', telefone: '+5511978622068') }

    before { conversa(joao) }

    it 'acha pelos dígitos, com espaço e traço' do
      expect(buscar('11 97862-2068')[:conversations].map(&:contact)).to eq([joao])
    end

    it 'acha com o +55 e parênteses' do
      expect(buscar('+55 (11) 97862-2068')[:conversations].map(&:contact)).to eq([joao])
    end

    it 'com menos de 4 dígitos não trata como telefone' do
      expect(buscar('11 9')[:conversations]).to be_empty
    end

    it 'oferece começar conversa com um telefone que ninguém tem' do
      expect(buscar('11 91234-5678')[:telefone_novo]).to eq('+5511912345678')
    end

    it 'com +, usa o número como foi digitado, sem pôr 55' do
      expect(buscar('+1 (415) 555-0132')[:telefone_novo]).to eq('+14155550132')
    end

    it 'com +, acha o número estrangeiro pelo começo, e não o confunde com um do Brasil' do
      gringo = contato('Peter Hall', telefone: '+14155550132')
      conversa(gringo)
      brasileiro = contato('Bia Nunes', telefone: '+5511914155550')
      conversa(brasileiro)
      expect(buscar('+1 415 555')[:conversations].map(&:contact)).to eq([gringo])
      expect(buscar('415 555')[:conversations].map(&:contact)).to contain_exactly(gringo, brasileiro)
      expect(buscar('+1 (415) 555-0132')[:telefone_novo]).to be_nil
    end

    it 'sem +, número com 55 na frente não ganha outro 55' do
      expect(buscar('55 11 91234-5678')[:telefone_novo]).to eq('+5511912345678')
    end

    it 'o zero de tronco do DDD sai, na busca e no número novo' do
      expect(buscar('011 97862-2068')[:conversations].map(&:contact)).to eq([joao])
      expect(buscar('011 91234-5678')[:telefone_novo]).to eq('+5511912345678')
    end

    it 'não oferece número que o contato recusaria (mais de 15 dígitos ou zero depois do +)' do
      expect(buscar('+1 234 5678 9012 3456')[:telefone_novo]).to be_nil
      expect(buscar('+0 11 91234-5678')[:telefone_novo]).to be_nil
    end

    it 'nono dígito: o número digitado com o 9 acha o gravado sem, e não oferece duplicar' do
      antigo = contato('Wagner Lima', telefone: '+551178622068')
      conversa(antigo)
      resultado = buscar('11 97862-2068')
      expect(resultado[:conversations].map(&:contact)).to include(antigo)
      expect(resultado[:telefone_novo]).to be_nil
    end

    it 'nono dígito: o número digitado sem o 9 acha o gravado com, e não oferece duplicar' do
      resultado = buscar('11 7862-2068')
      expect(resultado[:conversations].map(&:contact)).to eq([joao])
      expect(resultado[:telefone_novo]).to be_nil
    end

    it 'quem não cria contato não recebe a oferta' do
      com_funcao(%w[conversation_manage contact_view])
      expect(buscar('11 91234-5678')[:telefone_novo]).to be_nil
    end

    it 'não oferece telefone que já é de alguém' do
      expect(buscar('11 97862-2068')[:telefone_novo]).to be_nil
    end
  end

  describe 'e-mail' do
    let!(:com_conversa) { account.contacts.create!(name: 'Marta Reis', email: 'marta@example.test') }
    let!(:sem_conversa) { account.contacts.create!(name: 'Caio Prates', email: 'caio@example.test') }

    before { conversa(com_conversa) }

    it 'oferece começar conversa com um e-mail que ninguém da conta tem, como o contato grava' do
      expect(buscar('  Novo.Cliente@Example.TEST ')[:email_novo]).to eq('novo.cliente@example.test')
    end

    it 'não oferece e-mail que já é de alguém, nem com maiúsculas diferentes, e acha a pessoa como hoje' do
      resultado = buscar('MARTA@Example.test')
      expect(resultado[:email_novo]).to be_nil
      expect(resultado[:conversations].map(&:contact)).to eq([com_conversa])
      sem_conversa_achado = buscar('Caio@EXAMPLE.test')
      expect(sem_conversa_achado[:email_novo]).to be_nil
      expect(sem_conversa_achado[:contacts]).to eq([sem_conversa])
    end

    it 'e-mail de contato de outra conta continua novo nesta' do
      create(:account).contacts.create!(name: 'Lia Outra', email: 'lia@example.test')
      expect(buscar('lia@example.test')[:email_novo]).to eq('lia@example.test')
    end

    it 'texto que não é e-mail não traz a oferta' do
      %w[marta example.test @example.test marta@ marta@@example.test].each do |texto|
        expect(buscar(texto)[:email_novo]).to be_nil
      end
      expect(buscar('ana @example.test')[:email_novo]).to be_nil
    end

    it 'quem não cria contato não recebe a oferta' do
      com_funcao(%w[conversation_manage contact_view])
      expect(buscar('novo@example.test')[:email_novo]).to be_nil
    end

    it 'telefone não vira e-mail, e o telefone novo continua igual' do
      resultado = buscar('11 91234-5678')
      expect(resultado[:email_novo]).to be_nil
      expect(resultado[:telefone_novo]).to eq('+5511912345678')
      expect(buscar('novo@example.test')[:telefone_novo]).to be_nil
    end
  end

  # #2257 — no telefone novo, a tela já sabe em quais caixas do WhatsApp Híbrido a primeira mensagem pode ser texto livre.
  describe 'texto livre nas caixas' do
    let(:canal) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    end
    let(:hibrida) { canal.inbox }

    around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { example.run } }

    before do
      Current.user = agente
      create(:inbox_member, user: agente, inbox: hibrida)
    end

    after { Current.user = nil }

    def conexao(caixa = hibrida, **atributos)
      WhatsappHybrid::Connection.create!(
        { account: account, inbox: caixa, session_name: "hibrida-#{caixa.id}", status: 'connected',
          connected_phone: caixa.channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
          status_checked_at: Time.current }.merge(atributos)
      )
    end

    def caixas(texto = '11 91234-5678')
      buscar(texto)[:texto_livre_nas_caixas]
    end

    it 'a caixa híbrida pronta entra' do
      conexao
      expect(caixas).to eq([hibrida.id])
    end

    it 'sem conexão híbrida, não entra' do
      expect(caixas).to eq([])
    end

    it 'com a sessão desconectada, não entra' do
      conexao(status: 'disconnected')
      expect(caixas).to eq([])
    end

    it 'com a origem humana desligada, não entra' do
      conexao(disabled_origins: ['human'])
      expect(caixas).to eq([])
    end

    it 'com o WhatsApp limitando conversas novas (timelock), não entra' do
      timelock = WhatsappHybrid::Timelock.new(conexao)
      timelock.apply!('isActive' => true, 'timeEnforcementEnds' => 6.hours.from_now.to_i)
      expect(caixas).to eq([])
    ensure
      Redis::Alfred.delete(timelock.key) if timelock
    end

    it 'caixa que a pessoa não pode usar não entra' do
      conexao
      alheia = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                         validate_provider_config: false).inbox
      conexao(alheia)
      expect(caixas).to eq([hibrida.id])
    end

    it 'sem telefone novo, vem vazio' do
      conexao
      contato('João Prado', telefone: '+5511912345678')
      expect(caixas).to eq([])
      expect(caixas('joao')).to eq([])
      expect(caixas('  ')).to eq([])
    end
  end

  # A conversa vazia só oferece caixa em que o create da conversa deixa começar (InboxPolicy#show?). O inbox_view de
  # função personalizada lista todas as caixas da conta, mas sem ser membro o create responde 403 depois de gravar o
  # contato.
  describe 'caixas para começar' do
    before do
      inbox
      outra_caixa
    end

    def caixas(texto, quem: agente)
      buscar(texto, quem: quem)[:caixas_para_comecar]
    end

    it 'o membro recebe só as caixas que atende, no telefone e no e-mail novos' do
      expect(caixas('11 91234-5678')).to eq([inbox.id])
      expect(caixas('novo@example.test')).to eq([inbox.id])
    end

    it 'com a função inbox_view, a caixa de que não é membro não vem' do
      com_funcao(%w[conversation_manage contact_manage inbox_view])
      expect(caixas('11 91234-5678')).to eq([inbox.id])
      expect(caixas('novo@example.test')).to eq([inbox.id])
    end

    it 'o administrador recebe todas as caixas da conta, e só as desta conta' do
      create_crm_inbox(account: create(:account), name: 'Caixa de outra conta')
      expect(caixas('11 91234-5678', quem: admin)).to eq([inbox.id, outra_caixa.id])
    end

    it 'sem telefone nem e-mail novos, vem vazio' do
      contato('João Prado', telefone: '+5511912345678')
      expect(caixas('11 91234-5678')).to eq([])
      expect(caixas('joao')).to eq([])
      com_funcao(%w[conversation_manage contact_view])
      expect(caixas('novo@example.test')).to eq([])
    end
  end

  describe 'nome' do
    let!(:joao) { contato('João da Conceição') }

    before { conversa(joao) }

    it 'acha sem acento' do
      expect(buscar('joao conceicao')[:conversations].map(&:contact)).to eq([joao])
    end

    it 'o termo passa pela mesma expressão no banco: não depende da collation (Ø, Ł)' do
      polones = contato('Ølsen Łódź')
      conversa(polones)
      expect(buscar('ØLSEN ŁÓDŹ')[:conversations].map(&:contact)).to eq([polones])
      expect(buscar('Ølsen Lodz')[:conversations]).to be_empty
    end

    it 'acha com acento digitado onde o nome não tem' do
      outra = contato('Paula Lima')
      conversa(outra)
      expect(buscar('Páula')[:conversations].map(&:contact)).to eq([outra])
    end

    it 'acha com as palavras em qualquer ordem' do
      expect(buscar('Conceição João')[:conversations].map(&:contact)).to eq([joao])
    end

    it 'precisa de todas as palavras' do
      expect(buscar('João Silva')[:conversations]).to be_empty
    end
  end

  it 'ordena por nome exato, depois começo do nome, depois contém' do
    contem = contato('Ana Maria Souza')
    comeco = contato('Mariana Dias')
    exato = contato('Maria')
    [contem, comeco, exato].each { |pessoa| conversa(pessoa, atividade: 1.hour.ago) }
    expect(buscar('maria')[:conversations].map(&:contact)).to eq([exato, comeco, contem])
  end

  it 'no mesmo nível, a conversa com atividade mais recente vem antes' do
    velha = contato('Bruno Velho')
    nova = contato('Bruno Novo')
    conversa(velha, atividade: 2.days.ago)
    conversa(nova, atividade: 1.minute.ago)
    expect(buscar('bruno')[:conversations].map(&:contact)).to eq([nova, velha])
  end

  it 'mostra uma conversa por pessoa, a mais recente, mesmo resolvida' do
    rafael = contato('Rafael Souza')
    conversa(rafael, atividade: 10.days.ago)
    recente = conversa(rafael, atividade: 1.day.ago, status: :resolved)
    expect(buscar('rafael')[:conversations]).to eq([recente])
  end

  it 'acha a conversa pelo título do card' do
    pessoa = contato('Helena Sá')
    alvo = conversa(pessoa)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Seguro do Onix', inbox: inbox, owner: admin,
                              contact: pessoa, primary_conversation: alvo)
    expect(buscar('onix')[:conversations]).to eq([alvo])
  end

  it 'acha a conversa pelo assunto do e-mail' do
    alvo = conversa(contato('Clara Monteiro'))
    alvo.update!(additional_attributes: { 'mail_subject' => 'Cotação de seguro viagem' })
    expect(buscar('cotacao viagem')[:conversations]).to eq([alvo])
  end

  describe 'mensagens' do
    let(:alvo) { conversa(contato('Laura Pinto')) }

    it 'acha sem acento e com as palavras fora de ordem' do
      achada = mensagem(alvo, 'Preciso da apólice do carro')
      expect(buscar('carro apolice')[:messages]).to eq([achada])
    end

    it 'ignora palavras com menos de 3 letras; sem nenhuma, a seção fica vazia' do
      achada = mensagem(alvo, 'Preciso da apólice do carro')
      expect(buscar('da apolice')[:messages]).to eq([achada])
      expect(buscar('da do')[:messages]).to be_empty
    end

    it 'olha os últimos 12 meses, não só 3' do
      seis_meses = mensagem(alvo, 'renovação combinada', quando: 6.months.ago)
      mensagem(alvo, 'renovação antiga', quando: 13.months.ago)
      expect(buscar('renovacao')[:messages]).to eq([seis_meses])
    end

    it 'não traz mensagem de conversa já apagada (o destroy_async ainda não chegou nas mensagens)' do
      mensagem(alvo, 'franquia do seguro')
      Conversation.where(id: alvo.id).delete_all
      expect(buscar('franquia')[:messages]).to be_empty
    end

    # A seção de mensagens, com espião no caminho do índice.
    def secao_de_mensagens
      instancias = []
      allow(SearchService::MensagensDaLista).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap do |instancia|
          allow(instancia).to receive(:pelo_indice).and_call_original
          instancias << instancia
        end
      end
      instancias
    end

    it 'termo comum: com LIMITE na janela das recentes, para ali, sem ir ao índice' do
      stub_const('SearchService::MensagensDaLista::LIMITE', 2)
      stub_const('SearchService::MensagensDaLista::JANELA_DE_RECENTES', 3)
      mensagem(alvo, 'boleto antigo', quando: 2.days.ago)
      media = mensagem(alvo, 'boleto do mês', quando: 1.day.ago)
      nova = mensagem(alvo, 'boleto pago', quando: 1.hour.ago)
      instancias = secao_de_mensagens
      expect(buscar('boleto')[:messages]).to eq([nova, media])
      expect(instancias.first).not_to have_received(:pelo_indice)
    end

    it 'termo raro: fora da janela das recentes, acha pelo índice' do
      stub_const('SearchService::MensagensDaLista::JANELA_DE_RECENTES', 2)
      rara = mensagem(alvo, 'vistoria cautelar', quando: 3.months.ago)
      3.times { |vez| mensagem(alvo, "bom dia #{vez}") }
      instancias = secao_de_mensagens
      expect(buscar('cautelar')[:messages]).to eq([rara])
      expect(instancias.first).to have_received(:pelo_indice)
    end

    it 'acha pelo áudio transcrito' do
      audio = mensagem(alvo, nil)
      anexo = audio.attachments.new(account: account, file_type: :audio, meta: { 'transcribed_text' => 'meu carro foi batido' })
      anexo.file.attach(io: StringIO.new('audio'), filename: 'audio.ogg', content_type: 'audio/ogg')
      anexo.save!
      expect(buscar('batido')[:messages]).to eq([audio])
    end
  end

  describe 'pessoas sem conversa' do
    let!(:sem_conversa) { contato('Conceição Ramos', telefone: '+5521988887777') }

    it 'aparecem à parte, e quem tem conversa não aparece aqui' do
      com_conversa = contato('Conceição Alves')
      conversa(com_conversa)
      resultado = buscar('conceicao')
      expect(resultado[:contacts]).to eq([sem_conversa])
      expect(resultado[:conversations].map(&:contact)).to eq([com_conversa])
    end

    it 'o contato de sistema "Integração WhatsApp" do conector não aparece' do
      account.contacts.create!(name: 'Integração WhatsApp', identifier: Waha::IntegracaoDoConector::IDENTIFIER)
      contato('Integração Silva')
      expect(buscar('integracao', quem: admin)[:contacts].map(&:name)).to eq(['Integração Silva'])
    end
  end

  describe 'acesso' do
    it 'a janela das recentes só olha mensagens das conversas que a pessoa vê' do
      stub_const('SearchService::MensagensDaLista::LIMITE', 2)
      stub_const('SearchService::MensagensDaLista::JANELA_DE_RECENTES', 3)
      minha = mensagem(conversa(contato('Rita Melo')), 'sinistro aberto', quando: 2.days.ago)
      alheia = conversa(contato('Sara Dias'), caixa: outra_caixa)
      3.times { |vez| mensagem(alheia, "sinistro alheio #{vez}") }
      expect(buscar('sinistro')[:messages]).to eq([minha])
    end

    it 'o áudio transcrito de conversa alheia não aparece' do
      audio(conversa(contato('Sara Dias'), caixa: outra_caixa), 'franquia reduzida no contrato')
      expect(buscar('franquia')[:messages]).to be_empty
    end

    it 'com a função de só ler (conversation_view), acha a conversa de outro responsável' do
      outro = create(:user, account: account, role: :agent)
      alvo = conversa(contato('Talita Reis'))
      alvo.update!(assignee: outro)
      com_funcao(%w[conversation_view])
      expect(buscar('talita')[:conversations]).to eq([alvo])
    end

    it 'a conversa "Integração WhatsApp" do conector não aparece, como na lista' do
      integracao = account.contacts.create!(name: 'Integração WhatsApp', identifier: Waha::IntegracaoDoConector::IDENTIFIER)
      mensagem(conversa(integracao), 'integracao com erro de tarefa')
      resultado = buscar('integracao')
      expect(resultado[:conversations]).to be_empty
      expect(resultado[:messages]).to be_empty
    end

    it 'com a conversa de e-mail nova, o que está no Spam e na Lixeira não aparece, como na lista' do
      account.enable_features!('conversa_email_nova')
      %w[spam lixeira].each do |pasta|
        alvo = conversa(contato("Ulisses #{pasta}"))
        mensagem(alvo, "promocao imperdivel #{pasta}")
        ConversaCanal::PastaDoEmail.create!(account: account, conversation: alvo, pasta: pasta)
      end
      fora = conversa(contato('Ulisses Entrada'))
      resultado = buscar('ulisses')
      expect(resultado[:conversations]).to eq([fora])
      expect(buscar('promocao')[:messages]).to be_empty
    end

    it 'contato com conversa só numa caixa que a pessoa não vê aparece em Pessoas, sem a conversa' do
      pessoa = contato('Vitor Alves')
      conversa(pessoa, caixa: outra_caixa)
      resultado = buscar('vitor')
      expect(resultado[:conversations]).to be_empty
      expect(resultado[:contacts]).to eq([pessoa])
    end

    it 'não mostra conversa de caixa que a pessoa não tem' do
      conversa(contato('Diego Vaz'), caixa: outra_caixa)
      expect(buscar('diego')[:conversations]).to be_empty
    end

    it 'o administrador vê todas as caixas' do
      alvo = conversa(contato('Diego Vaz'), caixa: outra_caixa)
      expect(buscar('diego', quem: admin)[:conversations]).to eq([alvo])
    end

    it 'não mostra mensagem de caixa que a pessoa não tem' do
      mensagem(conversa(contato('Diego Vaz'), caixa: outra_caixa), 'franquia do seguro')
      expect(buscar('franquia')[:messages]).to be_empty
    end

    it 'respeita o acesso por funil' do
      pipeline, = create_crm_pipeline(account: account, user: admin)
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agente, all_pipelines: false, triage: false)
      access.agent_pipelines.create!(account: account, pipeline: pipeline)
      alvo = conversa(contato('Otávio Lins'))
      mensagem(alvo, 'franquia do seguro')
      resultado = buscar('otavio')
      expect(resultado[:conversations]).to be_empty
      expect(buscar('franquia')[:messages]).to be_empty
    end

    it 'sem poder ver contatos, a seção de pessoas sem conversa fica vazia' do
      contato('Igor Santana')
      expect(buscar('igor')[:contacts].size).to eq(1)
      com_funcao(%w[conversation_manage])
      expect(buscar('igor')[:contacts]).to be_empty
    end

    it 'com a função "conversas em que participa", só as dela e aquelas em que participa' do
      dela = conversa(contato('Nina Prado'))
      dela.update!(assignee: agente)
      participa = conversa(contato('Nina Souza'))
      ConversationParticipant.create!(account: account, conversation: participa, user: agente)
      fora = conversa(contato('Nina Lopes'))
      [dela, participa, fora].each { |alvo| mensagem(alvo, 'vistoria marcada') }
      com_funcao(%w[conversation_participating_manage])
      resultado = buscar('nina')
      expect(resultado[:conversations]).to contain_exactly(dela, participa)
      expect(buscar('vistoria')[:messages].map(&:conversation)).to contain_exactly(dela, participa)
    end
  end
end
