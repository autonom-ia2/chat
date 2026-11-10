require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 12 dos termos de aceite: "Visita que aconteceu decide o próximo passo".
#
# > "Depois da visita o corretor esquece de anotar e de mandar a proposta. Quero que o sistema faça isso."
# > — Márcio, dono da imobiliária
#
# Começa quando: o card entra na etapa "Visita feita" (o pós-reunião da agenda já move quando a visita acontece).
#   1. Manda à Ana: "Obrigado pela visita! O que achou do apartamento?".
#   2. Cria um retorno para o corretor: "Como foi a visita com a Ana? Escreva uma frase no campo 'Como foi a visita' do
#      card".
#   3. Espera até a Ana responder ou o campo ser preenchido, por até 24 horas.
#   4. A IA decide pelo que os dois disseram: "gostou", "quer outra opção" ou "não gostou".
#   5. Gostou: move para "Proposta", manda à Ana por e-mail a lista de documentos para a proposta e cria retorno de 2
#      dias.
#   6. Quer outra opção: a IA extrai o que faltou (vaga, andar, preço), grava no card e cria retorno para mandar 3 opções.
#   7. Não gostou: põe a etiqueta "procurando", fecha o card e coloca a Ana na campanha de lançamentos.
#   8. Nada em 24 horas: avisa o Márcio.
# Resultado: toda visita tem próximo passo no mesmo dia. O Márcio vê no quadro quem está em proposta, quem quer outra
# opção e quem voltou para a campanha.
#
# Montado como o Márcio montaria, pela API da tela, numa automação só (G5). A Ana está na janela de 24 h (falou na
# visita), então a mensagem vai em texto livre. O e-mail sai pela caixa de e-mail da imobiliária (G2); o retorno é do
# corretor, o responsável do card (G3); fechar o card é a G25. "Coloca na campanha de lançamentos" é pôr a etiqueta do
# público dela (G14). "Grava no card" (passo 6): o extrair grava na conversa, e uma ação copia para o card (G16), como no
# exemplo 13. A IA é o dublê. Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
RSpec.describe 'Fechamento #2414 · exemplo 12: visita que aconteceu decide o próximo passo', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:marcio) { create(:user, account: account, role: :administrator, name: 'Márcio') }
  let(:corretor) { create(:user, account: account, role: :agent, name: 'Paulo Corretor') }
  let(:ana) { create(:contact, account: account, name: 'Ana', email: 'ana@exemplo.com', phone_number: '+5511900000012') }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: ana, source_id: '5511900000012') }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: ana, contact_inbox: contact_inbox, status: :open) }
  let(:funil_e_entrada) { create_crm_pipeline(account: account, user: marcio, name: 'Imóveis') }
  let(:funil) { funil_e_entrada.first }
  let(:visita_feita) { create_crm_stage(account: account, pipeline: funil, name: 'Visita feita', position: 2) }
  let(:proposta) { create_crm_stage(account: account, pipeline: funil, name: 'Proposta', position: 3) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: funil_e_entrada.last, inbox: canal.inbox, contact: ana, primary_conversation: conversa,
                              owner: corretor, title: 'Ana - apartamento Moema', currency: 'BRL')
  end
  let(:roteiro) { {} }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def card_id = { '$valor' => 'card.id' }
  def conversa_id = { '$valor' => 'conversa.id' }

  def retorno(id, titulo, daqui) = { id: id, tipo: 'retorno', titulo: titulo, daqui: daqui }

  def etiqueta(id, nome)
    { id: id, tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: "Pôr a etiqueta #{nome}",
      caminho: { conversation_id: conversa_id }, corpo: { por: [nome] } }
  end

  def receita
    respondeu_ou_anotou = { alguma: [
      { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true },
      { campo: { '$valor' => 'card.atributos.como_foi_a_visita' }, op: 'preenchido' }
    ] }
    { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: visita_feita.id }, passos: [
      { id: 'obrigado', tipo: 'mensagem', texto: ['Obrigado pela visita! O que achou do apartamento?'] },
      retorno('corretor_anota', ['Como foi a visita com a Ana? Escreva uma frase no campo ‘Como foi a visita’ do card'],
              { valor: 1, unidade: 'horas' }),
      { id: 'espera', tipo: 'esperar_ate', condicao: respondeu_ou_anotou, prazo: { valor: 24, unidade: 'horas' }, se_vencer: [
        { id: 'avisa_marcio', tipo: 'avisar', para: { pessoas: [marcio.id] },
          texto: ['Ninguém disse nada sobre a visita de ', { '$valor' => 'contato.nome' }, ' em 24 horas.'] },
        { id: 'fim', tipo: 'parar' }
      ] },
      decidir
    ] }
  end

  def decidir
    { id: 'o_que_achou', tipo: 'decidir', le: %w[mensagens_recentes card], pergunta: 'O que a Ana achou do apartamento visitado?',
      caminhos: [
        { nome: 'Gostou', chave: 'gostou', descricao: 'gostou do apartamento', passos: gostou },
        { nome: 'Quer outra opção', chave: 'outra_opcao', descricao: 'quer ver outra opção', passos: quer_outra_opcao },
        { nome: 'Não gostou', chave: 'nao_gostou', descricao: 'não gostou e não quer outra opção agora', passos: nao_gostou }
      ], nenhum: [] }
  end

  def gostou
    [{ id: 'para_proposta', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Levar para Proposta',
       caminho: { id: card_id }, corpo: { stage_id: proposta.id } },
     { id: 'documentos', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Documentos para a proposta'],
       texto: ['Oi ', { '$valor' => 'contato.nome' }, ', para a proposta precisamos de: RG, CPF, comprovante de renda e de residência.'] },
     retorno('proposta_2_dias', ['Acompanhar a proposta da Ana'], { valor: 2, unidade: 'dias' })]
  end

  def quer_outra_opcao
    [{ id: 'o_que_faltou', tipo: 'extrair', le: %w[mensagens_recentes card], campos: [
      { chave: 'vaga', descricao: 'quantas vagas de garagem ela quer', destino: 'conversa.atributos.vaga' },
      { chave: 'andar', descricao: 'o andar que ela prefere', destino: 'conversa.atributos.andar' },
      { chave: 'preco', descricao: 'o preço máximo que ela quer pagar', destino: 'conversa.atributos.preco' }
    ] },
     { id: 'no_card', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Gravar no card o que faltou', caminho: { id: card_id },
       corpo: { card: { custom_attributes: %w[vaga andar preco].index_with { |chave| { '$valor' => "conversa.atributos.#{chave}" } } } } },
     retorno('tres_opcoes', ['Mandar 3 opções para a Ana'], { valor: 1, unidade: 'dias' })]
  end

  def nao_gostou
    [etiqueta('procurando', 'procurando'),
     { id: 'fecha', tipo: 'acao', acao: 'POST crm/cards/:id/close', descricao: 'Fechar o card', caminho: { id: card_id },
       corpo: { result: 'lost', lost_reason: 'Não gostou do imóvel' } },
     etiqueta('lancamentos', 'lancamentos')]
  end

  def atributo(chave, modelo, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo, attribute_display_type: tipo)
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    [marcio, corretor].each { |pessoa| create(:inbox_member, user: pessoa, inbox: canal.inbox) }
    criar_campos_e_etiquetas
    [visita_feita, proposta, card, caixa_de_email]
  end

  def criar_campos_e_etiquetas
    atributo('como_foi_a_visita', 'card_attribute', 'text')
    { 'vaga' => 'number', 'andar' => 'text', 'preco' => 'number' }.each do |chave, tipo|
      atributo(chave, 'conversation_attribute', tipo)
      atributo(chave, 'card_attribute', tipo)
    end
    %w[procurando lancamentos].each { |nome| create(:label, account: account, title: nome, description: "Imóveis: #{nome}") }
  end

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

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  # O pós-reunião da agenda move o card para "Visita feita" depois da visita.
  def visita_feita_as(hora)
    as(hora) do
      Crm::Cards::Mover.new(card: card, actor: corretor, target_stage: visita_feita).perform
      drenar
    end
  end

  def ana_responde_as(hora, texto)
    as(hora) do
      cliente_escreve(conversa, texto)
      drenar
    end
  end

  def varredura_as(hora)
    as(hora) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  def textos_enviados = chamadas_para('graph.facebook.com').filter_map { |chamada| chamada.corpo.dig('text', 'body') }
  def automacao_id = Autonomia::Automacao::Definicao.find_by!(account: account, nome: 'Visita feita').id
  def historico = Autonomia::Automacao::Registro.where(automacao_id: automacao_id).order(:id).pluck(:passo, :resultado, :motivo)
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')
  def retornos = Crm::FollowUp.where(card_id: card.id).order(:id)

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-10 09:00') do
      preparar_conta
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: ana,
                       content: 'Estou chegando para a visita das 14h.')
      ligar_automacao(marcio, account, montar_automacao(marcio, account, nome: 'Visita feita', receita: receita))
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  it 'passos 1 e 2: o card entra em "Visita feita"; a Ana recebe o obrigado e o corretor, o retorno para anotar',
     :aggregate_failures do
    visita_feita_as('2026-11-10 15:00')

    expect(textos_enviados).to eq(['Obrigado pela visita! O que achou do apartamento?'])
    expect(retornos.sole).to have_attributes(
      assignee_id: corretor.id, title: 'Como foi a visita com a Ana? Escreva uma frase no campo ‘Como foi a visita’ do card'
    )
    expect(historico.last).to eq(['espera', 'ok', nil])
  end

  it 'passos 3 a 5: a Ana responde que gostou; o card vai para Proposta, os documentos vão por e-mail e o retorno de 2 dias',
     :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'gostou', 'motivo' => 'amou a vista e o preço' }
    visita_feita_as('2026-11-10 15:00')

    ana_responde_as('2026-11-10 17:00', 'Amei! A vista é linda e o preço está bom.')

    expect(card.reload.stage_id).to eq(proposta.id)
    email = Conversation.where(inbox: caixa_de_email).sole
    expect(email.contact).to eq(ana)
    expect(email.additional_attributes['mail_subject']).to eq('Documentos para a proposta')
    expect(retornos.last).to have_attributes(assignee_id: corretor.id, title: 'Acompanhar a proposta da Ana',
                                             due_at: fuso.parse('2026-11-12 17:00'))
  end

  # "Pelo que os dois disseram": a frase do corretor no card também decide, sem a Ana responder. G48: o campo do card
  # preenchido acorda o "esperar até" na hora (Crm::CardAvisaAutomacao), sem esperar o prazo de 24 horas.
  it 'passos 3 e 4: o corretor escreve no campo do card; a decisão vem na hora, lendo o que ele escreveu', :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'gostou', 'motivo' => 'o corretor disse que ela gostou' }
    visita_feita_as('2026-11-10 15:00')

    as('2026-11-10 16:00') do
      card.update!(custom_attributes: card.custom_attributes.merge('como_foi_a_visita' => 'Gostou muito, quer fazer proposta.'))
      drenar
    end

    lido = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_decidir' }.sole['input'].to_json
    expect(lido).to include('Gostou muito, quer fazer proposta.')
    expect(card.reload.stage_id).to eq(proposta.id)
  end

  it 'passo 6: quer outra opção; o que faltou vai para o card e o retorno para mandar 3 opções', :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'outra_opcao', 'motivo' => 'quer 2 vagas' }
    roteiro['automacao_extrair'] = { 'vaga' => 2, 'andar' => 'alto', 'preco' => 900_000 }
    visita_feita_as('2026-11-10 15:00')

    ana_responde_as('2026-11-10 17:00', 'Gostei, mas preciso de 2 vagas, andar alto, até 900 mil.')

    expect(card.reload.custom_attributes).to include('vaga' => 2, 'andar' => 'alto', 'preco' => 900_000)
    expect(retornos.last).to have_attributes(assignee_id: corretor.id, title: 'Mandar 3 opções para a Ana')
    expect(card.stage_id).to eq(visita_feita.id)
  end

  it 'passo 7: não gostou; etiqueta "procurando", o card fechado e a Ana no público da campanha de lançamentos',
     :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'nao_gostou', 'motivo' => 'achou escuro' }
    visita_feita_as('2026-11-10 15:00')

    ana_responde_as('2026-11-10 17:00', 'Não gostei, achei muito escuro.')

    expect(card.reload).to have_attributes(status: 'lost', lost_reason: 'Não gostou do imóvel')
    expect(conversa.reload.label_list).to include('procurando', 'lancamentos')
  end

  it 'passo 8: nada em 24 horas; o Márcio é avisado e nada mais acontece', :aggregate_failures do
    visita_feita_as('2026-11-10 15:00')

    varredura_as('2026-11-11 15:05')

    expect(mencoes_para(marcio).count).to eq(1)
    expect(ia_recebeu).to be_empty
    expect(card.reload).to have_attributes(stage_id: visita_feita.id, status: 'open')
  end
end
