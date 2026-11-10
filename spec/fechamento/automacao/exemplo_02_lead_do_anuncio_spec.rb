require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 2 dos termos de aceite: "Lead do anúncio atendido em 5 minutos" (#2856).
#
# > "O povo preenche o formulário do anúncio e quando eu ligo já esfriou. Quero que alguém fale com ele na hora e, se ele
# > quiser ver o apartamento, já marque a visita." — Márcio, dono da imobiliária
#
# Começa quando: card criado pelo formulário de um anúncio.
#   1. Põe no contato a etiqueta com o nome do anúncio.
#   2. Manda pelo modelo aprovado do WhatsApp: "Oi, Ana! Vi que você se interessou pelo apartamento do Jardim. Posso te
#      ajudar?".
#   3. Espera a resposta, por até 2 horas.
#   4. Sem resposta: cria um retorno para o corretor responsável por esse anúncio ligar ainda hoje.
#   5. Respondeu: passa a conversa para a Sofia, a agente de IA da imobiliária.
#   6. A cada resposta da Ana, a IA decide: "quer visitar", "quer outro imóvel", "só curiosidade" ou "ainda conversando".
#   7. Quer visitar: manda o link da agenda do corretor do anúncio.
#   8. Visita marcada: move o card para "Visita marcada" e avisa o corretor com um resumo do que a Ana perguntou à Sofia.
#   9. Quer outro imóvel: a IA extrai bairro, quartos e valor, grava no card e cria retorno para o corretor mandar opções.
#  10. Só curiosidade: põe a etiqueta "frio" e coloca a Ana na campanha mensal de lançamentos.
#
# Montado como o Márcio montaria, pela API da tela, numa automação só. O lead entra pelo importador de verdade do
# formulário da Meta (G29), e o card nasce com o corretor que a Atribuição do funil dá (G30). A Ana não tem conversa: a
# mensagem abre a dela pela caixa do WhatsApp oficial escolhida no gatilho (G33), e a resposta dela entra pelo webhook
# da Cloud. A IA é o dublê; o que sai para a Ana para no receptor do WhatsApp oficial (F9.7).
#
# - Começa quando: o filtro `card.origem` = formulário de anúncio (G29); a etiqueta do passo 1 é `card.anuncio`.
# - "O corretor responsável por esse anúncio" (passos 4, 7, 8 e 9) é o dono do card do lead (G30): o retorno vai para o
#   responsável do card, o link é `card.link_da_agenda` (a página dele, G12) e o aviso vai ao `responsavel_do_card`.
# - Passo 4: o retorno "para hoje", no fim do dia, no fuso da conta (G57); depois dele a execução para.
# - Passo 6: o decidir volta a esperar enquanto a IA diz "ainda conversando" (G31; 24 horas de silêncio encerram, decisão
#   1 do Rodrigo, 09/11). A Sofia (G15) responde pelo robô dela, que aqui é a mensagem de saída do espelho da agente.
# - Passo 8: "Visita marcada" é o "esperar até" `card.tem_reuniao_marcada` (G32), sem prazo; a Ana marca pela página do
#   corretor, pelo serviço real (Crm::BookingV2::Booker), que põe a reunião no card do lead.
# - Passo 9, "grava no card": o extrair grava direto nos campos do card do lead (G70, decisão 20 do Rodrigo, "IA só anota
#   campos"), como quem ligou a automação. Os campos só existem no card: não há cópia pela conversa.
# - Passo 10, "coloca na campanha mensal de lançamentos": pôr alguém numa campanha é pôr a etiqueta do público dela
#   (G14), aqui `lancamentos`; a campanha do mês, montada na tela de Campanhas com esse público, chega à Ana.
RSpec.describe 'Fechamento #2414 · exemplo 2: lead do anúncio atendido em 5 minutos', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper
  include FechamentoAutomacao::Canais

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true',
                      AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { exemplo.run }
  end

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:marcio) { create(:user, account: account, role: :administrator, name: 'Márcio Imóveis') }
  # A outra corretora da caixa nasce antes do Paulo: sem a Atribuição do funil, a fila daria o lead a ela (menor id). O
  # Paulo é o corretor deste anúncio pela pessoa fixa da Atribuição, não por ser o único da caixa.
  let!(:outra_corretora) { create(:user, account: account, role: :agent, name: 'Bia Corretora') }
  let(:corretor) { create(:user, account: account, role: :agent, name: 'Paulo Corretor') }
  let(:funil_e_entrada) { create_crm_pipeline(account: account, user: marcio, name: 'Lançamentos') }
  let(:visita_marcada) { create_crm_stage(account: account, pipeline: funil, name: 'Visita marcada', position: 1) }
  let(:agenda_do_corretor) do
    create_booking_profile(account: account, host: corretor, pipeline: funil, stage: funil_e_entrada.last, title: 'Visita ao apartamento')
  end
  let(:sofia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Sofia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Você é a Sofia, da imobiliária. Tire dúvidas de preço, vaga e condomínio.')
  end
  let(:escolhas) { [] }
  let(:automacao) { montar_automacao(marcio, account, nome: 'Lead do anúncio atendido em 5 minutos', receita: receita) }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def funil = funil_e_entrada.first
  def caixa = canal.inbox
  def nome = { '$valor' => 'contato.nome' }
  def card_id = { '$valor' => 'card.id' }
  def para_o_corretor = { quem: 'responsavel' }
  def caminho(nome_do_caminho, chave, descricao, passos = []) = { nome: nome_do_caminho, chave: chave, descricao: descricao, passos: passos }

  def etiquetas_no_contato(id, descricao, por)
    { id: id, tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: descricao,
      caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: por } }
  end

  def receita
    { gatilho: { tipo: 'card.criado', funil_id: funil.id, conversa_nova: { caixa_id: caixa.id },
                 filtros: [{ campo: { '$valor' => 'card.origem' }, op: 'igual', valor: 'formulario_de_anuncio' }] },
      passos: [
        etiquetas_no_contato('anuncio', 'Pôr a etiqueta com o nome do anúncio', [{ '$valor' => 'card.anuncio' }]),
        { id: 'oi', tipo: 'mensagem', texto: ['Oi, ', nome, '! Vi que você se interessou pelo apartamento do Jardim. Posso te ajudar?'],
          modelo: { nome: 'lead_jardim', idioma: 'pt_BR', variaveis: [[nome]] } },
        { id: 'resposta', tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true },
          prazo: { valor: 2, unidade: 'horas' }, se_vencer: [
            { id: 'ligar_hoje', tipo: 'retorno', titulo: ['Ligar para ', nome, ', lead do anúncio'], quando: { dia: 'hoje' },
              para: para_o_corretor },
            { id: 'fim', tipo: 'parar' }
          ] },
        { id: 'sofia', tipo: 'ia_assumir', agente_id: sofia.id },
        decidir
      ] }
  end

  # Passos 6 a 10.
  def decidir
    { id: 'o_que_quer', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'O que a Ana quer, pela conversa com a Sofia?',
      de_novo: { caminhos: ['ainda_conversando'], prazo: { valor: 24, unidade: 'horas' } },
      caminhos: [
        caminho('Quer visitar', 'quer_visitar', 'quer marcar uma visita ao apartamento', quer_visitar),
        caminho('Quer outro imóvel', 'quer_outro_imovel', 'quer ver outro imóvel, em outro bairro, tamanho ou preço', quer_outro_imovel),
        caminho('Só curiosidade', 'so_curiosidade', 'só está curiosa, sem intenção de comprar agora',
                [etiquetas_no_contato('frio', 'Pôr frio e a campanha de lançamentos', %w[frio lancamentos])]),
        caminho('Ainda conversando', 'ainda_conversando', 'ainda está tirando dúvidas com a Sofia')
      ],
      nenhum: [] }
  end

  # Passos 7 e 8.
  def quer_visitar
    [{ id: 'link', tipo: 'mensagem', texto: ['Que ótimo! Escolha o melhor horário para a visita: ', { '$valor' => 'card.link_da_agenda' }] },
     { id: 'marcou', tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'card.tem_reuniao_marcada' }, op: 'igual', valor: true },
       prazo: 'sem_prazo' },
     { id: 'para_visita_marcada', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Levar para Visita marcada',
       caminho: { id: card_id }, corpo: { stage_id: visita_marcada.id } },
     { id: 'resumo', tipo: 'resumir', le: %w[mensagens_com_respostas], linhas: 4,
       instrucao: 'Diga o que a Ana perguntou à Sofia e quanto ela pode pagar.', destino: { avisar: { responsavel_do_card: true } } }]
  end

  # Passo 9.
  def quer_outro_imovel
    [{ id: 'o_que_procura', tipo: 'extrair', le: %w[mensagens_recentes], campos: %w[bairro quartos valor].map do |chave|
      { chave: chave, descricao: "o #{chave} do imóvel que a Ana procura", destino: "card.atributos.#{chave}" }
    end },
     { id: 'mandar_opcoes', tipo: 'retorno', titulo: ['Mandar opções de imóveis para ', nome], quando: { dia: 'hoje' },
       para: para_o_corretor }]
  end

  def modelo_aprovado
    { 'name' => 'lead_jardim', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi, {{1}}! Vi que você se interessou pelo apartamento do Jardim. Posso te ajudar?' }] }
  end

  # Os campos do imóvel procurado existem só no card (G70): o extrair grava neles, sem passar pela conversa.
  def criar_campos
    %w[bairro quartos valor].each do |chave|
      create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                           attribute_model: 'card_attribute', attribute_display_type: 'text')
    end
  end

  # O dublê da IA responde pelo que leu: o decidir segue a fila do exemplo; o extrair e o resumo saem do texto da Ana que
  # o pedido levou (nada inventado aqui chega ao card ou ao aviso).
  def roteiro_da_ia
    fila = escolhas
    lambda do |schema, corpo|
      case schema
      when 'automacao_decidir' then { 'caminho' => fila.shift, 'motivo' => 'Pela conversa.' }
      when 'automacao_extrair' then o_que_a_ana_procura(mensagens_lidas(corpo).last.to_s.split('] ', 2).last)
      else { 'resumo' => "Perguntas da Ana: #{perguntas_da_ana(mensagens_lidas(corpo)).join(' ')}" }
      end
    end
  end

  # "Esse não. Queria 3 quartos em Moema, até 900 mil." → bairro, quartos e valor, palavra a palavra; sem o dado, nulo.
  def o_que_a_ana_procura(texto)
    palavras = texto.to_s.delete('.,').split
    depois = ->(marca, passo = 1) { (indice = palavras.index(marca)) && palavras[indice + passo] }
    { 'bairro' => depois.call('em'), 'quartos' => depois.call('quartos', -1),
      'valor' => (indice = palavras.index('até')) && palavras[(indice + 1)..].join(' ') }
  end

  def perguntas_da_ana(mensagens) = mensagens.filter_map { |mensagem| mensagem.delete_prefix('Customer: ') if mensagem.start_with?('Customer: ') }

  before do
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    [outra_corretora, corretor].each { |pessoa| create(:inbox_member, user: pessoa, inbox: caixa) }
    account.crm_pipeline_inboxes.create!(pipeline: funil, inbox: caixa)
    funil.update!(metadata: { 'ai' => { 'handoff' => { 'enabled' => true, 'pool_type' => 'user', 'pool_id' => corretor.id } } })
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    canal.update!(message_templates: [modelo_aprovado])
    %w[frio lancamentos].each { |titulo| create(:label, account: account, title: titulo) }
    criar_campos
    visita_marcada
    agenda_do_corretor
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    Autonomia::Agents::Areas.vincular!(agent: sofia, inbox: caixa)
    ia_responde(account, roteiro_da_ia)
    receptor_whatsapp_cloud
    as('2026-11-10 09:00') { ligar_automacao(marcio, account, automacao) }
    clear_enqueued_jobs
  end

  after { Current.reset }

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

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  # O lead como a Graph da Meta o entrega ao webhook do formulário.
  def lead_chega
    lead = { 'id' => 'L0002', 'created_time' => '2026-11-10T13:00:00+0000', 'form_id' => '9002', 'ad_name' => 'Apartamento Jardim',
             'field_data' => [{ 'name' => 'full_name', 'values' => ['Ana'] }, { 'name' => 'phone_number', 'values' => ['+5511987650002'] }] }
    as('2026-11-10 10:00') do
      Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: funil, stage: funil_e_entrada.last, form_name: 'Quero visitar')
                                       .import(lead)
      drenar
    end
  end

  def ana_escreve(hora, texto)
    as(hora) do
      cliente_escreve_pela_cloud(canal, remetente: '5511987650002', nome: 'Ana', texto: texto)
      drenar
    end
  end

  def varrer(hora)
    as(hora) do
      Autonomia::Automacao::VarreduraJob.perform_now
      drenar
    end
  end

  def card = account.crm_cards.sole
  def conversa = card.contact.conversations.sole
  def execucao = Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).sole
  def passos_feitos = historico_de(automacao).map(&:first)
  def whatsapp = chamadas_para('graph.facebook.com').map(&:corpo)
  def robo_da_sofia = Autonomia::Agents::Areas.vincular!(agent: sofia, inbox: caixa).agent_bot

  it 'começa no card do formulário e faz os passos 1 e 2: a etiqueta do anúncio e o modelo aprovado com o nome da Ana',
     :aggregate_failures do
    lead_chega

    expect(Crm::Entrega::QuemCuida.na_caixa(inbox: caixa, pipeline_id: funil.id)).to include(outra_corretora, corretor)
    expect(card).to have_attributes(source: Crm::MetaAds::LeadForms::Importer::SOURCE, owner: corretor)
    expect(card.contact.label_list).to eq(['apartamento_jardim'])
    modelo = whatsapp.sole
    expect(modelo).to include('to' => '5511987650002', 'type' => 'template')
    expect(modelo.dig('template', 'name')).to eq('lead_jardim')
    expect(modelo.to_json).to include('Ana')
    expect(passos_feitos).to eq(%w[anuncio oi resposta])
    expect(execucao).to have_attributes(estado: 'esperando', cursor: 'resposta')
  end

  it 'passos 3 e 4: sem resposta em 2 horas, o corretor do anúncio ganha o retorno de ligar ainda hoje', :aggregate_failures do
    lead_chega
    varrer('2026-11-10 11:50')
    expect(execucao.estado).to eq('esperando')

    varrer('2026-11-10 12:01')

    expect(execucao.reload.estado).to eq('concluida')
    expect(Crm::FollowUp.sole).to have_attributes(title: 'Ligar para Ana, lead do anúncio', card_id: card.id,
                                                  due_at: fuso.parse('2026-11-10').end_of_day.change(usec: 0))
    expect(Crm::FollowUp.sole.recipient_mode).to eq('card_owner')
    expect(passos_feitos).not_to include('sofia', 'o_que_quer')
  end

  it 'passos 5 e 6: a Ana responde, a Sofia assume, e "ainda conversando" espera a próxima resposta', :aggregate_failures do
    lead_chega
    escolhas << 'ainda_conversando'

    ana_escreve('2026-11-10 10:20', 'Qual o valor do condomínio?')

    expect(conversa.reload.ai_assignee).to eq(robo_da_sofia)
    expect(passos_feitos).to eq(%w[anuncio oi resposta resposta sofia o_que_quer])
    expect(execucao).to have_attributes(estado: 'esperando', cursor: 'o_que_quer')
    expect(ia_recebeu.last.to_json).to include('Qual o valor do condomínio?')
  end

  it 'passos 7 e 8: quer visitar recebe o link do corretor; marcada, o card vai para "Visita marcada" e o corretor tem o resumo',
     :aggregate_failures do
    lead_chega
    escolhas.push('ainda_conversando', 'quer_visitar')
    ana_escreve('2026-11-10 10:20', 'Qual o valor do condomínio?')
    as('2026-11-10 10:21') do
      create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, sender: robo_da_sofia,
                       content: 'O condomínio é R$ 600,00, com uma vaga.')
      drenar
    end
    ana_escreve('2026-11-10 10:30', 'Quero visitar amanhã de manhã')

    link = whatsapp.last.dig('text', 'body')
    expect(link).to eq("Que ótimo! Escolha o melhor horário para a visita: #{Crm::BookingV2::ShortLink.url_for(agenda_do_corretor)}")
    expect(execucao.reload).to have_attributes(estado: 'esperando', cursor: 'marcou')

    as('2026-11-10 10:40') do
      Crm::BookingV2::Booker.new(profile: agenda_do_corretor, name: 'Ana', phone: '(11) 98765-0002',
                                 starts_at: fuso.parse('2026-11-11 10:00').iso8601, source: 'public_link').perform
      drenar
    end

    expect(card.reload.stage).to eq(visita_marcada)
    expect(execucao.reload.estado).to eq('concluida')
    aviso = conversa.messages.where(private: true).find_by('content LIKE ?', "%mention://user/#{corretor.id}/%")
    # O resumo é o que a Ana escreveu à Sofia, lido do pedido à IA, que levou também a resposta da Sofia.
    expect(aviso.content).to include('Perguntas da Ana: Qual o valor do condomínio? Quero visitar amanhã de manhã')
    pedido = ia_recebeu.find { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_resumir' }
    expect(pedido.to_json).to include('O condomínio é R$ 600,00')
    # F4.5: o aviso chega no sino do corretor do anúncio, com o link da conversa; a outra corretora não é avisada.
    sino = Notification.where(user: corretor, notification_type: 'conversation_mention').sole
    expect(sino).to have_attributes(primary_actor: conversa)
    expect(Notification.where(user: outra_corretora, notification_type: 'conversation_mention')).to be_empty
  end

  it 'passo 9: quer outro imóvel grava bairro, quartos e valor no card e o corretor ganha o retorno de mandar opções',
     :aggregate_failures do
    lead_chega
    escolhas << 'quer_outro_imovel'

    ana_escreve('2026-11-10 10:20', 'Esse não. Queria 3 quartos em Moema, até 900 mil.')

    # O que o card guarda é o que o dublê tirou do texto que o pedido levou à IA, não um valor do teste.
    pedido = ia_recebeu.find { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_extrair' }
    expect(mensagens_lidas(pedido).last).to end_with('Esse não. Queria 3 quartos em Moema, até 900 mil.')
    expect(card.reload.custom_attributes).to include('bairro' => 'Moema', 'quartos' => '3', 'valor' => '900 mil')
    # Direto no card (G70): a conversa não guarda os campos e nenhuma ação copia de lá; o registro do extrair diz o que gravou.
    expect(conversa.reload.custom_attributes.keys & %w[bairro quartos valor]).to be_empty
    expect(passos_feitos).to eq(%w[anuncio oi resposta resposta sofia o_que_quer o_que_procura mandar_opcoes])
    gravou = Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'o_que_procura').sole
    expect(gravou).to have_attributes(resultado: 'ok')
    expect(gravou.dados['campos']).to include('gravados' => %w[bairro quartos valor], 'ausentes' => [])
    expect(Crm::FollowUp.sole).to have_attributes(title: 'Mandar opções de imóveis para Ana', card_id: card.id, recipient_mode: 'card_owner')
    expect(execucao.reload.estado).to eq('concluida')
  end

  it 'passo 10: só curiosidade põe "frio" e a Ana entra no público da campanha mensal de lançamentos', :aggregate_failures do
    lead_chega
    escolhas << 'so_curiosidade'

    ana_escreve('2026-11-10 10:20', 'Só queria saber o preço mesmo, obrigada.')

    expect(card.contact.reload.label_list).to contain_exactly('apartamento_jardim', 'frio', 'lancamentos')
    expect(Crm::FollowUp.count).to eq(0)
    expect(execucao.reload.estado).to eq('concluida')

    # A campanha mensal de lançamentos, como o Márcio monta na tela de Campanhas, com o público "lancamentos": a Ana recebe.
    campanha_de_lancamentos
    lancamentos = whatsapp.select { |corpo| corpo.dig('template', 'name') == 'lancamentos' }
    expect(lancamentos.map { |corpo| corpo['to'].delete('+') }).to eq(['5511987650002'])
  end

  def campanha_de_lancamentos
    modelo = { 'name' => 'lancamentos', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
               'components' => [{ 'type' => 'BODY', 'text' => 'Os lançamentos de {{1}} chegaram. Quer conhecer?' }] }
    account.enable_features!('whatsapp_campaign')
    canal.update!(message_templates: [modelo_aprovado, modelo])
    stub_request(:get, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') })
      .to_return(status: 200, body: { data: [modelo.merge('id' => '9002')] }.to_json, headers: { 'Content-Type' => 'application/json' })
    as('2026-11-10 11:00') do
      campanha = account.campaigns.create!(
        title: 'Lançamentos do mês', inbox: caixa, sender: marcio, scheduled_at: Time.current, message: 'Os lançamentos de novembro chegaram.',
        template_params: { 'name' => 'lancamentos', 'language' => 'pt_BR', 'category' => 'MARKETING',
                           'processed_params' => { 'body' => { '1' => 'novembro' } } },
        audience: [{ 'type' => 'Label', 'id' => account.labels.find_by!(title: 'lancamentos').id }]
      )
      Campaigns::TriggerOneoffCampaignJob.perform_now(campanha)
    end
  end
end
