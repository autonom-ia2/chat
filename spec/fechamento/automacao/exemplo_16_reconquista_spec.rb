require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 16 dos termos de aceite: "Reconquistar quem foi para o concorrente".
#
# > "Quem fechou com outro no ano passado tá vencendo agora. Quero chamar de volta com uma oferta melhor."
# > — Juliana, corretora
#
# Começa quando: todo dia 1º do mês, para cada card perdido há 11 meses com o motivo "fechou com outro" ou "achou caro".
#   1. Põe a etiqueta "reconquista" no contato.
#   2. Monta a campanha com o modelo aprovado "Seu seguro está vencendo" para todos com essa etiqueta.
#   3. Cada resposta: a IA decide "quer cotação", "ficou satisfeito lá" ou "não quer contato".
#   4. Quer cotação: a IA escreve uma resposta que fala do motivo da perda gravado no card antigo.
#   5. Cria um card novo no Comercial, com a origem "reconquista", e passa para o corretor que atendeu da outra vez.
#   6. Ficou satisfeito: agradece e grava um retorno para daqui a 11 meses.
#   7. Não quer contato: registra e nunca mais manda.
#   8. Card novo sem resposta do corretor em 4 horas: manda ao cliente o link da agenda.
# Resultado: todo mês a Juliana tem uma lista nova de clientes perdidos que pediram cotação, cada um com o corretor que
# já conhece a história.
#
# Montado como a Juliana montaria, pela API da tela, em duas automações. A do dia 1º (card.recorrente, G7) roda em cada
# card perdido da seleção: põe a etiqueta e entra na campanha da vez (G55), que sai uma vez só, para todos com a
# etiqueta, pelo disparo de sempre (Campaigns::TriggerOneoffCampaignJob, o serviço de envio do EE), e para no receptor da
# Graph. A da resposta é a mensagem do cliente com o filtro "respondeu à campanha 'Seu seguro está vencendo'" (G38),
# que chega pelo webhook real da Cloud e lê o destinatário que o envio gravou. A IA é o dublê (nenhuma chamada paga).
# Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
#
# - Começa quando: a seleção do recorrente é o funil Comercial, perdido entre 330 e 360 dias atrás (11 meses, na
#   contagem de 30 dias do exemplo 9); o motivo é o "Só se" do gatilho, `card.motivo_da_perda` igual a um dos dois.
# - Passo 3: "cada resposta" é cada mensagem recebida que responde a essa campanha (G38), uma execução por conversa.
# - Passos 4, 5 e 8 rodam no card antigo do mesmo contato, pelo "em outro registro" (G18, cards_do_contato, perdido, o
#   mais recente), na conversa em que o cliente escreveu: a IA lê o card antigo (`le: card`) e escreve. O card novo nasce
#   no contato (G4 com `contato`, G49), e a ação no card que esta execução criou grava a origem "reconquista" e o dono
#   (o `card.responsavel_id` do card antigo). "Passa para o corretor" também passa a conversa a ele, e a espera do
#   passo 8 é a dele (`conversa.responsavel_respondeu`, G40); vencida, o link é o da página dele
#   (`conversa.link_da_agenda`, G12).
# - Passo 6, "daqui a 11 meses": o retorno conta em minutos, horas ou dias; são 330 dias, como os 180 dias dos 6 meses do
#   exemplo 9. Vai para a Juliana.
# - Passo 7: "registra e nunca mais manda" é o "não recebe" do contato (campanha `nao_receber`), que o envio de toda
#   campanha relê; a campanha do mês seguinte o pula.
RSpec.describe 'Fechamento #2414 · exemplo 16: reconquistar quem foi para o concorrente', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper
  include FechamentoAutomacao::Canais

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:juliana) { create(:user, account: account, role: :administrator, name: 'Juliana Corretora') }
  let(:rafael) { create(:user, account: account, role: :agent, name: 'Rafael Corretor') }
  let(:funil) { account.crm_pipelines.create!(name: 'Comercial', created_by: juliana, status: :active) }
  let(:proposta) { account.crm_pipeline_stages.create!(pipeline: funil, name: 'Proposta', position: 0) }
  let(:novo) { account.crm_pipeline_stages.create!(pipeline: funil, name: 'Novo', position: 1) }
  let(:agenda_do_rafael) { create_booking_profile(account: account, host: rafael, title: 'Cotação do seguro') }
  let!(:reconquista) { create(:label, account: account, title: 'reconquista') }
  let(:escolhas) { [] }
  # Os perdidos da Juliana. Só Ana, Bruno e Eva entram: o Caio perdeu por outro motivo, e o Davi há 20 dias.
  let!(:perdidos) do
    { ana: perdido('Ana', '5511900001601', 335, 'achou caro'), bruno: perdido('Bruno', '5511900001602', 340, 'fechou com outro'),
      eva: perdido('Eva', '5511900001605', 345, 'fechou com outro'), caio: perdido('Caio', '5511900001603', 338, 'desistiu do carro'),
      davi: perdido('Davi', '5511900001604', 20, 'achou caro') }
  end
  let(:automacoes) do
    as(fuso.local(2026, 10, 15, 10)) do
      [montar_automacao(juliana, account, nome: 'Reconquista: dia 1º', receita: receita_do_dia_primeiro),
       montar_automacao(juliana, account, nome: 'Reconquista: resposta', receita: receita_da_resposta)]
        .each { |automacao| ligar_automacao(juliana, account, automacao) }
    end
  end

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def account = canal.account
  def caixa = canal.inbox
  def dia_primeiro = fuso.local(2026, 11, 1, 9)
  def texto_da_ia = 'Ana, da outra vez o preço pesou; este ano consigo melhor. Posso cotar?'
  def do_dia_primeiro = automacoes.first
  def da_resposta = automacoes.last
  %i[ana bruno eva caio davi].each { |nome| define_method(nome) { perdidos.fetch(nome) } }

  def valor(caminho) = { '$valor' => caminho }

  def receita_do_dia_primeiro
    motivos = ['fechou com outro', 'achou caro'].map { |motivo| { campo: valor('card.motivo_da_perda'), op: 'igual', valor: motivo } }
    { gatilho: { tipo: 'card.recorrente', frequencia: 'mensal', dia_do_mes: 1, hora: 9, filtros: [{ alguma: motivos }],
                 selecao: { funil_id: funil.id, situacao: 'perdido', fechado_entre_dias: { de: 330, ate: 360 } } },
      passos: [
        { id: 'etiqueta', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Pôr a etiqueta reconquista',
          caminho: { contact_id: valor('contato.id') }, corpo: { por: ['reconquista'] } },
        { id: 'campanha', tipo: 'campanha', faz: 'disparar', titulo: 'Seu seguro está vencendo', caixa_id: caixa.id,
          modelo: { nome: 'seguro_vencendo', idioma: 'pt_BR', variaveis: [['Este ano consigo um preço melhor.']] },
          etiquetas: [reconquista.id] }
      ] }
  end

  def receita_da_resposta
    { gatilho: { tipo: 'mensagem.criada',
                 filtros: [{ campo: valor('mensagem.tipo'), op: 'igual', valor: 'recebida' },
                           { campo: valor('mensagem.campanha'), op: 'igual', valor: 'Seu seguro está vencendo' }] },
      passos: [{ id: 'resposta', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'O que o cliente respondeu à campanha?',
                 caminhos: [caminho('Quer cotação', 'quer_cotacao', 'quer uma cotação nova do seguro', [no_card_antigo]),
                            caminho('Ficou satisfeito lá', 'satisfeito', 'está satisfeito com a seguradora de agora', satisfeito),
                            caminho('Não quer contato', 'nao_quer_contato', 'pede para não ser mais procurado', nao_quer_contato)],
                 nenhum: [] }] }
  end

  def caminho(nome, chave, descricao, passos) = { nome: nome, chave: chave, descricao: descricao, passos: passos }

  # Passos 4, 5 e 8, no card perdido mais recente do mesmo contato.
  def no_card_antigo
    { id: 'card_antigo', tipo: 'em_outro_registro', registro: { de: 'cards_do_contato', situacao: ['lost'], mais_recente: true },
      passos: [
        { id: 'oferta', tipo: 'escrever', le: %w[mensagens_recentes card], destino: 'mensagem',
          instrucao: 'Responda falando do motivo da perda gravado no card antigo e diga que este ano consegue melhor.' },
        { id: 'card_novo', tipo: 'card', etapa_id: novo.id, contato: valor('contato.id') },
        { id: 'origem_e_dono', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Origem reconquista, com o corretor de antes',
          caminho: { id: valor('criado.card_novo') }, corpo: { card: { source: 'reconquista', owner_id: valor('card.responsavel_id') } } },
        { id: 'conversa_ao_corretor', tipo: 'acao', acao: 'POST conversations/:conversation_id/assignments',
          descricao: 'Passar a conversa para o corretor de antes', caminho: { conversation_id: valor('conversa.id') },
          corpo: { assignee_id: valor('card.responsavel_id') } },
        { id: 'corretor_responde', tipo: 'esperar_ate', condicao: { campo: valor('conversa.responsavel_respondeu'), op: 'igual', valor: true },
          prazo: { valor: 4, unidade: 'horas' },
          se_vencer: [{ id: 'link_da_agenda', tipo: 'mensagem',
                        texto: ['Para não esperar, escolha um horário para a sua cotação: ', valor('conversa.link_da_agenda')] }] }
      ] }
  end

  # Passo 6.
  def satisfeito
    [{ id: 'agradece', tipo: 'mensagem', texto: ['Que bom, ', valor('contato.nome'), '! Obrigada pela atenção.'] },
     { id: 'daqui_a_11_meses', tipo: 'retorno', titulo: ['Reconquista: falar de novo com ', valor('contato.nome')],
       daqui: { valor: 330, unidade: 'dias' }, para: { quem: 'pessoas', pessoas: [juliana.id] } }]
  end

  # Passo 7.
  def nao_quer_contato = [{ id: 'nunca_mais', tipo: 'campanha', faz: 'nao_receber' }]

  def modelo_aprovado
    { 'name' => 'seguro_vencendo', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Seu seguro está vencendo. {{1}}' }] }
  end

  def roteiro_da_ia
    fila = escolhas
    escrito = texto_da_ia
    roteiro = Object.new
    roteiro.define_singleton_method(:fetch) do |schema|
      schema == 'automacao_escrever' ? { 'texto' => escrito } : { 'caminho' => fila.shift, 'motivo' => 'Pela resposta.' }
    end
    roteiro
  end

  def perdido(nome, telefone, dias, motivo, dono: rafael)
    contato = create(:contact, account: account, name: nome, phone_number: "+#{telefone}")
    account.crm_cards.create!(pipeline: funil, stage: proposta, title: "Seguro de #{nome}", currency: 'BRL', contact: contato,
                              owner: dono, status: :lost, lost_reason: motivo)
           .tap { |card| card.update_columns(closed_at: dia_primeiro - dias.days) } # rubocop:disable Rails/SkipsModelValidations
    contato
  end

  def as(hora, &) = travel_to(hora, &)

  # A varredura do dia 1º (o TempoJob, o job da automação, os lotes e cada execução) e o disparo da campanha da vez.
  def chega_o_dia(dia)
    as(dia + 5.minutes) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
      rodar_jobs
    end
    as(dia + 6.minutes) { perform_enqueued_jobs(only: Campaigns::TriggerOneoffCampaignJob) }
  end

  def responde(contato, hora, texto)
    as(hora) { cliente_escreve_pela_cloud(canal, remetente: contato.phone_number.delete('+'), nome: contato.name, texto: texto) }
  end

  def varrer(hora) = as(hora) { Autonomia::Automacao::VarreduraJob.perform_now.then { rodar_jobs } }

  def conversa_de(contato) = contato.conversations.sole
  def textos_para(contato) = conversa_de(contato).messages.outgoing.where(private: false).order(:id).pluck(:content)
  def modelos_enviados = chamadas_para('graph.facebook.com').map(&:corpo).select { |corpo| corpo['type'] == 'template' }
  def execucoes(automacao) = Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).order(:id)

  before do
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'whatsapp_campaign', 'crm_booking_v2')
    create(:inbox_member, user: rafael, inbox: caixa)
    account.crm_pipeline_inboxes.create!(pipeline: funil, inbox: caixa)
    agenda_do_rafael
    canal.update!(message_templates: [modelo_aprovado])
    receptor_whatsapp_cloud
    # A trava do disparo pergunta à Meta o estado do modelo na hora (#1329): a Meta de teste responde aprovado.
    stub_request(:get, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') })
      .to_return(status: 200, body: { data: [modelo_aprovado.merge('id' => '9016')] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    ia_responde(account, roteiro_da_ia)
    automacoes
  end

  after { Current.reset }

  it 'começa quando e passos 1 e 2: só os perdidos há 11 meses pelo motivo certo ganham a etiqueta, e uma campanha sai a todos',
     :aggregate_failures do
    chega_o_dia(dia_primeiro)

    expect([ana, bruno, eva].map { |contato| contato.reload.label_list }).to all(eq(['reconquista']))
    expect([caio, davi].map { |contato| contato.reload.label_list }).to all(be_empty)
    expect(account.campaigns.sole).to have_attributes(title: 'Seu seguro está vencendo', sender: juliana, campaign_status: 'completed',
                                                      audience: [{ 'type' => 'Label', 'id' => reconquista.id }])
    expect(modelos_enviados.pluck('to')).to contain_exactly('+5511900001601', '+5511900001602', '+5511900001605')
    expect(modelos_enviados.map { |corpo| corpo.dig('template', 'name') }.uniq).to eq(['seguro_vencendo'])
    expect(execucoes(do_dia_primeiro).map { |execucao| execucao.alvo.contact }).to contain_exactly(ana, bruno, eva)
  end

  context 'with a campanha já enviada' do
    before { chega_o_dia(dia_primeiro) }

    it 'passo 3: a mensagem que não responde à campanha não abre a decisão', :aggregate_failures do
      responde(davi, dia_primeiro + 1.hour, 'Oi, queria saber do meu sinistro')

      expect(conversa_de(davi)).to be_present
      expect(execucoes(da_resposta)).to be_empty
      expect(ia_recebeu).to be_empty
    end

    it 'passos 3, 4 e 5: quer cotação recebe a resposta do motivo da perda e ganha card novo com o corretor de antes',
       :aggregate_failures do
      escolhas << 'quer_cotacao'

      responde(ana, dia_primeiro + 1.hour, 'Quero sim uma cotação nova')

      expect(ia_recebeu.size).to eq(2)
      decidir, escrever = ia_recebeu
      expect(decidir.to_json).to include('Quero sim uma cotação nova')
      lido = JSON.parse(escrever['input'].sole.fetch('content').sole['text'])
      expect(lido.dig('conversa', 'card')).to include('status' => 'lost', 'lost_reason' => 'achou caro')
      expect(escrever['instructions']).to include('motivo da perda gravado no card antigo')
      expect(textos_para(ana)).to eq([texto_da_ia])
      card_novo = account.crm_cards.where(contact: ana, status: :open).sole
      expect(card_novo).to have_attributes(pipeline: funil, stage: novo, source: 'reconquista', owner: rafael)
      expect(conversa_de(ana).reload.assignee).to eq(rafael)
      filha = execucoes(da_resposta).where('evento LIKE ?', 'em:%').sole
      expect(filha).to have_attributes(alvo: account.crm_cards.find_by!(contact: ana, status: :lost), estado: 'esperando',
                                       cursor: 'corretor_responde')
      feitos = Autonomia::Automacao::Registro.where(execucao: filha).order(:id).pluck(:passo, :resultado)
      expect(feitos).to include(%w[oferta ok], %w[card_novo ok], %w[origem_e_dono ok], %w[conversa_ao_corretor ok])
    end

    it 'passo 8: o corretor responde em 4 horas e o link da agenda não sai', :aggregate_failures do
      escolhas << 'quer_cotacao'
      responde(ana, dia_primeiro + 1.hour, 'Quero sim uma cotação nova')

      as(dia_primeiro + 2.hours) do
        create(:message, account: account, inbox: caixa, conversation: conversa_de(ana), message_type: :outgoing, sender: rafael,
                         content: 'Ana, aqui é o Rafael. Já vou montar a cotação.')
        rodar_jobs
      end
      varrer(dia_primeiro + 5.hours + 5.minutes)

      expect(textos_para(ana)).to eq([texto_da_ia, 'Ana, aqui é o Rafael. Já vou montar a cotação.'])
      expect(execucoes(da_resposta).where('evento LIKE ?', 'em:%').sole.estado).to eq('concluida')
    end

    it 'passo 8: sem resposta do corretor em 4 horas, o cliente recebe o link da agenda dele', :aggregate_failures do
      escolhas << 'quer_cotacao'
      responde(ana, dia_primeiro + 1.hour, 'Quero sim uma cotação nova')

      varrer(dia_primeiro + 4.hours + 55.minutes)
      expect(textos_para(ana)).to eq([texto_da_ia])

      varrer(dia_primeiro + 5.hours + 5.minutes)

      link = "Para não esperar, escolha um horário para a sua cotação: #{Crm::BookingV2::ShortLink.url_for(agenda_do_rafael)}"
      expect(textos_para(ana)).to eq([texto_da_ia, link])
      expect(execucoes(da_resposta).where('evento LIKE ?', 'em:%').sole.estado).to eq('concluida')
    end

    it 'passo 6: ficou satisfeito, recebe o agradecimento e a Juliana tem o retorno para daqui a 11 meses', :aggregate_failures do
      escolhas << 'satisfeito'

      responde(bruno, dia_primeiro + 1.hour, 'Obrigado, mas estou bem atendido onde estou.')

      expect(textos_para(bruno)).to eq(['Que bom, Bruno! Obrigada pela atenção.'])
      expect(Crm::FollowUp.sole).to have_attributes(title: 'Reconquista: falar de novo com Bruno', status: 'pending',
                                                    recipient_mode: 'users', recipient_user_ids: [juliana.id], contact_id: bruno.id,
                                                    due_at: dia_primeiro + 1.hour + 330.days)
      expect(account.crm_cards.where(contact: bruno, status: :open)).to be_empty
    end

    it 'passo 7: não quer contato, fica registrado e a campanha do mês seguinte não vai para ele', :aggregate_failures do
      escolhas << 'nao_quer_contato'

      responde(eva, dia_primeiro + 1.hour, 'Não quero mais contato, por favor.')

      expect(eva.reload).to be_opted_out
      expect(historico_de(da_resposta).last).to eq(['nunca_mais', 'ok', nil])
      expect(textos_para(eva)).to be_empty

      # No mês seguinte um card novo entra na seleção, e a campanha vai a todos com a etiqueta, menos a Eva.
      perdido('Fabio', '5511900001606', 335 - 30, 'fechou com outro')
      chega_o_dia(fuso.local(2026, 12, 1, 9))

      dezembro = account.campaigns.order(:id).last
      expect(dezembro.campaign_recipients.find_by!(contact: eva)).to have_attributes(status: 'skipped')
      expect(modelos_enviados.count { |corpo| corpo['to'] == '+5511900001605' }).to eq(1)
      expect(modelos_enviados.count { |corpo| corpo['to'] == '+5511900001606' }).to eq(1)
    end
  end
end
