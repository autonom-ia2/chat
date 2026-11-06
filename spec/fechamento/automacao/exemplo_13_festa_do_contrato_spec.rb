require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 13 dos termos de aceite: "Festa do contrato ao depoimento".
#
# > "Depois que fecha a festa, quero que o sistema cuide de tudo até o dia: confirmar convidados, mandar o cardápio,
# > lembrar a equipe e depois pedir a avaliação." — Rose, dona do buffet
#
# Montado como a Rose montaria, pela API da tela: uma automação no card ganho e uma por data da festa (G6, "N dias
# antes/depois de um campo de data do card"). As datas são a da festa e a da próxima oferta, que a 1ª automação grava
# com a data calculada (G16, festa + 11 meses). O relógio anda até cada data e a varredura do motor dispara o gatilho.
# Mensagem ao cliente fora da janela de 24 h vai pelo modelo aprovado (G1) e para no receptor de teste; o e-mail sai
# pela caixa de e-mail da conta (G2). A IA é o dublê. Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
#
# "Grava no card" (passos 3 e 4): o extrair grava no contato ou na conversa, e uma ação copia para o card ($valor, G16).
RSpec.describe 'Fechamento #2414 · exemplo 13: festa do contrato ao depoimento', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:rose) { create(:user, account: account, role: :administrator, name: 'Rose Dona') }
  let(:cozinha) { create(:user, account: account, role: :agent, name: 'Cozinha') }
  let(:decoracao) { create(:user, account: account, role: :agent, name: 'Decoração') }
  let(:familia) { create(:contact, account: account, name: 'Ana', email: 'ana@exemplo.com', phone_number: '+5511900000002') }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: familia, source_id: '5511900000002') }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: familia, contact_inbox: contact_inbox) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: rose, name: 'Festas') }
  let(:funil) { funil_e_etapa.first }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: funil_e_etapa.last, title: 'Festa da Ana', currency: 'BRL', contact: familia,
                              primary_conversation: conversa,
                              custom_attributes: { 'data_da_festa' => '2027-03-20', 'link_contrato' => 'https://buffet.exemplo/contrato/42' })
  end
  let(:roteiro) { {} }

  def modelo(nome) = { nome: nome, idioma: 'pt_BR', variaveis: [[{ '$valor' => 'contato.nome' }]] }
  def mensagem(id, nome, texto) = { id: id, tipo: 'mensagem', texto: [texto], modelo: modelo(nome) }
  def card_id = { '$valor' => 'card.id' }
  def no_dia(dias, quando) = { tipo: 'card.data', campo: 'data_da_festa', dias: dias, quando: quando, hora: 9 }

  def resposta_do_cliente(id, prazo_em_dias)
    { id: id, tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true },
      prazo: { valor: prazo_em_dias, unidade: 'dias' } }
  end

  def para_o_card(id, descricao, chaves)
    atributos = chaves.index_with { |chave| { '$valor' => "conversa.atributos.#{chave}" } }
    { id: id, tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: descricao, caminho: { id: card_id },
      corpo: { card: { custom_attributes: atributos } } }
  end

  def etiqueta(id, nome)
    { id: id, tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: "Pôr a etiqueta #{nome}",
      caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { por: [nome] } }
  end

  # As receitas, uma por momento do termo, montadas e ligadas pela Rose.
  def receitas
    { contrato: receita_do_contrato, convidados: receita_dos_convidados, cardapio: receita_do_cardapio,
      equipe: { gatilho: no_dia(7, 'antes'), passos: [
        { id: 'resumo', tipo: 'resumir', le: %w[conversa], linhas: 4, destino: { avisar: { pessoas: [cozinha.id, decoracao.id] } } }
      ] },
      lembrete: { gatilho: no_dia(1, 'antes'), passos: [mensagem('lembrete', 'festa_lembrete', 'Amanhã é a festa!')] },
      avaliacao: receita_da_avaliacao,
      proximo_ano: { gatilho: { tipo: 'card.data', campo: 'proxima_oferta', dias: 0, quando: 'antes', hora: 9 },
                     passos: [mensagem('oferta', 'festa_proxima', 'Vamos fazer a festa do próximo aniversário?')] } }
  end

  def receita_do_contrato
    { gatilho: { tipo: 'card.ganho', funil_id: funil.id }, passos: [
      { id: 'contrato', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Contrato da sua festa'],
        texto: ['Oi ', { '$valor' => 'contato.nome' }, ', o contrato da festa: ', { '$valor' => 'card.atributos.link_contrato' }] },
      etiqueta('festa_novembro', 'festa-novembro'),
      { id: 'proxima_oferta', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Marcar a oferta do próximo ano',
        caminho: { id: card_id }, corpo: { card: { custom_attributes: { proxima_oferta: {
          '$data' => { de: { '$valor' => 'card.atributos.data_da_festa' }, mais: { valor: 11, unidade: 'meses' } }
        } } } } }
    ] }
  end

  def receita_dos_convidados
    { gatilho: no_dia(30, 'antes'), passos: [
      mensagem('pergunta', 'festa_convidados', 'Quantos convidados e quantas crianças?'), resposta_do_cliente('resposta', 5),
      { id: 'numeros', tipo: 'extrair', campos: [
        { chave: 'convidados', descricao: 'quantos convidados', destino: 'conversa.atributos.convidados' },
        { chave: 'criancas', descricao: 'quantas crianças', destino: 'conversa.atributos.criancas' }
      ] },
      para_o_card('no_card', 'Gravar os números no card', %w[convidados criancas])
    ] }
  end

  def receita_do_cardapio
    { gatilho: no_dia(15, 'antes'), passos: [
      mensagem('cardapio', 'festa_cardapio', 'O cardápio. Alguém tem alergia?'), resposta_do_cliente('resposta', 5),
      { id: 'alergias', tipo: 'extrair', campos: [{ chave: 'alergias', descricao: 'alergias citadas', destino: 'conversa.atributos.alergias' }] },
      para_o_card('no_card', 'Gravar as alergias no card', %w[alergias])
    ] }
  end

  def receita_da_avaliacao
    promotor = [{ id: 'depoimento', tipo: 'mensagem', texto: ['Que bom! Pode mandar um depoimento e fotos da festa?'] },
                etiqueta('etiqueta_depoimento', 'depoimento')]
    detrator = [{ id: 'avisa_rose', tipo: 'resumir', le: %w[mensagens_recentes], linhas: 3, destino: { avisar: { pessoas: [rose.id] } } }]
    { gatilho: no_dia(1, 'depois'), passos: [
      mensagem('nota', 'festa_nota', 'Que nota de 0 a 10 você dá?'), resposta_do_cliente('resposta', 5),
      { id: 'qual_nota', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'Qual nota de 0 a 10 a família deu?', caminhos: [
        { nome: '9 ou 10', chave: 'promotor', descricao: 'nota 9 ou 10', passos: promotor },
        { nome: '6 ou menos', chave: 'detrator', descricao: 'nota de 0 a 6', passos: detrator }
      ], nenhum: [] }
    ] }
  end

  def atributo(chave, modelo, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo, attribute_display_type: tipo)
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name)
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    [rose, cozinha, decoracao].each { |pessoa| create(:inbox_member, user: pessoa, inbox: canal.inbox) }
    criar_campos
    %w[festa-novembro depoimento].each { |nome| create(:label, account: account, title: nome, description: "Festa: #{nome}") }
    canal.update!(message_templates: modelos_aprovados)
  end

  # Os campos do card que a Rose criou, e os da conversa onde o extrair grava antes de copiar para o card.
  def criar_campos
    respostas = { 'convidados' => 'number', 'criancas' => 'number', 'alergias' => 'text' }
    respostas.merge('data_da_festa' => 'date', 'proxima_oferta' => 'date', 'link_contrato' => 'text')
             .each { |chave, tipo| atributo(chave, 'card_attribute', tipo) }
    respostas.each { |chave, tipo| atributo(chave, 'conversation_attribute', tipo) }
  end

  def modelos_aprovados
    %w[festa_convidados festa_cardapio festa_lembrete festa_nota festa_proxima].map do |nome|
      { 'name' => nome, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => "Oi {{1}}, mensagem #{nome}." }] }
    end
  end

  # Ligadas um mês antes de tudo: ligar não age no passado.
  def ligar_tudo
    receitas.each { |nome, receita| ligar_automacao(rose, account, montar_automacao(rose, account, nome: "Festa: #{nome}", receita: receita)) }
  end

  # A varredura dos gatilhos de tempo às 9h30 do dia, no fuso da conta, e os jobs que ela abre.
  def chega_o_dia(dia)
    travel_to(fuso.parse("#{dia} 09:30")) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      rodar_jobs
    end
  end

  # O cliente responde no mesmo dia; a espera acorda e os passos seguintes rodam.
  def cliente_responde(dia, texto)
    travel_to(fuso.parse("#{dia} 11:00")) do
      cliente_escreve(conversa, texto)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      rodar_jobs
    end
  end

  def modelos_enviados = chamadas_para('graph.facebook.com').filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')
  def historico(nome) = Autonomia::Automacao::Registro.where(automacao_id: automacao_id(nome)).order(:id).pluck(:passo, :resultado)

  def automacao_id(nome) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: "Festa: #{nome}").id

  before do
    preparar_conta
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    travel_to(fuso.parse('2026-12-01 10:00')) do
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: familia,
                       content: 'Quero fechar a festa da Ana')
      card
      ligar_tudo
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  it 'passo 1: festa fechada, o contrato vai por e-mail, a etiqueta entra e a oferta do próximo ano fica marcada', :aggregate_failures do
    travel_to(fuso.parse('2026-12-02 15:00')) do
      Crm::Cards::Closer.new(card: card, actor: rose, result: 'won').perform
      rodar_jobs
      perform_enqueued_jobs(only: Autonomia::Automacao::EventoDoCardJob)
      rodar_jobs
    end

    email = Conversation.where(inbox: caixa_de_email).sole
    expect(email.contact).to eq(familia)
    expect(email.additional_attributes['mail_subject']).to eq('Contrato da sua festa')
    expect(email.messages.outgoing.sole.content).to eq('Oi Ana, o contrato da festa: https://buffet.exemplo/contrato/42')
    expect(conversa.reload.label_list).to include('festa-novembro')
    expect(card.reload.custom_attributes).to include('data_da_festa' => '2027-03-20', 'proxima_oferta' => '2028-02-20')
    expect(historico(:contrato)).to eq([%w[contrato ok], %w[festa_novembro ok], %w[proxima_oferta ok]])
  end

  it 'passos 2 e 3: 30 dias antes pergunta pelo modelo aprovado, e os números da resposta vão para o card', :aggregate_failures do
    roteiro['automacao_extrair'] = { 'convidados' => 40, 'criancas' => 15 }
    chega_o_dia('2027-02-18')
    expect(modelos_enviados).to eq(%w[festa_convidados])

    cliente_responde('2027-02-18', 'Vão ser 40 convidados, 15 crianças.')

    expect(card.reload.custom_attributes).to include('convidados' => 40, 'criancas' => 15)
    # O "esperar até" grava uma linha quando começa a esperar e outra quando a resposta chega.
    expect(historico(:convidados).uniq).to eq([%w[pergunta ok], %w[resposta ok], %w[numeros ok], %w[no_card ok]])
  end

  it 'passo 4: 15 dias antes manda o cardápio pelo modelo, e as alergias da resposta vão para o card', :aggregate_failures do
    roteiro['automacao_extrair'] = { 'alergias' => 'amendoim' }
    chega_o_dia('2027-03-05')
    expect(modelos_enviados).to eq(%w[festa_cardapio])

    cliente_responde('2027-03-05', 'Uma criança tem alergia a amendoim.')

    expect(card.reload.custom_attributes).to include('alergias' => 'amendoim')
  end

  it 'passo 5: 7 dias antes, a cozinha e a decoração recebem no sino o resumo da festa', :aggregate_failures do
    card.update!(custom_attributes: card.custom_attributes.merge('convidados' => 40, 'alergias' => 'amendoim'))
    roteiro['automacao_resumir'] = { 'resumo' => 'Festa da Ana em 20/03: 40 convidados, alergia a amendoim, tema fundo do mar.' }

    chega_o_dia('2027-03-13')

    expect([mencoes_para(cozinha).count, mencoes_para(decoracao).count]).to eq([1, 1])
    resumo = conversa.messages.where(private: true).find_by('content LIKE ?', '%mention://user/%')
    expect(resumo.content).to include('40 convidados', 'amendoim', "mention://user/#{cozinha.id}/", "mention://user/#{decoracao.id}/")
    expect(chamadas_para('graph.facebook.com')).to be_empty
  end

  it 'passo 6: 1 dia antes, a família é lembrada pelo modelo aprovado' do
    chega_o_dia('2027-03-19')

    expect(modelos_enviados).to eq(%w[festa_lembrete])
  end

  context 'with o dia seguinte à festa (passos 7 a 9)' do
    before { chega_o_dia('2027-03-21') }

    it 'pede a nota pelo modelo aprovado' do
      expect(modelos_enviados).to eq(%w[festa_nota])
    end

    it 'nota 9 ou 10: pede depoimento e fotos e põe a etiqueta depoimento', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'promotor', 'motivo' => 'deu nota 10' }
      cliente_responde('2027-03-21', 'Nota 10! Foi perfeito.')

      expect(conversa.reload.label_list).to include('depoimento')
      saida = chamadas_para('graph.facebook.com').last.corpo
      expect(saida.dig('text', 'body')).to eq('Que bom! Pode mandar um depoimento e fotos da festa?')
      expect(mencoes_para(rose)).to be_empty
    end

    it 'nota 6 ou menos: avisa a Rose na hora, com o resumo', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'detrator', 'motivo' => 'deu nota 4' }
      roteiro['automacao_resumir'] = { 'resumo' => 'A família deu nota 4: o bolo atrasou uma hora.' }
      cliente_responde('2027-03-21', 'Nota 4. O bolo atrasou uma hora.')

      expect(mencoes_para(rose).count).to eq(1)
      expect(conversa.messages.where(private: true).find_by('content LIKE ?', "%mention://user/#{rose.id}/%").content).to include('bolo atrasou')
      expect(conversa.reload.label_list).not_to include('depoimento')
    end
  end

  it 'passo 10: 11 meses depois da festa, oferece a do próximo aniversário pelo modelo aprovado' do
    card.update!(custom_attributes: card.custom_attributes.merge('proxima_oferta' => '2028-02-20'))

    chega_o_dia('2028-02-20')

    expect(modelos_enviados).to eq(%w[festa_proxima])
  end
end
