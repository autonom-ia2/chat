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
# - Passo 3, à risca pela decisão 15 do Rodrigo: os contatos entram pelas regras de linha do Importar contatos
#   (CampaignImports::ContactRow) e a lista fica registrada como importação de contatos (CampaignImport, flow "contacts",
#   origem "automacao"), que aparece em Contatos > Importações com o rótulo "Automação", quem ligou e quantos entraram.
#
# - Passos 6 a 8, o laço dos documentos na 2ª automação, como no exemplo 14 (G46): espera 3 dias o funcionário mandar
#   foto ou PDF; a IA extrai, só dos anexos novos, qual documento é, e cada um é marcado no campo de marcar do card; a IA
#   decide pelo card se está completo e, faltando, volta a esperar (`de_novo`). Em 3 dias sem documento, a IA escreve o
#   pedido só do que falta. Completo: move para "Enviar à operadora" e manda os dados ao sistema da operadora (G13,
#   `webhook`, num receptor WebMock com IP público).
# - Passo 9, uma 3ª automação, toda sexta (G22): o "para cada item" gravou o RH como quem pediu cada card, e o aviso de
#   sexta lista ao RH quem ainda falta, pelo modelo aprovado.
RSpec.describe 'Fechamento #2414 · exemplo 8: funcionário novo no plano da empresa', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  # A jornada de campanhas e o import ligados: Contatos > Importações (decisão 15) abre como na conta real.
  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CAMPAIGN_JOURNEY_ENABLED: 'true', CAMPAIGN_IMPORT_ENABLED: 'true') { exemplo.run }
  end

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
  let(:enviar_a_operadora) { create_crm_stage(account: account, pipeline: funil, name: 'Enviar à operadora', position: 2) }
  let(:pedidos_a_operadora) { [] }
  let(:roteiro) { { 'automacao_decidir' => { 'caminho' => 'inclusao', 'motivo' => 'lista de funcionários novos' } } }

  # Os 4 funcionários da lista. O Bruno já é contato, sem empresa.
  def funcionarios
    [{ 'nome' => 'Ana Prado', 'data_nascimento' => '12/03/1990', 'telefone' => '11 98888-0001' },
     { 'nome' => 'Bruno Reis', 'data_nascimento' => '05/07/1985', 'telefone' => '(11) 98888-0002' },
     { 'nome' => 'Carla Dias', 'data_nascimento' => '23/11/1998', 'telefone' => '11988880003' },
     { 'nome' => 'Diego Melo', 'data_nascimento' => '30/01/2001', 'telefone' => '+55 11 98888-0004' }]
  end

  def operadora = 'https://inclusoes.operadora.test/vidas'
  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
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

  # Passo 5: em cada card novo do quadro, a lista de documentos pelo modelo aprovado. Passos 6 a 8: o laço dos documentos.
  def receita_de_cada_card
    nome = { '$valor' => 'contato.nome' }
    { gatilho: { tipo: 'card.criado', funil_id: funil.id, conversa_nova: { caixa_id: canal.inbox.id } }, passos: [
      { id: 'documentos', tipo: 'mensagem',
        texto: ['Olá, ', nome, '! Para a sua inclusão no plano, mande: RG, CPF e comprovante de residência.'],
        modelo: { nome: 'documentos_da_inclusao', idioma: 'pt_BR', variaveis: [[nome]] } },
      espera_o_documento, extrai_o_documento, *marca_no_card, completo?
    ] }
  end

  def tipos_de_documento = { 'rg' => 'o RG', 'cpf' => 'o CPF', 'comprovante' => 'o comprovante de residência' }

  # Passo 7: 3 dias sem documento novo, a IA escreve o pedido só do que falta e espera mais 3; sem nada, a automação encerra.
  # Depois de 3 dias a janela de 24 h fechou: o pedido que a IA escreveu sai dentro do modelo aprovado.
  def espera_o_documento(id = 'espera_doc', se_vencer = nil)
    nome = { '$valor' => 'contato.nome' }
    se_vencer ||= [{ id: 'pede_o_resto', tipo: 'escrever', le: %w[card], destino: 'guardar',
                     instrucao: 'Peça ao funcionário só os documentos da inclusão que ainda não estão marcados no card.' },
                   { id: 'manda_o_pedido', tipo: 'mensagem', texto: ['Olá, ', nome, '. ', { '$valor' => 'ia.pede_o_resto' }],
                     modelo: { nome: 'documentos_faltando', idioma: 'pt_BR', variaveis: [[nome], [{ '$valor' => 'ia.pede_o_resto' }]] } },
                   espera_o_documento('espera_doc2', [{ id: 'sem_documento', tipo: 'parar' }])]
    { id: id, tipo: 'esperar_ate', prazo: { valor: 3, unidade: 'dias' }, se_vencer: se_vencer,
      condicao: { campo: { '$valor' => 'conversa.cliente_mandou_documento' }, op: 'igual', valor: true } }
  end

  # Passo 6: a IA extrai, só dos anexos que ainda não leu, quais documentos chegaram.
  def extrai_o_documento
    campos = tipos_de_documento.map do |chave, nome_do_documento|
      { chave: chave, descricao: "true se chegou #{nome_do_documento} e dá para ler; null se não chegou", destino: "conversa.atributos.#{chave}" }
    end
    { id: 'extrai', tipo: 'extrair', le: %w[anexos_novos], trocar: true, campos: campos }
  end

  # Passo 6, "marca no card": um passo por documento; o que não chegou nesta leitura pula sem desmarcar.
  def marca_no_card
    tipos_de_documento.map do |chave, nome_do_documento|
      { id: "marca_#{chave}", tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: "Marcar #{nome_do_documento} no card",
        caminho: { id: { '$valor' => 'card.id' } },
        corpo: { card: { custom_attributes: { chave => { '$valor' => "conversa.atributos.#{chave}" } } } } }
    end
  end

  # Passo 8: completo, move para "Enviar à operadora" e manda os dados à operadora. Faltando, volta a esperar.
  def completo?
    completo = [{ id: 'para_operadora', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Levar para Enviar à operadora',
                  caminho: { id: { '$valor' => 'card.id' } }, corpo: { stage_id: enviar_a_operadora.id } },
                { id: 'operadora', tipo: 'webhook', descricao: 'Mandar à operadora', url: operadora,
                  corpo: { nome: { '$valor' => 'contato.nome' }, telefone: { '$valor' => 'contato.telefone' },
                           nascimento: { '$valor' => 'contato.atributos.data_nascimento' } } }]
    { id: 'completo', tipo: 'decidir', le: %w[card], pergunta: 'O card da inclusão já tem RG, CPF e comprovante marcados?',
      caminhos: [{ nome: 'Completo', chave: 'completo', descricao: 'RG, CPF e comprovante marcados no card', passos: completo },
                 { nome: 'Falta algo', chave: 'falta', descricao: 'algum documento ainda não está marcado', passos: [] }],
      nenhum: [], de_novo: { caminhos: %w[falta nenhum], desde: 'espera_doc' } }
  end

  # Passo 9: toda sexta, o RH de cada empresa com inclusão aberta sabe quem ainda não mandou documento.
  def receita_de_sexta
    faltam = { '$valor' => 'contato.solicitados_faltando' }
    { gatilho: { tipo: 'contato.recorrente', frequencia: 'semanal', dia_da_semana: 5, hora: 9,
                 selecao: { solicitante_de: { funil_id: funil.id, faltando: tipos_de_documento.keys } },
                 conversa_nova: { caixa_id: canal.inbox.id } },
      passos: [{ id: 'aviso_ao_rh', tipo: 'mensagem', texto: ['Oi! Ainda faltam documentos de: ', faltam],
                 modelo: { nome: 'documentos_pendentes', idioma: 'pt_BR', variaveis: [[faltam]] } }] }
  end

  def ligar_tudo
    { 'Lista do RH' => receita_do_rh, 'Documentos de cada vida' => receita_de_cada_card,
      'Documentos pendentes ao RH' => receita_de_sexta }.each do |nome, receita|
      ligar_automacao(luciana, account, montar_automacao(luciana, account, nome: nome, receita: receita))
    end
  end

  def drenados
    [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::TempoDaAutomacaoJob,
     Autonomia::Automacao::RecorrenteLoteJob]
  end

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
    canal.update!(message_templates: [documentos, pendentes_ao_rh, documentos_faltando])
    preparar_os_documentos
    create(:contact, account: account, name: 'Bruno', phone_number: '+5511988880002', email: nil)
    conversa_do_rh
    receptor_whatsapp_cloud
    roteiro['automacao_para_cada'] = { 'itens' => funcionarios }
    ia_responde(account, roteiro)
    ligar_tudo
    clear_enqueued_jobs
  end

  after { Current.reset }

  def documentos_faltando
    { 'name' => 'documentos_faltando', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá, {{1}}. {{2}}' }] }
  end

  def pendentes_ao_rh
    { 'name' => 'documentos_pendentes', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi! Ainda faltam documentos de: {{1}}' }] }
  end

  # Os campos de marcar do card e os da conversa, onde o extrair grava; a etapa "Enviar à operadora"; o sistema da operadora.
  def preparar_os_documentos
    account.update!(reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    %w[card_attribute conversation_attribute].product(tipos_de_documento.keys).each do |modelo, chave|
      create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave.upcase,
                                           attribute_model: modelo, attribute_display_type: 'checkbox')
    end
    # A data de nascimento que vai à operadora: o atributo da coluna do Importar contatos, criado antes para o salvar conferir.
    create(:custom_attribute_definition, account: account, attribute_key: 'data_nascimento', attribute_display_name: 'data_nascimento',
                                         attribute_model: 'contact_attribute', attribute_display_type: 'text')
    enviar_a_operadora
    receptor_da_operadora
  end

  # O sistema da operadora: um nome que resolve para um IP público, e cada pedido guardado.
  def receptor_da_operadora
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('inclusoes.operadora.test').and_return(['93.184.216.34'])
    stub_request(:post, operadora).to_return do |pedido|
      pedidos_a_operadora << JSON.parse(pedido.body)
      { status: 201, body: { protocolo: 'OP-1' }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def lista_do_rh
    rh_manda('Oi Luciana! Seguem os novos para incluir no plano: Ana Prado 12/03/1990 11 98888-0001; Bruno Reis 05/07/1985 ' \
             '(11) 98888-0002; Carla Dias 23/11/1998 11988880003; Diego Melo 30/01/2001 +55 11 98888-0004')
  end

  def card_da(nome) = funil.cards.joins(:contact).find_by!(contacts: { name: nome })
  def conversa_da(nome) = Conversation.where(inbox: canal.inbox, contact: card_da(nome).contact).order(:id).last

  # O funcionário manda a foto ou o PDF de um documento, como o canal grava a mídia.
  def manda_documento(nome, arquivo)
    conversa = conversa_da(nome)
    mensagem = conversa.messages.new(account: account, inbox: canal.inbox, message_type: :incoming, sender: conversa.contact, content: nil)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: :file)
    anexo.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: arquivo, content_type: 'application/pdf', identify: false)
    mensagem.save!
    drenar
  end

  def varre(instante)
    travel_to(instante) do
      Autonomia::Automacao::TempoJob.perform_now
      Autonomia::Automacao::VarreduraJob.perform_now
      drenar
    end
  end

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
    # Passo 3, "pela mesma importação da tela Contatos": a lista está em Contatos > Importações, como importação da automação.
    get "/api/v1/accounts/#{account.id}/contact_imports", headers: { 'api_access_token' => luciana.access_token.token }
    importacao = response.parsed_body['payload'].sole
    expect(importacao).to include('origin' => 'automation', 'name' => 'Lista do RH', 'status' => 'completed', 'total_rows' => 4,
                                  'imported_contacts_count' => 4, 'failed_count' => 0)
    expect(importacao['created_by']['id']).to eq(luciana.id)
    linhas = CampaignImport.find(importacao['id']).campaign_import_rows.order(:row_number)
    expect(linhas.map(&:contact_id)).to eq(contatos.map(&:id))
    expect(linhas.map(&:was_existing_contact)).to eq([false, true, false, false])
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
    expect(historico('Documentos de cada vida')).to eq([['documentos', 'ok', nil], ['espera_doc', 'ok', nil]] * 4)
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

  it 'passo 6: cada documento que chega vai à IA, e o card marca o que chegou', :aggregate_failures do
    lista_do_rh
    roteiro['automacao_extrair'] = { 'rg' => true, 'cpf' => nil, 'comprovante' => nil }
    roteiro['automacao_decidir'] = { 'caminho' => 'falta', 'motivo' => 'faltam CPF e comprovante' }

    manda_documento('Ana Prado', 'rg-ana.pdf')

    expect(pedidos_a_ia('automacao_extrair').sole['input'].first['content'].pluck('filename')).to include('rg-ana.pdf')
    expect(card_da('Ana Prado').custom_attributes).to eq('rg' => true)
    expect(card_da('Ana Prado').stage_id).to eq(etapa.id)
    expect(pedidos_a_operadora).to be_empty
  end

  it 'passo 7: 3 dias sem documento novo, a IA escreve o pedido só do que falta, lendo o card', :aggregate_failures do
    lista_do_rh
    roteiro['automacao_extrair'] = { 'rg' => true, 'cpf' => nil, 'comprovante' => nil }
    roteiro['automacao_decidir'] = { 'caminho' => 'falta', 'motivo' => 'faltam CPF e comprovante' }
    roteiro['automacao_escrever'] = { 'texto' => 'Ana, recebi o RG. Falta mandar o CPF e o comprovante de residência.' }
    manda_documento('Ana Prado', 'rg-ana.pdf')

    varre(3.days.from_now + 5.minutes)

    # A IA leu o card de cada funcionário; o da Ana, com o RG marcado.
    expect(pedidos_a_ia('automacao_escrever').map(&:to_json)).to include(a_string_including('\\"rg\\":true'))
    pedido = para(numeros.first).select { |corpo| corpo.dig('template', 'name') == 'documentos_faltando' }.sole
    expect(pedido.dig('template', 'components', 0, 'parameters').pluck('text'))
      .to eq(['Ana Prado', 'Ana, recebi o RG. Falta mandar o CPF e o comprovante de residência.'])
  end

  it 'passo 8: card completo vai para "Enviar à operadora" e os dados seguem ao sistema da operadora', :aggregate_failures do
    lista_do_rh
    roteiro['automacao_extrair'] = { 'rg' => true, 'cpf' => true, 'comprovante' => true }
    roteiro['automacao_decidir'] = { 'caminho' => 'completo', 'motivo' => 'os três marcados' }

    manda_documento('Ana Prado', 'documentos-ana.pdf')

    expect(card_da('Ana Prado')).to have_attributes(stage_id: enviar_a_operadora.id,
                                                    custom_attributes: { 'rg' => true, 'cpf' => true, 'comprovante' => true })
    expect(pedidos_a_operadora.sole).to eq('nome' => 'Ana Prado', 'telefone' => '+5511988880001', 'nascimento' => '12/03/1990')
  end

  it 'passo 9: na sexta, o RH recebe quem ainda falta mandar documento', :aggregate_failures do
    lista_do_rh
    roteiro['automacao_extrair'] = { 'rg' => true, 'cpf' => true, 'comprovante' => true }
    roteiro['automacao_decidir'] = { 'caminho' => 'completo', 'motivo' => 'os três marcados' }
    # Na sexta vencem também os 3 dias dos outros: o pedido do que falta sai para eles.
    roteiro['automacao_escrever'] = { 'texto' => 'Ainda faltam o RG, o CPF e o comprovante.' }
    manda_documento('Ana Prado', 'documentos-ana.pdf')

    expect(funil.cards.pluck(:solicitante_contact_id).uniq).to eq([rh.id])
    # A sexta é a de pelo menos um dia depois de hoje: a conversa do RH já passou das 24 h e o aviso sai pelo modelo.
    # Contar a partir de hoje dava, numa quinta depois das 9h05, a sexta seguinte com a janela ainda aberta (texto livre).
    sexta = 1.day.from_now.in_time_zone(fuso).next_occurring(:friday).change(hour: 9, min: 5)
    varre(sexta)

    aviso = para(rh.phone_number).find { |corpo| corpo.dig('template', 'name') == 'documentos_pendentes' }
    texto = aviso.dig('template', 'components', 0, 'parameters', 0, 'text')
    expect(texto).to include('Bruno', 'Carla Dias', 'Diego Melo')
    expect(texto).not_to include('Ana Prado')
  end
end
