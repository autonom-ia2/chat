require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 8 dos termos de aceite ("Funcionário novo no plano da empresa"), só o
# passo 9 (G22):
#
#   9. Toda sexta, para cada empresa com inclusão aberta, avisa o RH quem ainda não mandou documento.
#
# O exemplo inteiro segue pendente pelas outras lacunas (pendentes_spec.rb). A criação dos contatos e dos cards do passo
# 3 é da G24: o "para cada item" grava no card quem pediu (o RH, `solicitante`); aqui o card nasce com ele à mão. Sem
# gravador, o salvar recusa a condição (Solicitados::GRAVADORES, último exemplo). O documento que chega é marcado pela
# API do card, a mesma ação que a automação usa (PATCH crm/cards/:id).
#
# A Luciana monta e liga pela API da tela, numa função com só a caixa do WhatsApp oficial dela: o card de outra caixa
# não entra no texto ao RH. O RH é a pessoa da empresa que pediu (Marta, na Acme); a última mensagem dela foi há 4 dias,
# então o aviso sai pelo modelo aprovado e para no receptor do WhatsApp oficial. A varredura do motor roda com o relógio
# no fuso da conta.
RSpec.describe 'Fechamento #2414 · exemplo 8, passo 9: toda sexta o RH sabe quem falta', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:whatsapp) { canal.inbox }
  let(:luciana) { create(:user, account: account, role: :agent, name: 'Luciana') }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Dona da corretora') }
  let(:inclusao) { create_crm_pipeline(account: account, user: dona, name: 'Inclusão de vidas') }
  let(:documentos) { inclusao.last.tap { |etapa| etapa.update!(name: 'Documentos') } }
  let(:marta) { create(:contact, account: account, name: 'Marta', phone_number: '+5511900000081', company_id: empresa('Acme')) }
  let(:joao) { create(:contact, account: account, name: 'João', phone_number: '+5511900000082', company_id: empresa('Beta')) }
  let!(:cards) do
    receptor_whatsapp_cloud
    as('2026-11-16 10:00') do
      preparar_conta
      marta_mandou_a_lista
      pedidos_da_semana.merge(automacao: ligada)
    end
  end

  def tudo = { 'rg' => true, 'cpf' => true, 'comprovante' => true }
  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def as(hora, &) = travel_to(fuso.parse(hora), &)
  def empresa(nome) = create(:company, account: account, name: nome).id

  # Um job por vez, como no Sidekiq, com os jobs da varredura do recorrente no meio.
  def drenar
    drenados = [Autonomia::Automacao::TempoDaAutomacaoJob, Autonomia::Automacao::RecorrenteLoteJob, EventDispatcherJob,
                Autonomia::Automacao::AvancarJob, SendReplyJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def varredura_as(hora)
    as(hora) do
      Autonomia::Automacao::TempoJob.perform_now
      drenar
    end
  end

  # O card de cada funcionário, que o passo 3 cria (G24) com quem pediu: na caixa do WhatsApp da Luciana, na etapa
  # "Documentos".
  def pedido(nome, marcados = {}, quem_pediu: marta, etapa: documentos, caixa: whatsapp)
    funcionario = create(:contact, account: account, name: nome, company_id: quem_pediu.company_id)
    account.crm_cards.create!(pipeline: etapa.pipeline, stage: etapa, title: "Inclusão de #{nome}", currency: 'BRL', contact: funcionario,
                              inbox: caixa, solicitante: quem_pediu, custom_attributes: marcados)
  end

  # Ana mandou o RG; Bruno mandou tudo e já foi para "Enviar à operadora"; Carla não mandou nada. Na Beta, o João pediu
  # o Elias, que mandou tudo. Pendentes que não contam: o card de outro funil e o de uma caixa que a Luciana não vê.
  def pedidos_da_semana
    ana = pedido('Ana Souza', { 'rg' => true })
    pedido('Bruno Lima', tudo, etapa: create_crm_stage(account: account, pipeline: inclusao.first, name: 'Enviar à operadora'))
    carla = pedido('Carla Dias')
    pedido('Elias Prado', tudo, quem_pediu: joao)
    pedido('Fora do funil', etapa: create_crm_pipeline(account: account, user: dona, name: 'Vendas').last)
    pedido('Davi Rocha', caixa: create(:inbox, account: account, name: 'Caixa do outro corretor'))
    { ana: ana, carla: carla }
  end

  def ligada
    automacao = montar_automacao(luciana, account, nome: 'Documentos pendentes ao RH', receita: receita)
    ligar_automacao(luciana, account, automacao)
    clear_enqueued_jobs
    automacao
  end

  def receita
    faltam = { '$valor' => 'contato.solicitados_faltando' }
    { gatilho: { tipo: 'contato.recorrente', frequencia: 'semanal', dia_da_semana: 5, hora: 9,
                 selecao: { solicitante_de: { funil_id: inclusao.first.id, faltando: %w[rg cpf comprovante] } },
                 conversa_nova: { caixa_id: whatsapp.id } },
      passos: [{ id: 'aviso', tipo: 'mensagem', texto: ['Oi! Ainda faltam documentos de: ', faltam],
                 modelo: { nome: 'documentos_pendentes', idioma: 'pt_BR', variaveis: [[faltam]] } }] }
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    permissoes = %w[automation_manage conversation_manage contact_view contact_manage crm_view crm_manage_cards]
    account.account_users.find_by(user: luciana).update!(custom_role: create(:custom_role, account: account, permissions: permissoes))
    create(:inbox_member, user: luciana, inbox: whatsapp)
    { 'rg' => 'RG', 'cpf' => 'CPF', 'comprovante' => 'comprovante' }.each do |chave, rotulo|
      create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: rotulo,
                                           attribute_model: 'card_attribute', attribute_display_type: 'checkbox')
    end
    canal.update!(message_templates: [{ 'name' => 'documentos_pendentes', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                        'category' => 'UTILITY',
                                        'components' => [{ 'type' => 'BODY', 'text' => 'Oi! Ainda faltam documentos de: {{1}}' }] }])
  end

  # A Marta mandou a lista pelo WhatsApp na segunda; a janela de 24 h fecha bem antes de sexta.
  def marta_mandou_a_lista
    contact_inbox = create(:contact_inbox, inbox: whatsapp, contact: marta, source_id: '5511900000081')
    conversa = create(:conversation, account: account, inbox: whatsapp, contact: marta, contact_inbox: contact_inbox)
    create(:message, conversation: conversa, account: account, inbox: whatsapp, message_type: :incoming, sender: marta,
                     content: 'Seguem os funcionários novos')
  end

  def whatsapp_chamadas = chamadas_para('graph.facebook.com')
  def parametros(chamada) = chamada.corpo.dig('template', 'components', 0, 'parameters').pluck('text')

  after { Current.reset }

  it 'quinta, nada; sexta 9h, um aviso só, ao RH da Acme, com quem falta e o que falta; repetir não manda de novo',
     :aggregate_failures do
    varredura_as('2026-11-19 09:05')
    expect(whatsapp_chamadas).to be_empty

    varredura_as('2026-11-20 09:05')
    aviso = whatsapp_chamadas.sole
    expect(aviso.corpo).to include('to' => '5511900000081', 'type' => 'template')
    expect(aviso.corpo.dig('template', 'name')).to eq('documentos_pendentes')
    # Bruno (completo, já em "Enviar à operadora"), o card de outro funil e o da caixa que a Luciana não vê ficam fora;
    # o João, com tudo completo, não recebe nada.
    expect(parametros(aviso)).to eq(['Ana Souza (CPF, comprovante); Carla Dias (RG, CPF, comprovante)'])

    varredura_as('2026-11-20 09:35')
    expect(whatsapp_chamadas.size).to eq(1)

    execucao = Autonomia::Automacao::Execucao.where(automacao_id: cards[:automacao]['id']).sole
    expect(execucao).to have_attributes(alvo_type: 'Contact', alvo_id: marta.id)
    expect(historico_de(cards[:automacao])).to eq([['aviso', 'ok', nil]])
  end

  it 'com os documentos marcados no card durante a semana, a sexta seguinte não avisa ninguém', :aggregate_failures do
    varredura_as('2026-11-20 09:05')
    expect(whatsapp_chamadas.size).to eq(1)

    as('2026-11-24 15:00') do
      { cards[:ana] => { cpf: true, comprovante: true }, cards[:carla] => { rg: true, cpf: true, comprovante: true } }.each do |card, marcar|
        patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}",
              params: { card: { custom_attributes: marcar } }, headers: luciana.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok), -> { "o card não foi marcado: #{response.body}" }
      end
    end

    varredura_as('2026-11-27 09:05')
    expect(whatsapp_chamadas.size).to eq(1)
    expect(Autonomia::Automacao::Execucao.where(automacao_id: cards[:automacao]['id']).count).to eq(1)
  end

  it 'o salvar recusa o valor fora desse gatilho e campo que não é de marcar do card', :aggregate_failures do
    create(:custom_attribute_definition, account: account, attribute_key: 'cpf_do_contato', attribute_display_name: 'CPF do contato',
                                         attribute_model: 'contact_attribute', attribute_display_type: 'checkbox')
    create(:label, account: account, title: 'rh')
    sem_condicao = receita.merge(gatilho: receita[:gatilho].merge(selecao: { etiqueta: 'rh' }))
    campo_do_contato = receita.deep_merge(gatilho: { selecao: { solicitante_de: { faltando: %w[cpf_do_contato] } } })

    { sem_condicao => 'solicitados_so_no_recorrente', campo_do_contato => 'faltando_de_fora' }.each do |errada, frase|
      post api_automacoes(account), params: { nome: "Errada #{frase}", receita: errada }, headers: luciana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      chave = I18n.t("autonomia.automacao.receita.#{frase}",
                     passo: 'aviso', caminho: 'contato.solicitados_faltando', campo: 'cpf_do_contato', locale: :pt_BR)
      expect(response.body).to include(chave.to_json[1..-2])
    end
  end

  # Sem o passo 3 (G24) gravando quem pediu, card nenhum teria solicitante e toda sexta o aviso pularia sem mandar nada:
  # sem gravador, a Luciana nem consegue salvar a automação de sexta.
  it 'sem passo que grave o solicitante, o salvar recusa a automação de sexta', :aggregate_failures do
    stub_const('Autonomia::Automacao::Solicitados::GRAVADORES', [])

    post api_automacoes(account), params: { nome: 'Sexta sem gravador', receita: receita }, headers: luciana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    frase = I18n.t('autonomia.automacao.receita.solicitante_sem_gravador', locale: :pt_BR)
    expect(response.body).to include(frase.to_json[1..-2])
  end
end
