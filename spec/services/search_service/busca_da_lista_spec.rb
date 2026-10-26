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

  def mensagem(alvo, texto, quando: Time.current)
    alvo.messages.create!(account: account, inbox: alvo.inbox, message_type: :incoming, content: texto, sender: alvo.contact,
                          created_at: quando)
  end

  before { Current.account = account }
  after { Current.account = nil }

  it 'não busca com texto vazio' do
    expect(buscar('  ')).to eq(conversations: [], messages: [], contacts: [], telefone_novo: nil, parcial: [])
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

    it 'quem não cria contato não recebe a oferta' do
      com_funcao(%w[conversation_manage contact_view])
      expect(buscar('11 91234-5678')[:telefone_novo]).to be_nil
    end

    it 'não oferece telefone que já é de alguém' do
      expect(buscar('11 97862-2068')[:telefone_novo]).to be_nil
    end
  end

  describe 'nome' do
    let!(:joao) { contato('João da Conceição') }

    before { conversa(joao) }

    it 'acha sem acento' do
      expect(buscar('joao conceicao')[:conversations].map(&:contact)).to eq([joao])
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
  end

  describe 'acesso' do
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
