require 'rails_helper'

# Fechamento do épico #2414 (#2570), exemplo 14 dos termos de aceite, passos 1 a 8, à risca e numa automação só (G46, G13):
#
# > "Quando o cliente fecha, eu perco dias esperando documento. Quero que o sistema peça, confira e me avise só quando
# > estiver tudo certo." — Dona Cida, dona da corretora
#
# Começa quando o card entra em "Documentação". 1. Manda pelo modelo a lista do ramo. 2. A cada foto ou PDF, a IA extrai
# qual documento é e se dá para ler (grava no card, um campo por documento). 3. Não deu para ler: pede de novo. 4. Faltando algo: escreve só o
# que falta. 5. 2 dias sem documento novo: lembra uma vez, pelo modelo; 4 dias: cria retorno para o corretor. 6. Tudo
# recebido: etiqueta "docs ok" e move para "Emissão". 7. Manda os dados ao sistema da seguradora e grava no card o número da
# proposta que ele devolve. 8. A seguradora recusou: avisa a Dona Cida com o motivo que veio na resposta.
#
# O laço: o "esperar até o cliente mandar foto ou PDF" (2 dias) e o "decidir" que volta a ele (`de_novo.desde`) nos
# caminhos "ilegível", "falta algo" e "nenhum". O lembrete é uma vez por pausa, e o prazo recomeça a cada documento
# (decisão do Rodrigo, 09/11); depois do retorno, a automação encerra. O lembrete, o retorno e o "tudo recebido" só agem
# com o card ainda em "Documentação" (um "se" na receita, decisão do Rodrigo). O extrair lê só os anexos que ainda não
# leu (`anexos_novos`) e grava cada documento no seu campo do card; o "decidir" lê o card. A etiqueta é "docs-ok": o nome de
# etiqueta não aceita espaço, como no exemplo 1. Montada e ligada pela API da tela; o card entra pelo Creator; as esperas
# andam pela varredura do motor; a IA é o dublê no endereço da OpenAI (nenhuma chamada paga); o WhatsApp oficial para no
# receptor. A seguradora é o passo "webhook" (G13): um receptor WebMock num nome que resolve para um IP público; a
# resposta grava no card o número da proposta, ou o motivo da recusa, que vai no aviso à Dona Cida (`se_recusar`).
RSpec.describe 'Fechamento #2414 · exemplo 14: o laço dos documentos', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:cida) { create(:user, account: account, role: :administrator, name: 'Dona Cida') }
  let(:corretor) { create(:user, account: account, role: :agent, name: 'Rafael Corretor') }
  let(:marcos) { create(:contact, account: account, name: 'Marcos', phone_number: '+5511900002714') }
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: marcos, source_id: '5511900002714')
    create(:conversation, account: account, inbox: inbox, contact: marcos, contact_inbox: contact_inbox, status: :open)
  end
  let(:funil) { create_crm_pipeline(account: account, user: cida, name: 'Seguros').first }
  let(:documentacao) { create_crm_stage(account: account, pipeline: funil, name: 'Documentação', position: 1) }
  let(:emissao) { create_crm_stage(account: account, pipeline: funil, name: 'Emissão', position: 2) }
  let(:perdido) { create_crm_stage(account: account, pipeline: funil, name: 'Perdido', position: 3) }
  # O que o dublê da IA responde, por passo, uma resposta por ida, na ordem (a última se repete). Um Proc roda durante a
  # ida (o que chega enquanto a IA lê) e devolve a resposta.
  let(:respostas) { { 'automacao_extrair' => [], 'automacao_decidir' => [], 'automacao_escrever' => [] } }
  let(:card) { entra_em_documentacao }
  let(:pedidos_a_seguradora) { [] }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def inicio = fuso.parse('2026-11-09 09:00')
  def seguradora = 'https://propostas.seguradora.test/auto'
  def card_id = { '$valor' => 'card.id' }

  def modelo(nome, *variaveis) = { nome: nome, idioma: 'pt_BR', variaveis: [[{ '$valor' => 'contato.nome' }], *variaveis] }

  # A lista do ramo (seguro auto) que o passo 1 manda, na variável do modelo aprovado.
  def lista_do_auto = 'CNH, documento do carro e comprovante de endereço'

  def chegou_documento(id, se_vencer)
    { id: id, tipo: 'esperar_ate', prazo: { valor: 2, unidade: 'dias' }, se_vencer: se_vencer,
      condicao: { campo: { '$valor' => 'conversa.cliente_mandou_documento' }, op: 'igual', valor: true } }
  end

  # "Só se o card ainda estiver em Documentação" (decisão do Rodrigo, 09/11): antes do lembrete e antes do retorno. Fora
  # da etapa, a automação para ali. É configuração da receita; o motor não muda.
  def so_se_em_documentacao(id, passos)
    { id: id, tipo: 'se', condicao: { campo: { '$valor' => 'card.etapa_id' }, op: 'igual', valor: documentacao.id },
      entao: passos, senao: [{ id: "#{id}_parar", tipo: 'parar' }] }
  end

  def escrever(id, instrucao) = { id: id, tipo: 'escrever', le: %w[card mensagens_recentes], instrucao: instrucao, destino: 'mensagem' }

  def caminho(nome, chave, descricao, passos)
    { nome: nome, chave: chave, descricao: descricao, passos: passos }
  end

  # Os três documentos da lista. Cada um tem o campo dele no card: "recebido", ou o que não deu para ler nele.
  def documentos = { 'cnh' => 'a CNH', 'doc_carro' => 'o documento do carro (CRLV)', 'comprovante' => 'o comprovante de endereço' }

  # A resposta do extrair traz os três campos (o esquema pede todos); o documento que não chegou vem vazio.
  def extraiu(achados) = documentos.keys.index_with { '' }.merge(achados)

  def receita
    { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: documentacao.id }, passos: [
      { id: 'lista', tipo: 'mensagem', texto: ["Para emitir o seguro auto: #{lista_do_auto}."],
        modelo: modelo('lista_documentos', [lista_do_auto]) },
      espera_lembra_e_liga, extrai, *no_card, decide
    ] }
  end

  # 2 dias sem documento: o lembrete; mais 2: o retorno à equipe, e a automação encerra. Os dois só com o card em Documentação.
  def espera_lembra_e_liga
    retorno = { id: 'ligar', tipo: 'retorno', titulo: ['Ligar para ', { '$valor' => 'contato.nome' }, ': documentos'],
                daqui: { valor: 1, unidade: 'minutos' } }
    lembrete = { id: 'lembrete', tipo: 'mensagem', texto: ['Lembrete dos documentos'], modelo: modelo('lembrete_documentos') }
    segunda = chegou_documento('espera_doc2', [so_se_em_documentacao('ainda_la2', [retorno, { id: 'fim', tipo: 'parar' }])])
    chegou_documento('espera_doc', [so_se_em_documentacao('ainda_la', [lembrete, segunda])])
  end

  # Lê só os anexos que ainda não leu (`anexos_novos`): nenhum vai duas vezes à IA, e com 6 ou mais nada fica de fora.
  def extrai
    campos = documentos.map do |chave, nome|
      { chave: chave, descricao: "se chegou #{nome}: \"recebido\" se dá para ler, ou o que não deu para ler; vazio se não chegou",
        destino: "conversa.atributos.#{chave}" }
    end
    { id: 'extrai', tipo: 'extrair', le: %w[anexos_novos], trocar: true, campos: campos }
  end

  # Um passo por documento: o que não chegou nesta leitura fica vazio, e o passo dele pula sem apagar o que o card já tem.
  def no_card
    documentos.map do |chave, nome|
      { id: "no_card_#{chave}", tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: "Gravar no card #{nome}",
        caminho: { id: card_id }, corpo: { card: { custom_attributes: { chave => { '$valor' => "conversa.atributos.#{chave}" } } } } }
    end
  end

  # Decide pelo card (o que já chegou), não pelos anexos. O fim só com o card ainda em Documentação.
  def decide
    tudo_ok = [{ id: 'docs_ok', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: 'Pôr a etiqueta docs ok',
                 caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { por: ['docs-ok'] } },
               { id: 'para_emissao', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Levar para Emissão', caminho: { id: card_id },
                 corpo: { stage_id: emissao.id } }, a_seguradora]
    { id: 'decide', tipo: 'decidir', le: %w[card], pergunta: 'O que falta para emitir o seguro auto?',
      caminhos: [
        caminho('Ilegível', 'ilegivel', 'um documento do card não deu para ler',
                [escrever('pede_de_novo', 'Peça de novo o documento, dizendo o que não deu para ler.')]),
        caminho('Falta algo', 'falta_algo', 'os documentos do card dão para ler, mas falta algum da lista',
                [escrever('pede_resto', 'Peça só os documentos da lista que ainda não chegaram.')]),
        caminho('Tudo recebido', 'tudo_recebido', 'CNH, documento do carro e comprovante estão no card como recebidos',
                [so_se_em_documentacao('ainda_la3', tudo_ok)])
      ],
      nenhum: [], de_novo: { caminhos: %w[ilegivel falta_algo nenhum], desde: 'espera_doc' } }
  end

  # Passos 7 e 8: os dados do card à seguradora; o número da proposta, ou o motivo da recusa, volta para o card.
  def a_seguradora
    recusou = { id: 'avisa_cida', tipo: 'avisar', para: { pessoas: [cida.id] },
                texto: ['A seguradora recusou a proposta de ', { '$valor' => 'contato.nome' }, ': ',
                        { '$valor' => 'card.atributos.motivo_da_recusa' }] }
    { id: 'seguradora', tipo: 'webhook', descricao: 'Mandar à seguradora', url: seguradora,
      corpo: { nome: { '$valor' => 'contato.nome' }, telefone: { '$valor' => 'contato.telefone' }, cnh: { '$valor' => 'card.atributos.cnh' } },
      gravar: [{ chave: 'proposta.numero', destino: 'card.atributos.numero_da_proposta' },
               { chave: 'motivo', destino: 'card.atributos.motivo_da_recusa' }],
      se_recusar: [recusou] }
  end

  # O sistema da seguradora: guarda cada pedido e responde o que o exemplo pede.
  def seguradora_responde(status, corpo)
    stub_request(:post, seguradora).to_return do |pedido|
      pedidos_a_seguradora << JSON.parse(pedido.body)
      { status: status, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  # Um job por vez, como no Sidekiq, com o do evento do card no meio.
  def drenar
    drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def entra_em_documentacao
    Crm::Cards::Creator.new(account: account, user: cida, params: {
                              pipeline_id: funil.id, stage_id: documentacao.id, contact_id: marcos.id, owner_id: corretor.id,
                              conversation_id: conversa.id, inbox_id: inbox.id, title: 'Seguro auto do Marcos', currency: 'BRL'
                            }).perform
    drenar
    account.crm_cards.find_by!(title: 'Seguro auto do Marcos')
  end

  # A mídia como o canal grava: a mensagem sem texto, com o arquivo anexado.
  def foto_ou_pdf(midia, nome)
    file_type, content_type, arquivo = { foto: [:image, 'image/png', 'sample.png'], pdf: [:file, 'application/pdf', 'sample.pdf'] }.fetch(midia)
    mensagem = conversa.messages.new(account: account, inbox: inbox, message_type: :incoming, sender: marcos, content: nil)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: file_type)
    anexo.file.attach(io: Rails.root.join('spec/assets', arquivo).open, filename: nome, content_type: content_type, identify: false)
    mensagem.tap(&:save!)
  end

  def manda(midia, nome, quando:)
    travel_to(quando) do
      foto_ou_pdf(midia, nome)
      drenar
    end
  end

  def escreve(texto, quando:) = travel_to(quando) { cliente_escreve(conversa, texto) }

  # A varredura do motor naquele instante: acorda as esperas vencidas.
  def varre(instante)
    travel_to(instante) do
      Autonomia::Automacao::VarreduraJob.perform_now
      drenar
    end
  end

  def modelos(nome) = chamadas_para('graph.facebook.com').count { |chamada| chamada.corpo.dig('template', 'name') == nome }
  def textos = chamadas_para('graph.facebook.com').filter_map { |chamada| chamada.corpo.dig('text', 'body') }
  def execucao = Autonomia::Automacao::Execucao.sole
  def ramos = Autonomia::Automacao::Registro.where(passo: 'decide').order(:id).map { |item| item.dados['ramo'] }
  def idas(nome) = ia_recebeu.count { |corpo| corpo.dig('text', 'format', 'name') == nome }
  def pedidos(nome) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == nome }

  # Os campos do card que a IA recebeu (a leitura "card" vai como JSON no texto da entrada).
  def card_lido(corpo)
    texto = corpo['input'].first['content'].find { |parte| parte['type'] == 'input_text' }['text']
    JSON.parse(texto).dig('conversa', 'card', 'attributes')
  end

  # O que cada ida do extrair levou: o nome de cada PDF, "foto" por imagem.
  def lidos_pelo_extrair
    pedidos('automacao_extrair').map do |corpo|
      corpo['input'].first['content'].filter_map { |parte| parte['filename'] || ('foto' if parte['type'] == 'input_image') }
    end
  end

  def ia_roteiro
    fila = respostas
    roteiro = Object.new
    roteiro.define_singleton_method(:fetch) do |nome|
      lista = fila.fetch(nome)
      atual = lista.size > 1 ? lista.shift : lista.first
      atual.is_a?(Proc) ? atual.call : atual
    end
    roteiro
  end

  def atributo(chave, modelo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo, attribute_display_type: 'text')
  end

  before do
    travel_to(inicio)
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name)
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    [cida, corretor].each { |pessoa| create(:inbox_member, user: pessoa, inbox: inbox) }
    %w[conversation_attribute card_attribute].product(documentos.keys).each { |modelo, chave| atributo(chave, modelo) }
    %w[numero_da_proposta motivo_da_recusa].each { |chave| atributo(chave, 'card_attribute') }
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('propostas.seguradora.test').and_return(['93.184.216.34'])
    seguradora_responde(201, { proposta: { numero: 'PR-2026-0714' } })
    create(:label, account: account, title: 'docs-ok', description: 'Documentos conferidos')
    corpos = { 'lista_documentos' => 'Oi {{1}}, para emitir o seu seguro auto, mande: {{2}}.', 'lembrete_documentos' => 'Oi {{1}}, documentos.' }
    canal.update!(message_templates: corpos.map do |nome, corpo|
      { 'name' => nome, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => corpo }] }
    end)
    receptor_whatsapp_cloud
    # O "fechado" foi há 2 dias: a janela de 24 h está fechada, e a lista sai pelo modelo aprovado, como o termo diz.
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: marcos,
                     content: 'Fechado, pode fazer o seguro', created_at: inicio - 2.days)
    [documentacao, emissao, perdido]
    automacao = montar_automacao(cida, account, nome: 'Documentação completa para emitir', receita: receita)
    ligar_automacao(cida, account, automacao)
    clear_enqueued_jobs
    ia_responde(account, ia_roteiro)
    card
  end

  after { Current.reset }

  def entrada = card.reload.entered_stage_at

  it 'passo 1: a lista do ramo sai pelo modelo, e a automação espera o primeiro documento por 2 dias', :aggregate_failures do
    expect(modelos('lista_documentos')).to eq(1)
    lista = chamadas_para('graph.facebook.com').find { |chamada| chamada.corpo.dig('template', 'name') == 'lista_documentos' }
    expect(lista.corpo.dig('template', 'components', 0, 'parameters').pluck('text')).to eq(['Marcos', lista_do_auto])
    expect([execucao.estado, execucao.cursor]).to eq(%w[esperando espera_doc])
    expect(execucao.due_at).to be_within(1.minute).of(entrada + 2.days)
    expect(ia_recebeu).to be_empty
  end

  it 'passos 2 e 3: a foto ilegível vai à IA, o card guarda o que não deu para ler, o pedido sai e a automação volta a esperar',
     :aggregate_failures do
    respostas['automacao_extrair'] << extraiu('cnh' => 'não dá para ler o CPF')
    respostas['automacao_decidir'] << { 'caminho' => 'ilegivel', 'motivo' => 'O CPF está borrado.' }
    respostas['automacao_escrever'] << { 'texto' => 'Não consegui ler o CPF da CNH. Pode mandar outra foto?' }

    manda(:foto, 'cnh.png', quando: entrada + 3.hours)

    expect(card.reload.custom_attributes).to eq('cnh' => 'não dá para ler o CPF')
    expect(ramos).to eq(%w[ilegivel])
    expect(textos).to eq(['Não consegui ler o CPF da CNH. Pode mandar outra foto?'])
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando espera_doc])
    expect(execucao.due_at).to be_within(1.minute).of(entrada + 3.hours + 2.days)
    expect(conversa.messages.where(private: true)).to be_empty
  end

  it 'passo 4: o PDF da CNH chega legível, e a IA escreve só o que falta, lendo o card', :aggregate_failures do
    card.update!(value_cents: 1_234_500)
    respostas['automacao_extrair'] << extraiu('cnh' => 'recebido')
    respostas['automacao_decidir'] << { 'caminho' => 'falta_algo', 'motivo' => 'Só chegou a CNH.' }
    respostas['automacao_escrever'] << { 'texto' => 'Recebi a CNH. Faltam o documento do carro e o comprovante de endereço.' }

    manda(:pdf, 'cnh.pdf', quando: entrada + 1.day)

    expect(ramos).to eq(%w[falta_algo])
    expect(textos).to eq(['Recebi a CNH. Faltam o documento do carro e o comprovante de endereço.'])
    expect(pedidos('automacao_escrever').sole.to_json).to include('Peça só os documentos da lista que ainda não chegaram.')
    expect(card_lido(pedidos('automacao_escrever').sole)).to eq('cnh' => 'recebido')
    expect(card_lido(pedidos('automacao_decidir').sole)).to eq('cnh' => 'recebido')
    # Decisão 9 (#2780): o valor da venda só decide; a IA nunca o recebe para escrever.
    expect(pedidos('automacao_escrever').sole.to_json).not_to include('12345')
    expect(pedidos('automacao_decidir').sole.to_json).to include('12345')
    expect(pedidos('automacao_decidir').sole['input'].first['content'].pluck('type')).to eq(%w[input_text])
    expect(lidos_pelo_extrair).to eq([%w[cnh.pdf]])
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando espera_doc])
  end

  it 'passo 5: "já mando" em texto não recomeça a conta; o lembrete sai no 2º dia', :aggregate_failures do
    prazo = execucao.due_at
    escreve('Já mando os documentos', quando: entrada + 1.day)
    expect([execucao.reload.estado, execucao.due_at]).to eq(['esperando', prazo])

    varre(entrada + 2.days + 10.minutes)

    expect(modelos('lembrete_documentos')).to eq(1)
    expect(ia_recebeu).to be_empty
  end

  it 'passo 5: no 2º dia um lembrete só; no 4º, o retorno para o corretor e o fim', :aggregate_failures do
    varre(entrada + 2.days + 10.minutes)
    expect(modelos('lembrete_documentos')).to eq(1)

    varre(entrada + 2.days + 25.minutes)
    varre(entrada + 3.days)
    expect(modelos('lembrete_documentos')).to eq(1)
    expect(Crm::FollowUp.count).to eq(0)

    varre(entrada + 4.days + 10.minutes)

    expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, recipient_mode: 'card_owner', title: 'Ligar para Marcos: documentos')
    expect(execucao.reload.estado).to eq('concluida')
    expect(modelos('lembrete_documentos')).to eq(1)
    expect(ia_recebeu).to be_empty
  end

  it 'o card movido à mão para "Emissão" antes do 2º dia não recebe lembrete nem retorno', :aggregate_failures do
    travel_to(entrada + 1.day) do
      Crm::Cards::Mover.new(card: card, actor: cida, target_stage: emissao).perform
      drenar
    end

    varre(entrada + 2.days + 10.minutes)
    varre(entrada + 4.days + 10.minutes)

    expect([modelos('lembrete_documentos'), Crm::FollowUp.count]).to eq([0, 0])
    expect(execucao.reload.estado).to eq('concluida')
    expect(Autonomia::Automacao::Registro.where(passo: 'ainda_la_parar').count).to eq(1)
  end

  it 'passo 5: o documento depois do lembrete abre uma pausa nova, com o seu próprio lembrete', :aggregate_failures do
    respostas['automacao_extrair'] << extraiu('cnh' => 'recebido')
    respostas['automacao_decidir'] << { 'caminho' => 'falta_algo', 'motivo' => 'Só chegou a CNH.' }
    respostas['automacao_escrever'] << { 'texto' => 'Faltam o documento do carro e o comprovante.' }
    varre(entrada + 2.days + 10.minutes)
    expect(modelos('lembrete_documentos')).to eq(1)

    manda(:foto, 'cnh.png', quando: entrada + 3.days)
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando espera_doc])

    varre(entrada + 4.days + 10.minutes)
    expect([modelos('lembrete_documentos'), Crm::FollowUp.count]).to eq([1, 0])

    varre(entrada + 5.days + 10.minutes)
    expect(modelos('lembrete_documentos')).to eq(2)
    expect(Crm::FollowUp.count).to eq(0)
  end

  # A 2ª e a 3ª foto chegam enquanto a IA lê a 1ª: a execução anda, e ninguém a acorda. Na volta ao "esperar até", a
  # janela começa quando ele foi cumprido: as duas contam, o laço roda de novo na hora, e a 2ª ida leva só as duas.
  it '3 fotos de uma vez: nenhuma se perde, nenhuma vai duas vezes, e o card guarda cada documento', :aggregate_failures do
    # O relógio do spec está parado: as duas chegam 1 segundo depois, enquanto a IA lê.
    chegam_mais = lambda do
      travel(1.second)
      %w[crlv.png comprovante.png].each { |nome| foto_ou_pdf(:foto, nome) }
      extraiu('cnh' => 'recebido')
    end
    respostas['automacao_extrair'].push(chegam_mais, extraiu('doc_carro' => 'recebido', 'comprovante' => 'recebido'))
    respostas['automacao_decidir'].push({ 'caminho' => 'falta_algo', 'motivo' => 'Só a CNH.' },
                                        { 'caminho' => 'tudo_recebido', 'motivo' => 'Chegaram os três.' })
    respostas['automacao_escrever'] << { 'texto' => 'Faltam o documento do carro e o comprovante.' }

    manda(:foto, 'cnh.png', quando: entrada + 2.hours)

    expect(lidos_pelo_extrair).to eq([%w[foto], %w[foto foto]])
    expect(card.reload.custom_attributes).to eq('cnh' => 'recebido', 'doc_carro' => 'recebido', 'comprovante' => 'recebido',
                                                'numero_da_proposta' => 'PR-2026-0714')
    expect(ramos).to eq(%w[falta_algo tudo_recebido])
    expect(card.stage_id).to eq(emissao.id)
  end

  # O laço longo: 7 documentos em 7 pausas. A CNH do começo continua no card, e o "decidir" lê o card, não os anexos.
  it '7 documentos ao longo do laço: cada ida lê só o novo, e a CNH do começo continua contando', :aggregate_failures do
    pdfs = %w[cnh.pdf carro-1.pdf carro-2.pdf carro-3.pdf carro-4.pdf carro-5.pdf comprovante.pdf]
    respostas['automacao_extrair'].push(extraiu('cnh' => 'recebido'), *Array.new(4) { extraiu('doc_carro' => 'a placa não dá para ler') },
                                        extraiu('doc_carro' => 'recebido'), extraiu('comprovante' => 'recebido'))
    respostas['automacao_decidir'].push({ 'caminho' => 'falta_algo', 'motivo' => 'Só a CNH.' },
                                        *Array.new(4) { { 'caminho' => 'ilegivel', 'motivo' => 'A placa não dá para ler.' } },
                                        { 'caminho' => 'falta_algo', 'motivo' => 'Falta o comprovante.' },
                                        { 'caminho' => 'tudo_recebido', 'motivo' => 'Os três no card.' })
    respostas['automacao_escrever'] << { 'texto' => 'Pode mandar de novo?' }

    pdfs.each_with_index { |nome, indice| manda(:pdf, nome, quando: entrada + (indice + 1).hours) }

    expect(lidos_pelo_extrair).to eq(pdfs.zip)
    expect(Autonomia::Automacao::Registro.where(passo: 'extrai').map { |item| item.dados.key?('marco_dos_anexos') }).to eq([true] * 7)
    expect(card_lido(pedidos('automacao_decidir').last)).to eq('cnh' => 'recebido', 'doc_carro' => 'recebido', 'comprovante' => 'recebido')
    expect(card.reload.custom_attributes).to eq('cnh' => 'recebido', 'doc_carro' => 'recebido', 'comprovante' => 'recebido',
                                                'numero_da_proposta' => 'PR-2026-0714')
    expect(ramos.last).to eq('tudo_recebido')
    expect(card.stage_id).to eq(emissao.id)
    expect(execucao.reload.estado).to eq('concluida')
  end

  it 'o card movido à mão para "Perdido" não volta para "Emissão" quando o último documento chega', :aggregate_failures do
    respostas['automacao_extrair'] << extraiu('comprovante' => 'recebido')
    respostas['automacao_decidir'] << { 'caminho' => 'tudo_recebido', 'motivo' => 'Os três no card.' }
    travel_to(entrada + 1.hour) do
      Crm::Cards::Mover.new(card: card, actor: cida, target_stage: perdido).perform
      drenar
    end

    manda(:pdf, 'comprovante.pdf', quando: entrada + 2.hours)

    expect(card.reload.stage_id).to eq(perdido.id)
    expect(conversa.reload.label_list).not_to include('docs-ok')
    expect(Autonomia::Automacao::Registro.where(passo: 'ainda_la3_parar').count).to eq(1)
    expect(execucao.reload.estado).to eq('concluida')
  end

  it 'passo 6: tudo recebido põe a etiqueta "docs-ok", move para "Emissão" e acaba', :aggregate_failures do
    respostas['automacao_extrair'] << extraiu('comprovante' => 'recebido')
    respostas['automacao_decidir'] << { 'caminho' => 'tudo_recebido', 'motivo' => 'Os três chegaram e dão para ler.' }

    manda(:pdf, 'comprovante.pdf', quando: entrada + 1.day)

    expect(conversa.reload.label_list).to include('docs-ok')
    expect(card.reload.stage_id).to eq(emissao.id)
    expect(execucao.reload.estado).to eq('concluida')
    expect(textos).to be_empty
  end

  it 'passo 7: com tudo recebido, os dados vão à seguradora e o card guarda o número da proposta', :aggregate_failures do
    respostas['automacao_extrair'] << extraiu('cnh' => 'recebido', 'doc_carro' => 'recebido', 'comprovante' => 'recebido')
    respostas['automacao_decidir'] << { 'caminho' => 'tudo_recebido', 'motivo' => 'Os três chegaram e dão para ler.' }

    manda(:pdf, 'documentos.pdf', quando: entrada + 1.day)

    expect(pedidos_a_seguradora.sole).to eq('nome' => 'Marcos', 'telefone' => '+5511900002714', 'cnh' => 'recebido')
    expect(card.reload.custom_attributes).to include('numero_da_proposta' => 'PR-2026-0714')
    expect(card.custom_attributes).not_to have_key('motivo_da_recusa')
    expect(Notification.where(user: cida, notification_type: 'conversation_mention')).to be_empty
    expect(Autonomia::Automacao::Registro.where(passo: 'seguradora').sole).to have_attributes(resultado: 'ok', motivo: nil)
  end

  it 'passo 8: a seguradora recusa; o card guarda o motivo e a Dona Cida é avisada com ele', :aggregate_failures do
    seguradora_responde(422, { motivo: 'CNH vencida' })
    respostas['automacao_extrair'] << extraiu('cnh' => 'recebido', 'doc_carro' => 'recebido', 'comprovante' => 'recebido')
    respostas['automacao_decidir'] << { 'caminho' => 'tudo_recebido', 'motivo' => 'Os três chegaram e dão para ler.' }

    manda(:pdf, 'documentos.pdf', quando: entrada + 1.day)

    expect(card.reload.custom_attributes).to include('motivo_da_recusa' => 'CNH vencida')
    expect(card.custom_attributes).not_to have_key('numero_da_proposta')
    expect(Notification.where(user: cida, notification_type: 'conversation_mention')).to exist
    nota = conversa.messages.where(private: true).order(:id).last
    expect(nota.content).to include('A seguradora recusou a proposta de Marcos: CNH vencida')
    expect(Autonomia::Automacao::Registro.where(passo: %w[seguradora avisa_cida]).order(:id).pluck(:passo, :resultado, :motivo))
      .to eq([%w[seguradora ok webhook_recusado], ['avisa_cida', 'ok', nil]])
  end
end
