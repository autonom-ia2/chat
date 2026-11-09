require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 8 dos termos de aceite: "Funcionário novo no plano da empresa".
#
# > "O RH da empresa cliente me manda os funcionários novos pelo WhatsApp. Quero que cada um vire um pedido e que o
# > sistema peça os documentos de cada um." — Luciana, corretora de planos empresariais
#
# Montado como a Luciana montaria, pela API da tela, nas duas automações encadeadas do termo. A 1ª começa com a mensagem
# do RH: a IA decide se é uma lista de inclusão, o "para cada item" (G24, #2771) tira nome, data de nascimento e
# telefone de cada funcionário, importa os contatos pela linha do Importar contatos, ligados à empresa do RH, e abre um
# card por funcionário no quadro "Inclusão de vidas"; por fim, o RH recebe a resposta com a contagem. A 2ª começa em cada
# card criado e manda ao funcionário a lista de documentos pelo modelo aprovado, abrindo a conversa pela caixa do
# WhatsApp oficial (conversa_nova).
#
# Só a borda é dublê, na camada HTTP: a Graph do WhatsApp oficial (as mensagens) e a OpenAI (decidir e a lista). A
# mensagem do RH entra pelo webhook real da Cloud; a foto da lista, como o canal grava a mídia.
#
# Adaptações ao termo, todas pela regra da plataforma:
# - O modelo aprovado da lista de documentos tem na Meta o nome `documentos_da_inclusao`.
# - O "quadro" é o funil "Inclusão de vidas"; o card nasce na primeira etapa dele.
# - A data de nascimento vai para o contato como a coluna "data_nascimento" do Importar contatos (atributo do contato).
# - Passo 3: os contatos entram pelas regras de linha do Importar contatos (CampaignImports::ContactRow), sem registro de
#   importação (CampaignImport). A lista não aparece em Contatos > Importações. Se "pela mesma importação da tela
#   Contatos" exige esse registro, o passo 3 ainda não cumpre o termo à risca (decisão pendente do Rodrigo).
#
# Passos 6 a 9 em aberto (pendentes_spec): a 2ª automação não volta a esperar a cada documento (G31: a receita não tem
# laço), não há gatilho de card completo (G27) e o aviso de sexta ao RH, que não está na conversa do card, é a G22.
RSpec.describe 'Fechamento #2414 · exemplo 8: funcionário novo no plano da empresa', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:luciana) { create(:user, account: account, role: :administrator, name: 'Luciana Corretora') }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: luciana, name: 'Inclusão de vidas') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }
  let(:empresa) { account.companies.create!(name: 'Alfa Metalúrgica') }
  let(:rh) { create(:contact, account: account, name: 'Rita do RH', phone_number: '+5511900000008', company: empresa) }
  let(:conversa_do_rh) do
    contact_inbox = create(:contact_inbox, inbox: canal.inbox, contact: rh, source_id: '5511900000008')
    create(:conversation, account: account, inbox: canal.inbox, contact: rh, contact_inbox: contact_inbox, status: :open)
  end
  let(:roteiro) { { 'automacao_decidir' => { 'caminho' => 'inclusao', 'motivo' => 'lista de funcionários novos' } } }

  # Os 4 funcionários da lista. O Bruno já é contato, sem empresa.
  def funcionarios
    [{ 'nome' => 'Ana Prado', 'data_nascimento' => '12/03/1990', 'telefone' => '11 98888-0001' },
     { 'nome' => 'Bruno Reis', 'data_nascimento' => '05/07/1985', 'telefone' => '(11) 98888-0002' },
     { 'nome' => 'Carla Dias', 'data_nascimento' => '23/11/1998', 'telefone' => '11988880003' },
     { 'nome' => 'Diego Melo', 'data_nascimento' => '30/01/2001', 'telefone' => '+55 11 98888-0004' }]
  end

  def numeros = %w[+5511988880001 +5511988880002 +5511988880003 +5511988880004]

  def documentos
    { 'name' => 'documentos_da_inclusao', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá, {{1}}! Para a sua inclusão no plano, mande: RG, CPF e comprovante de residência.' }] }
  end

  # Passos 1 a 4: a mensagem do RH.
  def receita_do_rh
    filtros = [{ campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' }]
    { gatilho: { tipo: 'mensagem.criada', filtros: filtros }, passos: [
      { id: 'lista_de_inclusao', tipo: 'decidir', le: %w[mensagens_recentes anexos], pergunta: 'A mensagem do RH é uma lista de inclusão no plano?',
        caminhos: [
          { nome: 'Lista de inclusão', chave: 'inclusao', descricao: 'manda funcionários novos para entrar no plano', passos: inclusao },
          { nome: 'Outro assunto', chave: 'outro', descricao: 'qualquer outra mensagem', passos: [{ id: 'para', tipo: 'parar' }] }
        ], nenhum: [] }
    ] }
  end

  def inclusao
    [{ id: 'funcionarios', tipo: 'para_cada', le: %w[mensagens_recentes anexos], descricao: 'Cada funcionário novo da lista do RH',
       campos: [{ chave: 'nome', descricao: 'Nome completo do funcionário' },
                { chave: 'data_nascimento', descricao: 'Data de nascimento, como está escrita' },
                { chave: 'telefone', descricao: 'Telefone ou WhatsApp do funcionário' }],
       etapa_id: etapa.id, maximo: 50 },
     { id: 'resposta_ao_rh', tipo: 'mensagem',
       texto: ['Recebi os ', { '$valor' => 'ia.funcionarios.quantos' }, ' nomes. Já vou pedir os documentos a cada um'] }]
  end

  # Passo 5: em cada card novo do quadro, a lista de documentos pelo modelo aprovado.
  def receita_de_cada_card
    nome = { '$valor' => 'contato.nome' }
    { gatilho: { tipo: 'card.criado', funil_id: funil.id, conversa_nova: { caixa_id: canal.inbox.id } }, passos: [
      { id: 'documentos', tipo: 'mensagem',
        texto: ['Olá, ', nome, '! Para a sua inclusão no plano, mande: RG, CPF e comprovante de residência.'],
        modelo: { nome: 'documentos_da_inclusao', idioma: 'pt_BR', variaveis: [[nome]] } }
    ] }
  end

  def ligar_tudo
    { 'Lista do RH' => receita_do_rh, 'Documentos de cada vida' => receita_de_cada_card }.each do |nome, receita|
      ligar_automacao(luciana, account, montar_automacao(luciana, account, nome: nome, receita: receita))
    end
  end

  def drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob]

  # Um job por vez, como no Sidekiq.
  def drenar
    200.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou em 200 jobs'
  end

  def rh_manda(texto)
    cliente_escreve_pela_cloud(canal, remetente: '5511900000008', nome: 'Rita do RH', texto: texto)
    drenar
  end

  # A foto da lista chega como o canal grava a mídia: a mensagem sem texto, com a imagem anexada.
  def rh_manda_a_foto
    mensagem = conversa_do_rh.messages.new(account: account, inbox: canal.inbox, message_type: :incoming, sender: rh, content: nil)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: :image)
    anexo.file.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'lista-de-inclusao.png', content_type: 'image/png')
    mensagem.save!
    drenar
  end

  def saidas = chamadas_para('graph.facebook.com').map(&:corpo)
  def para(numero) = saidas.select { |corpo| corpo['to'].to_s.delete('+') == numero.delete('+') }
  def pedidos_a_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }
  def historico(nome) = Autonomia::Automacao::Registro.where(automacao_id: automacao_id(nome)).order(:id).pluck(:passo, :resultado, :motivo)
  def automacao_id(nome) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: nome).id
  def execucoes(nome) = Autonomia::Automacao::Execucao.where(automacao_id: automacao_id(nome))

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'companies')
    create(:inbox_member, user: luciana, inbox: canal.inbox)
    canal.update!(message_templates: [documentos])
    create(:contact, account: account, name: 'Bruno', phone_number: '+5511988880002', email: nil)
    conversa_do_rh
    receptor_whatsapp_cloud
    roteiro['automacao_para_cada'] = { 'itens' => funcionarios }
    ia_responde(account, roteiro)
    ligar_tudo
    clear_enqueued_jobs
  end

  after { Current.reset }

  it 'passos 1 a 5: a lista do RH vira 4 contatos da empresa e 4 cards, o RH recebe a contagem e cada um, o pedido dos documentos',
     :aggregate_failures do
    rh_manda('Oi Luciana! Seguem os novos para incluir no plano: Ana Prado 12/03/1990 11 98888-0001; Bruno Reis 05/07/1985 ' \
             '(11) 98888-0002; Carla Dias 23/11/1998 11988880003; Diego Melo 30/01/2001 +55 11 98888-0004')

    # Passo 1: a IA decidiu que é lista de inclusão.
    expect(pedidos_a_ia('automacao_decidir').size).to eq(1)
    # Passo 2: a IA tirou nome, data de nascimento e telefone de cada funcionário.
    lista = pedidos_a_ia('automacao_para_cada').sole
    expect(lista.dig('text', 'format', 'schema', 'properties', 'itens', 'items', 'required')).to eq(%w[nome data_nascimento telefone])
    # Passo 3: os contatos pela linha do Importar contatos, ligados à empresa do RH, e um card de cada um no quadro.
    contatos = numeros.map { |numero| account.contacts.find_by!(phone_number: numero) }
    expect(contatos.map(&:name)).to eq(['Ana Prado', 'Bruno', 'Carla Dias', 'Diego Melo'])
    expect(contatos.map(&:company_id)).to all(eq(empresa.id))
    expect(contatos.map { |contato| contato.custom_attributes['data_nascimento'] }).to eq(%w[12/03/1990 05/07/1985 23/11/1998 30/01/2001])
    expect(account.custom_attribute_definitions.contact_attribute.find_by!(attribute_key: 'data_nascimento').attribute_display_type).to eq('text')
    cards = funil.cards.order(:id)
    expect(cards.map(&:contact)).to eq(contatos)
    expect(cards.map(&:stage_id).uniq).to eq([etapa.id])
    # Passo 4: o RH recebe a resposta com a contagem, na conversa dele.
    expect(para(rh.phone_number).map { |corpo| corpo.dig('text', 'body') }).to eq(['Recebi os 4 nomes. Já vou pedir os documentos a cada um'])
    expect(historico('Lista do RH')).to eq([['lista_de_inclusao', 'ok', nil], ['funcionarios', 'ok', nil], ['resposta_ao_rh', 'ok', nil]])
    # Passo 5: a 2ª automação rodou em cada card e cada funcionário recebeu o modelo aprovado, com o próprio nome.
    expect(execucoes('Documentos de cada vida').map(&:alvo)).to match_array(cards)
    numeros.zip(contatos).each do |numero, contato|
      modelo = para(numero).sole['template']
      expect(modelo['name']).to eq('documentos_da_inclusao')
      expect(modelo.dig('components', 0, 'parameters', 0, 'text')).to eq(contato.name)
    end
    expect(historico('Documentos de cada vida')).to eq([['documentos', 'ok', nil]] * 4)
  end

  it 'passo 2: a lista que chega em foto vai à IA, e os cards nascem dela', :aggregate_failures do
    rh_manda_a_foto

    imagem = pedidos_a_ia('automacao_para_cada').sole['input'].first['content'].find { |parte| parte['type'] == 'input_image' }
    expect(imagem).to be_present
    expect(funil.cards.count).to eq(4)
  end

  it 'passo 1: mensagem do RH que não é lista de inclusão para, sem contato, card nem resposta', :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'outro', 'motivo' => 'pergunta sobre a fatura' }

    rh_manda('Luciana, a fatura deste mês já saiu?')

    expect(pedidos_a_ia('automacao_para_cada')).to be_empty
    expect(funil.cards).to be_empty
    expect(account.contacts.where(phone_number: numeros)).to contain_exactly(account.contacts.find_by!(name: 'Bruno'))
    expect(saidas).to be_empty
    expect(execucoes('Documentos de cada vida')).to be_empty
  end
end
