require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 9 dos termos de aceite: "Prospecção que roda sozinha toda semana".
#
# > "Quero achar empresas novas da minha cidade toda semana, mandar uma apresentação e só falar com quem tiver
# > interesse." — André, sócio do escritório
#
# Montado como o André montaria, pela API da tela, em quatro automações: a da segunda às 8h (conta.recorrente, G7), que
# roda a busca do histórico da Prospecção, espera a conferência de WhatsApp, cria os cards (G21) e dispara a campanha
# (G14); a da resposta da empresa (decidir, link da agenda, retorno da G3 e a recusa da G21); a da reunião marcada e a da
# reunião cancelada (G12). O relógio anda até a segunda e a varredura do motor acorda a espera da conferência.
#
# Só a borda é dublê, na camada HTTP: o Google Places (a busca), a WAHA (a conferência de WhatsApp da Prospecção), a
# Graph do WhatsApp oficial (a campanha e as mensagens) e a OpenAI (decidir e resumir). A resposta da empresa entra
# pelo webhook real da Cloud. A reunião é marcada e cancelada pelos serviços reais do CRM. Desenho e lacunas:
# docs/automacao/F9-fechamento-20-exemplos.md (seção 6.4, as adaptações deste exemplo).
#
# Adaptações ao termo, todas pela regra da plataforma, não por atalho do teste:
# - "Busca salva": a Prospecção guarda as buscas no histórico, sem nome; o passo repete a busca do histórico
#   (`busca_id`), a "empresas abertas este mês" em "Campinas, SP". O "abertas este mês" vai como texto ao Google: a
#   Prospecção não tem filtro de data de abertura.
# - Etiquetas sem espaço (regra da etiqueta na plataforma): "prospecção-novembro", "tem-contador", "frio".
# - "Card com a etiqueta" (passo 3): a etiqueta vai no contato de cada card criado (decisão da G21, #2706). O contato é
#   o público da campanha do passo 4, e o card não tem etiqueta própria.
# - O modelo aprovado "Apresentação do escritório" tem na Meta o nome `apresentacao_do_escritorio`.
# - "Retorno para daqui a 6 meses" (passo 7): o retorno conta em minutos, horas ou dias; são 180 dias.
# - "Cancelou duas vezes" (passo 10): os valores da receita não contam reuniões canceladas. O André põe a etiqueta
#   "cancelou-uma-vez" no primeiro cancelamento e, se o contato já a tem, "frio".
# - O link da agenda (passo 6) é o do responsável da conversa (`conversa.link_da_agenda`): a automação primeiro passa a
#   conversa para o André, como ele faria para "só falar com quem tiver interesse".
# - O resumo da reunião marcada (passo 9) lê o card e as mensagens recentes da empresa (`le: card, mensagens_recentes`).
#
# O mundo: a conta tem o "Outro canal" do CRM ligado (`crm_outro_canal`, ligado em todas as contas em 07/11). É ele que
# liga a conversa da resposta ao card que a prospecção criou, e é nessa conversa que vão o link e o resumo. Sem ele, a
# deduplicação da caixa só reaproveita card da mesma caixa (Crm::Conversations::AutoCreateDeduplicator), o card da
# prospecção nasce sem caixa, e a resposta abriria um segundo card para a mesma empresa.
#
# Limite do termo, para decisão: a campanha de cada segunda vai para todo contato com a etiqueta, então a empresa da
# semana anterior que não recusou recebe a apresentação de novo. O spec confere só o que o termo promete: a empresa nova
# recebe, e a que recusou, nunca.
RSpec.describe 'Fechamento #2414 · exemplo 9: prospecção que roda sozinha toda semana', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true', GOOGLE_PLACES_API_KEY: 'chave-do-google-de-teste',
                      WAHA_API_URL: 'https://waha.prospeccao.test', WAHA_API_KEY: 'chave-da-waha-de-teste') { exemplo.run }
  end

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:andre) { create(:user, account: account, role: :administrator, name: 'André Sócio') }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: andre, name: 'Prospecção') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa_nova) { funil_e_etapa.last }
  let(:etapa_reuniao) { create_crm_stage(account: account, pipeline: funil, name: 'Reunião', position: 1) }
  let(:agenda) do
    create_booking_profile(account: account, host: andre, pipeline: funil, stage: etapa_reuniao, title: 'Conversa de 20 minutos',
                           duration_minutes: 20)
  end
  let(:busca_salva) do
    Autonomia::Prospecting::Search.create!(account: account, user: andre, query: 'empresas abertas este mês', location: 'Campinas, SP',
                                           radius: 5000, provider: 'google_places', requested_limit: 20, status: :completed)
  end
  let(:roteiro) { {} }
  let(:lugares) { [] }

  # As empresas que o Google devolve: nome e telefone. A Ferragens tem fixo, sem WhatsApp.
  def empresas
    { padaria: ['Padaria Nova Campinas', '+55 19 99111-0001'], oficina: ['Oficina Barão Geraldo', '+55 19 99111-0002'],
      studio: ['Studio Cambuí', '+55 19 99111-0003'], ferragens: ['Ferragens Taquaral', '+55 19 3222-0004'],
      mercado: ['Mercado Swift Campinas', '+55 19 99111-0005'] }
  end

  def sem_whatsapp = '+551932220004'
  def waha_da_prospeccao = 'https://waha.prospeccao.test'
  def link_da_agenda = Crm::BookingV2::ShortLink.url_for(agenda)

  def apresentacao
    { 'name' => 'apresentacao_do_escritorio', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá! Somos um escritório de contabilidade em {{1}}. Podemos apresentar o nosso trabalho?' }] }
  end

  def nova_data
    { 'name' => 'nova_data_da_conversa', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'A conversa foi cancelada. Escolha outro horário: {{1}}' }] }
  end

  def etiqueta(nome) = account.labels.find_by!(title: nome)
  def contato_id = { '$valor' => 'contato.id' }

  def no_contato(id, nome)
    { id: id, tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: "Pôr a etiqueta #{nome}",
      caminho: { contact_id: contato_id }, corpo: { por: [nome] } }
  end

  # Passos 1 a 4: toda segunda às 8h.
  def receita_da_segunda
    { gatilho: { tipo: 'conta.recorrente', frequencia: 'semanal', dia_da_semana: 1, hora: 8 }, passos: [
      { id: 'buscar', tipo: 'prospeccao', faz: 'buscar', busca_id: busca_salva.id, quantas: 20, etapa_id: etapa_nova.id,
        etiquetas: [etiqueta('prospecção-novembro').id] },
      { id: 'apresentar', tipo: 'campanha', faz: 'disparar', titulo: 'Apresentação do escritório', caixa_id: canal.inbox.id,
        modelo: { nome: 'apresentacao_do_escritorio', idioma: 'pt_BR', variaveis: [['Campinas']] },
        etiquetas: [etiqueta('prospecção-novembro').id] }
    ] }
  end

  # Passos 5 a 8: cada resposta de uma empresa prospectada.
  def receita_da_resposta
    filtros = [{ campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' },
               { campo: { '$valor' => 'contato.etiquetas' }, op: 'contem', valor: 'prospecção-novembro' }]
    { gatilho: { tipo: 'mensagem.criada', filtros: filtros }, passos: [
      { id: 'resposta', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'O que a empresa respondeu à apresentação do escritório?',
        caminhos: [
          { nome: 'Interesse', chave: 'interesse', descricao: 'quer conversar ou saber mais', passos: interesse },
          { nome: 'Já tem contador', chave: 'tem_contador', descricao: 'já tem contador ou escritório', passos: tem_contador },
          { nome: 'Não quer contato', chave: 'nao_quer', descricao: 'pediu para não ser mais contatada',
            passos: [{ id: 'recusa', tipo: 'prospeccao', faz: 'recusar' }] }
        ], nenhum: [] }
    ] }
  end

  def interesse
    [{ id: 'para_o_andre', tipo: 'acao', acao: 'POST conversations/:conversation_id/assignments', descricao: 'Passar para o André',
       caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { assignee_id: andre.id } },
     { id: 'agenda', tipo: 'mensagem',
       texto: ['Que bom! Escolha um horário para uma conversa de 20 minutos com o André: ', { '$valor' => 'conversa.link_da_agenda' }] }]
  end

  def tem_contador
    [no_contato('tem_contador', 'tem-contador'),
     { id: 'retorno', tipo: 'retorno', titulo: ['Voltar a falar com ', { '$valor' => 'contato.nome' }], daqui: { valor: 180, unidade: 'dias' },
       para: { quem: 'pessoas', pessoas: [andre.id] } }]
  end

  # Passo 9: a reunião marcada.
  def receita_da_reuniao
    { gatilho: { tipo: 'card.reuniao_marcada', funil_id: funil.id }, passos: [
      { id: 'para_reuniao', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Levar para Reunião',
        caminho: { id: { '$valor' => 'card.id' } }, corpo: { stage_id: etapa_reuniao.id } },
      { id: 'resumo', tipo: 'resumir', le: %w[card mensagens_recentes], linhas: 4, destino: { avisar: { pessoas: [andre.id] } } }
    ] }
  end

  # Passo 10: a reunião cancelada. Fora da janela de 24 h, o link vai pelo modelo aprovado (G1).
  def receita_do_cancelamento
    link = { '$valor' => 'card.link_da_agenda' }
    { gatilho: { tipo: 'card.reuniao_cancelada', funil_id: funil.id }, passos: [
      { id: 'link_de_novo', tipo: 'mensagem', texto: ['A conversa foi cancelada. Escolha outro horário: ', link],
        modelo: { nome: 'nova_data_da_conversa', idioma: 'pt_BR', variaveis: [[link]] } },
      { id: 'cancelou_antes', tipo: 'se', condicao: { campo: { '$valor' => 'contato.etiquetas' }, op: 'contem', valor: 'cancelou-uma-vez' },
        entao: [no_contato('frio', 'frio')], senao: [no_contato('primeira_vez', 'cancelou-uma-vez')] }
    ] }
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name)
    flags_do_piloto(account)
    # crm_outro_canal: a resposta da empresa cai no card que a prospecção criou (Crm::Conversations::OutroCanal).
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2', 'whatsapp_campaign', 'crm_outro_canal')
    prospeccao_pelo_google
    create(:inbox_member, user: andre, inbox: canal.inbox)
    # A caixa do WhatsApp ligada ao quadro "Prospecção", criando card para conversa nova.
    Crm::PipelineInbox.create!(account: account, inbox: canal.inbox, pipeline: funil, default_stage: etapa_nova, auto_create_card: true)
    # O número que a Prospecção usa para conferir WhatsApp (WhatsappVerifier.session_for).
    create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'conferencia-andre' })
    etiquetas_e_modelos
    agenda
  end

  def prospeccao_pelo_google
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places')
  end

  def etiquetas_e_modelos
    %w[prospecção-novembro tem-contador cancelou-uma-vez frio].each do |nome|
      create(:label, account: account, title: nome, description: "Prospecção: #{nome}")
    end
    canal.update!(message_templates: [apresentacao, nova_data])
  end

  # O Google devolve os `lugares` da vez, como o Places responde.
  def google_places
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT).to_return do
      places = lugares.map do |chave|
        nome, telefone = empresas.fetch(chave)
        { id: "places/#{chave}", displayName: { text: nome }, formattedAddress: "#{nome}, Campinas - SP", internationalPhoneNumber: telefone,
          addressComponents: [{ longText: 'Campinas', shortText: 'Campinas', types: %w[locality] }] }
      end
      { status: 200, body: { places: places }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  # A WAHA responde se o número tem WhatsApp: só o fixo da Ferragens não tem.
  def waha_confere
    stub_request(:get, ->(uri) { uri.host == URI(waha_da_prospeccao).host && uri.path == '/api/contacts/check-exists' }).to_return do |pedido|
      telefone = URI.decode_www_form(pedido.uri.query).to_h.fetch('phone')
      { status: 200, body: { numberExists: telefone != sem_whatsapp }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  # A trava do disparo pergunta à Meta o estado do modelo na hora (#1329): a Meta de teste responde aprovado.
  def meta_confere_modelos
    stub_request(:get, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') })
      .to_return(status: 200, body: { data: [apresentacao.merge('id' => '9001'), nova_data.merge('id' => '9002')] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def ligar_tudo
    { 'Segunda: prospecção' => receita_da_segunda, 'Resposta da empresa' => receita_da_resposta,
      'Reunião marcada' => receita_da_reuniao, 'Reunião cancelada' => receita_do_cancelamento }.each do |nome, receita|
      ligar_automacao(andre, account, montar_automacao(andre, account, nome: nome, receita: receita))
    end
  end

  # Os jobs do caminho de produção: os do fechamento, o evento do card (reunião), a ligação da conversa ao card no CRM,
  # a conferência de WhatsApp da Prospecção e o disparo da campanha.
  def drenados
    [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob, Crm::SyncConversationCardJob,
     Autonomia::Prospecting::VerifyWhatsappJob, Campaigns::TriggerOneoffCampaignJob]
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

  # A varredura de tempo na segunda às 8h05 (a ocorrência das 8h), e a do motor 3 minutos depois, quando a espera da
  # conferência de WhatsApp acorda. O bloco roda entre as duas, com a execução esperando.
  def chega_a_segunda(dia, *empresas)
    lugares.replace(empresas)
    travel_to(fuso.parse("#{dia} 08:05")) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
      drenar
      yield if block_given?
    end
    travel_to(fuso.parse("#{dia} 08:08")) do
      Autonomia::Automacao::VarreduraJob.perform_now
      drenar
    end
  end

  def primeira_segunda = chega_a_segunda('2026-11-09', :padaria, :oficina, :studio, :ferragens)

  def numero(chave) = Autonomia::Prospecting::PhoneContract.e164(empresas.fetch(chave).last, region: 'BR')
  def contato(chave) = account.contacts.find_by!(phone_number: numero(chave))
  def card_de(chave) = account.crm_cards.find_by!(contact: contato(chave))
  def conversa_de(chave) = account.conversations.find_by!(contact: contato(chave), inbox: canal.inbox)

  def empresa_responde(chave, texto, quando: '2026-11-09 10:00')
    travel_to(fuso.parse(quando)) do
      cliente_escreve_pela_cloud(canal, remetente: numero(chave).delete('+'), nome: empresas.fetch(chave).first, texto: texto)
      drenar
    end
  end

  def saidas = chamadas_para('graph.facebook.com')
  def modelos_para(chave) = para(chave).select { |chamada| chamada.corpo['template'] }
  def textos_para(chave) = para(chave).filter_map { |chamada| chamada.corpo.dig('text', 'body') }
  # A campanha manda para o telefone do contato (+55...); a conversa, para o wa_id da Cloud (55..., sem o +).
  def para(chave) = saidas.select { |chamada| chamada.corpo['to'].to_s.delete('+') == numero(chave).delete('+') }
  def historico(nome) = Autonomia::Automacao::Registro.where(automacao_id: automacao_id(nome)).order(:id).pluck(:passo, :resultado, :motivo)
  def automacao_id(nome) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: nome).id
  def mencoes_do_andre = Notification.where(user: andre, notification_type: 'conversation_mention')

  def marcar_reuniao(chave, comeca)
    params = { title: 'Conversa de 20 minutos', starts_at: comeca, ends_at: comeca + 20.minutes, timezone: fuso.name, extra_guests: [],
               location_type: 'whatsapp_video' }
    Crm::Meetings::InternalCreator.new(account: account, card: card_de(chave), inbox: nil, scheduled_by: andre, params: params).perform
  end

  before do
    preparar_conta
    google_places
    waha_confere
    meta_confere_modelos
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    travel_to(fuso.parse('2026-11-06 15:00')) do
      busca_salva
      ligar_tudo
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  it 'passos 1 a 4: na segunda às 8h, só as empresas com WhatsApp viram card, ganham a etiqueta e recebem a apresentação',
     :aggregate_failures do
    espera = nil
    chega_a_segunda('2026-11-09', :padaria, :oficina, :studio, :ferragens) do
      execucao = Autonomia::Automacao::Execucao.find_by!(automacao_id: automacao_id('Segunda: prospecção'))
      espera = [execucao.estado, execucao.due_at, account.crm_cards.count]
    end

    # A busca espera a conferência de WhatsApp: a execução fica esperando, sem card, e acorda 2 minutos depois.
    expect(espera).to eq(['esperando', fuso.parse('2026-11-09 08:07'), 0])
    # Passo 1: a busca do histórico rodou de novo no Google, sem cache, pela automação.
    busca = Autonomia::Prospecting::Search.where.not(id: busca_salva.id).sole
    expect([busca.query, busca.location, busca.status, busca.user]).to eq(['empresas abertas este mês', 'Campinas, SP', 'completed', andre])
    expect(a_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)).to have_been_made.once
    # Passo 2: a conferência da própria Prospecção descartou a Ferragens, que não tem WhatsApp.
    expect(a_request(:get, ->(uri) { uri.host == URI(waha_da_prospeccao).host })).to have_been_made.times(4)
    expect(account.contacts.where(phone_number: sem_whatsapp)).to be_empty
    # Passo 3: um card por empresa com WhatsApp no quadro "Prospecção", com a etiqueta no contato.
    cards = account.crm_cards.where(pipeline: funil)
    expect(cards.map(&:title)).to contain_exactly('Padaria Nova Campinas', 'Oficina Barão Geraldo', 'Studio Cambuí')
    expect(cards.map(&:stage_id).uniq).to eq([etapa_nova.id])
    expect(cards.map { |card| card.contact.label_list }).to all(eq(['prospecção-novembro']))
    # Passo 4: a campanha com o modelo aprovado saiu só para elas.
    expect(account.campaigns.sole).to have_attributes(title: 'Apresentação do escritório', campaign_status: 'completed')
    enviados = saidas.map(&:corpo)
    expect(enviados.pluck('to')).to contain_exactly(numero(:padaria), numero(:oficina), numero(:studio))
    expect(enviados.map { |corpo| corpo.dig('template', 'name') }.uniq).to eq(['apresentacao_do_escritorio'])
    # A espera da conferência não grava linha no histórico (Executor#acao, `registrar: false`): só o que o passo fez.
    expect(historico('Segunda: prospecção')).to eq([['buscar', 'ok', nil], ['apresentar', 'ok', nil]])
  end

  context 'with a apresentação enviada na segunda' do
    before { primeira_segunda }

    it 'passos 5 e 6: com interesse, a conversa vai para o André e a empresa recebe o link da agenda dele, de 20 minutos',
       :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'interesse', 'motivo' => 'quer conversar' }

      empresa_responde(:padaria, 'Oi! Tenho interesse, podemos conversar?')

      expect(conversa_de(:padaria).assignee).to eq(andre)
      expect(textos_para(:padaria)).to eq(["Que bom! Escolha um horário para uma conversa de 20 minutos com o André: #{link_da_agenda}"])
      expect(agenda.reload.duration_minutes).to eq(20)
      expect(historico('Resposta da empresa').map(&:first)).to eq(%w[resposta para_o_andre agenda])
    end

    it 'passo 7: já tem contador, ganha a etiqueta e o André tem o retorno para daqui a 6 meses', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'tem_contador', 'motivo' => 'já tem contador' }

      empresa_responde(:oficina, 'Obrigado, mas já temos contador.')

      expect(contato(:oficina).label_list).to contain_exactly('prospecção-novembro', 'tem-contador')
      expect(Crm::FollowUp.sole).to have_attributes(title: 'Voltar a falar com Oficina Barão Geraldo', status: 'pending',
                                                    due_at: fuso.parse('2026-11-09 10:00') + 180.days)
      expect(Crm::FollowUp.sole).to have_attributes(recipient_mode: 'users', recipient_user_ids: [andre.id], contact_id: contato(:oficina).id)
      expect(textos_para(:oficina)).to be_empty
    end

    it 'passo 8: não quer contato, a recusa fica na Prospecção e a empresa nunca mais recebe nada', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'nao_quer', 'motivo' => 'pediu para não ser contatada' }

      empresa_responde(:studio, 'Não quero contato, por favor tirem meu número.')

      lead = Autonomia::Prospecting::Lead.find_by!(account: account, provider_place_id: 'places/studio')
      expect([lead.consent_refused_at.present?, lead.consent_refused_by]).to eq([true, andre])
      expect(contato(:studio)).to be_opted_out

      # Na segunda seguinte o Google devolve o Studio de novo, junto com uma empresa nova.
      chega_a_segunda('2026-11-16', :studio, :mercado)

      expect(account.crm_cards.where(contact: contato(:studio)).count).to eq(1)
      expect(card_de(:mercado).stage).to eq(etapa_nova)
      expect(modelos_para(:studio).size).to eq(1)
      expect(modelos_para(:mercado).size).to eq(1)
    end

    context 'with o interesse e a conversa com o André' do
      before do
        roteiro['automacao_decidir'] = { 'caminho' => 'interesse', 'motivo' => 'quer conversar' }
        empresa_responde(:padaria, 'Oi! Tenho interesse, podemos conversar?')
      end

      it 'passo 9: reunião marcada, o card vai para "Reunião" e o André recebe o resumo da empresa', :aggregate_failures do
        roteiro['automacao_resumir'] = { 'resumo' => 'Padaria Nova Campinas, em Campinas: quer conhecer o escritório.' }

        travel_to(fuso.parse('2026-11-09 11:00')) do
          marcar_reuniao(:padaria, fuso.parse('2026-11-11 15:00'))
          drenar
        end

        expect(card_de(:padaria).stage).to eq(etapa_reuniao)
        expect(mencoes_do_andre.count).to eq(1)
        nota = conversa_de(:padaria).messages.where(private: true).find_by('content LIKE ?', "%mention://user/#{andre.id}/%")
        expect(nota.content).to include('quer conhecer o escritório')
        lido = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_resumir' }.sole['input'].to_json
        expect(lido).to include('Padaria Nova Campinas', 'Tenho interesse')
        expect(historico('Reunião marcada').map { |passo, resultado, _| [passo, resultado] }).to eq([%w[para_reuniao ok], %w[resumo ok]])
      end

      it 'passo 10: reunião cancelada, a empresa recebe o link de novo; cancelou duas vezes, ganha a etiqueta "frio"', :aggregate_failures do
        roteiro['automacao_resumir'] = { 'resumo' => 'Padaria Nova Campinas quer conhecer o escritório.' }
        reuniao = travel_to(fuso.parse('2026-11-09 11:00')) { marcar_reuniao(:padaria, fuso.parse('2026-11-11 15:00')).tap { drenar } }
        travel_to(fuso.parse('2026-11-09 12:00')) do
          Crm::Meetings::CancelService.new(meeting: reuniao.reload).perform
          drenar
        end

        expect(textos_para(:padaria).last).to eq("A conversa foi cancelada. Escolha outro horário: #{link_da_agenda}")
        expect(contato(:padaria).label_list).to contain_exactly('prospecção-novembro', 'cancelou-uma-vez')

        # Três dias depois (janela de 24 h fechada), marca e cancela de novo: o link vai pelo modelo aprovado.
        travel_to(fuso.parse('2026-11-12 09:00')) do
          outra = marcar_reuniao(:padaria, fuso.parse('2026-11-13 15:00'))
          drenar
          Crm::Meetings::CancelService.new(meeting: outra.reload).perform
          drenar
        end

        modelo = modelos_para(:padaria).last.corpo['template']
        expect(modelo['name']).to eq('nova_data_da_conversa')
        expect(modelo.dig('components', 0, 'parameters', 0, 'text')).to eq(link_da_agenda)
        expect(contato(:padaria).label_list).to contain_exactly('prospecção-novembro', 'cancelou-uma-vez', 'frio')
      end
    end
  end
end
