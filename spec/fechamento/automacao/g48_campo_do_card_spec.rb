require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G48: o campo do card preenchido acorda o "esperar até" na hora, e não no fim
# do prazo. Provada nos passos 1 a 4 e 8 do exemplo 12 dos termos de aceite ("Visita que aconteceu decide o próximo
# passo"), montados e ligados pela API da tela, como o Márcio montaria:
# 1. manda à Ana "Obrigado pela visita! O que achou do apartamento?";
# 2. cria um retorno para o corretor (o dono do card) pedindo a frase no campo "Como foi a visita";
# 3. espera até a Ana responder ou o campo ser preenchido, por até 24 horas;
# 4. a IA decide pelo que os dois disseram (o dublê no endereço da OpenAI);
# 8. nada em 24 horas: avisa o Márcio.
# O gancho é o único do Crm::Card para a Automação livre (Crm::CardAvisaAutomacao, lote 4, #2682): o corretor grava o
# campo pela mesma API da tela (PATCH do card), e o Despertador reserva a execução sem a varredura do relógio. O exemplo
# inteiro fica no pendentes_spec até a G25 (fechar o card, passo 7; #2654, que traz o spec do exemplo 12 à risca) fechar.
RSpec.describe 'Fechamento #2414 · G48: o campo do card acorda o "esperar até"', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:marcio) { create(:user, account: account, role: :administrator, name: 'Márcio') }
  let(:corretor) { create(:user, account: account, role: :agent, name: 'Rafael Corretor') }
  let(:ana) { create(:contact, account: account, name: 'Ana', phone_number: '+5511900000012') }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: ana, source_id: '5511900000012') }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: ana, contact_inbox: contact_inbox, status: :open) }
  let(:funil) { create_crm_pipeline(account: account, user: marcio, name: 'Imóveis').first }
  let(:visita_marcada) { create_crm_stage(account: account, pipeline: funil, name: 'Visita marcada', position: 1) }
  let(:visita_feita) { create_crm_stage(account: account, pipeline: funil, name: 'Visita feita', position: 2) }
  let(:proposta) { create_crm_stage(account: account, pipeline: funil, name: 'Proposta', position: 3) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: visita_marcada, inbox: canal.inbox, contact: ana, primary_conversation: conversa,
                              title: 'Ana - apartamento Vila Mariana', owner: corretor)
  end
  let(:roteiro) { { 'automacao_decidir' => { 'caminho' => 'gostou', 'motivo' => 'o corretor anotou que ela gostou' } } }

  def nome = { '$valor' => 'contato.nome' }
  def preenchido = { campo: { '$valor' => 'card.atributos.como_foi_a_visita' }, op: 'preenchido' }
  def ana_respondeu = { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true }

  def etiqueta(id, nome_da_etiqueta)
    { id: id, tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: "Pôr a etiqueta #{nome_da_etiqueta}",
      caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { por: [nome_da_etiqueta] } }
  end

  # Os passos 1 a 4 e 8. Do passo 4, cada caminho leva só a primeira ação do termo que não depende de outra lacuna: o
  # resto dos passos 5 a 7 é do spec do exemplo inteiro.
  def receita
    { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: visita_feita.id }, passos: [
      { id: 'obrigado', tipo: 'mensagem', texto: ['Obrigado pela visita! O que achou do apartamento?'] },
      { id: 'pergunta_ao_corretor', tipo: 'retorno', daqui: { valor: 1, unidade: 'horas' },
        titulo: ['Como foi a visita com a ', nome, '? Escreva uma frase no campo ‘Como foi a visita’ do card'] },
      { id: 'espera', tipo: 'esperar_ate', condicao: { alguma: [ana_respondeu, preenchido] }, prazo: { valor: 24, unidade: 'horas' },
        se_vencer: [{ id: 'avisa_marcio', tipo: 'avisar', para: { pessoas: [marcio.id] },
                      texto: ['Ninguém disse como foi a visita com a ', nome, ' em 24 horas.'] },
                    { id: 'fim', tipo: 'parar' }] },
      decidir
    ] }
  end

  def decidir
    { id: 'decide', tipo: 'decidir', le: %w[mensagens_recentes card], pergunta: 'O que a Ana achou da visita?', caminhos: [
      { nome: 'Gostou', chave: 'gostou', descricao: 'gostou do apartamento', passos: [
        { id: 'proposta', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Mover para Proposta',
          caminho: { id: { '$valor' => 'card.id' } }, corpo: { stage_id: proposta.id } }
      ] },
      { nome: 'Quer outra opção', chave: 'outra_opcao', descricao: 'quer ver outra opção', passos: [
        { id: 'tres_opcoes', tipo: 'retorno', titulo: ['Mandar 3 opções para a ', nome], daqui: { valor: 1, unidade: 'horas' } }
      ] },
      { nome: 'Não gostou', chave: 'nao_gostou', descricao: 'não gostou', passos: [etiqueta('procurando', 'procurando')] }
    ], nenhum: [] }
  end

  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob, SendReplyJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  # O pós-reunião da agenda move o card: o mesmo serviço da tela.
  def visita_acontece
    as('2026-11-10 15:00') do
      Crm::Cards::Mover.new(card: card, actor: marcio, target_stage: visita_feita).perform
      drenar
    end
  end

  # O corretor escreve no campo do card pela tela (o PATCH dela).
  def corretor_escreve_no_card(hora, campos)
    as(hora) do
      patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", params: { card: campos },
                                                                   headers: corretor.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok), -> { "o PATCH do card falhou: #{response.body}" }
      drenar
    end
  end

  def varredura_as(hora)
    as(hora) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  def automacao_id = Autonomia::Automacao::Definicao.find_by!(account: account, nome: 'Visita decide o próximo passo').id
  def execucao = Autonomia::Automacao::Execucao.find_by!(automacao_id: automacao_id, alvo: card)
  def historico = Autonomia::Automacao::Registro.where(automacao_id: automacao_id).order(:id).pluck(:passo, :resultado, :motivo)
  def textos_enviados = chamadas_para('graph.facebook.com').filter_map { |chamada| chamada.corpo.dig('text', 'body') }
  def pedido_da_ia = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_decidir' }.sole
  def avisos_ao_marcio = Notification.where(user: marcio, notification_type: 'conversation_mention')

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-10 10:00') do
      account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
      flags_do_piloto(account)
      account.enable_features!('automacao_gatilhos')
      [marcio, corretor].each { |pessoa| create(:inbox_member, user: pessoa, inbox: canal.inbox) }
      create(:custom_attribute_definition, account: account, attribute_key: 'como_foi_a_visita', attribute_display_name: 'Como foi a visita',
                                           attribute_model: 'card_attribute', attribute_display_type: 'text')
      create(:label, account: account, title: 'procurando', description: 'Procurando outro imóvel')
      [visita_feita, proposta]
      card
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: ana,
                       content: 'Combinado, estarei lá às 14h.')
      ligar_automacao(marcio, account, montar_automacao(marcio, account, nome: 'Visita decide o próximo passo', receita: receita))
      clear_enqueued_jobs
    end
    visita_acontece
  end

  after { Current.reset }

  it 'passos 1 a 3: agradece a Ana, cria o retorno do corretor e espera, com o prazo de 24 horas', :aggregate_failures do
    expect(textos_enviados).to eq(['Obrigado pela visita! O que achou do apartamento?'])
    expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, assignee_id: corretor.id,
                                                  title: 'Como foi a visita com a Ana? Escreva uma frase no campo ‘Como foi a visita’ do card')
    expect(execucao).to have_attributes(estado: 'esperando', due_at: fuso.parse('2026-11-11 15:00'))
  end

  it 'o corretor preenche o campo 2 horas depois: a espera acorda na hora, e a IA decide com a frase dele', :aggregate_failures do
    corretor_escreve_no_card('2026-11-10 17:00', custom_attributes: { como_foi_a_visita: 'Gostou muito, quer proposta' })

    expect(execucao.estado).to eq('concluida')
    expect(historico).to include(['espera', 'ok', nil])
    expect(pedido_da_ia['input'].to_json).to include('Gostou muito, quer proposta')
    expect(card.reload.stage_id).to eq(proposta.id)
    expect(avisos_ao_marcio).to be_empty
  end

  it 'o corretor mexe em outra coisa do card: a espera confere, segue esperando e o prazo não muda', :aggregate_failures do
    corretor_escreve_no_card('2026-11-10 17:00', title: 'Ana - apartamento Vila Mariana (2 quartos)')

    expect(execucao).to have_attributes(estado: 'esperando', due_at: fuso.parse('2026-11-11 15:00'))
    expect(ia_recebeu).to be_empty
    expect(card.reload.stage_id).to eq(visita_feita.id)
  end

  it 'a Ana responde antes do corretor: a resposta dela também acorda a espera', :aggregate_failures do
    as('2026-11-10 16:00') do
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: ana,
                       content: 'Adorei a varanda!')
      drenar
    end

    expect(execucao.estado).to eq('concluida')
    expect(pedido_da_ia['input'].to_json).to include('Adorei a varanda!')
    expect(avisos_ao_marcio).to be_empty
  end

  it 'passo 8: nada em 24 horas avisa o Márcio, e a IA não decide', :aggregate_failures do
    varredura_as('2026-11-11 15:01')

    expect(historico).to include(%w[espera pulado prazo_vencido])
    aviso = conversa.messages.where(private: true).find_by('content LIKE ?', "%mention://user/#{marcio.id}/%")
    expect(aviso.content).to include('Ninguém disse como foi a visita com a Ana em 24 horas.')
    expect(avisos_ao_marcio.count).to eq(1)
    expect(ia_recebeu).to be_empty
    expect(card.reload.stage_id).to eq(visita_feita.id)
  end
end
