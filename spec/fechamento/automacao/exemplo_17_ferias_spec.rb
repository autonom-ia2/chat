require 'rails_helper'

# Fechamento do épico #2414, exemplo 17 dos termos de aceite, "Vendedora de férias, cliente bem cuidado", à risca e numa
# automação só (G63 #2830, G64 #2839, G66 #2843):
#
# > "Quando alguém sai de férias eu passo os clientes para outra pessoa, mas o cliente fica perdido e a colega não sabe
# > o que foi combinado. E quando ela volta, quero que os clientes voltem pra ela." — Paula, gerente comercial
#
# Começa quando o responsável do card muda e a anterior está ausente (G9): a Paula troca os cards da Júlia para a
# Renata pela Lista do CRM. Passos 1 a 3 como no g9_troca_de_responsavel_spec.rb. A troca do dono do card não leva a
# conversa (ela segue com a Júlia); pela decisão 14 do Rodrigo (G66), a receita põe depois da troca o passo "passar a
# conversa para o responsável do card", o único passo a mais que o termo. O passo 4 é o galho "a cada mensagem do
# cliente" (G63) do "esperar até" que espera a Júlia voltar, e "espera a Renata responder" lê quem atende a conversa,
# agora a Renata; o passo 5, "toda manhã", é a conferência às 8h no fuso da conta (G64, decisão 12); o 6, o resumo para a
# Júlia depois de devolver o card.
#
# A IA é o dublê; o WhatsApp oficial para no receptor de teste. Fica pendente, com o motivo, o "passa a conversa para a
# agente de IA" do passo 4: com a Renata no nome da conversa, o ia_assumir pula com `pessoa_atribuida` ("pessoa no nome
# vence", D1). Pede decisão do Rodrigo, não lacuna de código.
RSpec.describe 'Fechamento #2414 · exemplo 17: vendedora de férias, numa automação só', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false',
                      AI_AGENT_MEDIA: 'false') { exemplo.run }
  end

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:troca) { fuso.local(2026, 11, 2, 10) }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:paula) { create(:user, account: account, role: :administrator, name: 'Paula Gerente') }
  let(:julia) { create(:user, account: account, role: :agent, name: 'Júlia') }
  let(:renata) { create(:user, account: account, role: :agent, name: 'Renata') }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: paula, name: 'Vendas') }
  let(:sofia) { Autonomia::Agents::Agent.create!(account: account, name: 'Sofia', agent_type: 'custom', status: :active, enabled: true) }

  let(:maria) { create(:contact, account: account, name: 'Maria', phone_number: '+5511900000017') }
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: maria, source_id: '5511900000017')
    create(:conversation, account: account, inbox: inbox, contact: maria, contact_inbox: contact_inbox, assignee: julia, status: :open)
  end
  let(:card) do
    account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Proposta da Maria', currency: 'BRL',
                              contact: maria, primary_conversation: conversa, owner: julia)
  end

  let(:automacao) { montar_automacao(paula, account, nome: 'Cobertura de férias', receita: receita) }
  let(:receita) do
    { gatilho: { tipo: 'card.responsavel_mudou', funil_id: funil_e_etapa.first.id,
                 filtros: [{ campo: valor('gatilho.responsavel_anterior_ausente'), op: 'igual', valor: true }] },
      passos: [*passos_1_a_3, conversa_para_a_renata, ferias, *passos_da_volta] }
  end

  def valor(caminho) = { '$valor' => caminho }
  def account = canal.account
  def inbox = canal.inbox

  def passos_1_a_3
    [{ id: 'resumo', tipo: 'resumir', le: %w[mensagens_com_respostas], linhas: 4, destino: { avisar: { responsavel_do_card: true } } },
     { id: 'aviso_ao_cliente', tipo: 'mensagem',
       texto: ['Oi, ', valor('contato.nome'), '! A ', valor('gatilho.responsavel_anterior_nome'), ' está de férias e a ',
               valor('card.responsavel_nome'), ' vai cuidar de você até ela voltar. Ela já está a par de tudo'] },
     { id: 'original', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Gravar no card quem é a responsável original',
       caminho: { id: valor('card.id') },
       corpo: { card: { custom_attributes: { responsavel_original: valor('gatilho.responsavel_anterior_id') } } } },
     { id: 'etiqueta', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar',
       descricao: 'Pôr a etiqueta cobertura de férias', caminho: { conversation_id: valor('conversa.id') },
       corpo: { por: ['cobertura-de-ferias'] } }]
  end

  # G66 (decisão 14): a conversa acompanha a troca do dono do card, por um passo da automação, logo depois da troca.
  def conversa_para_a_renata = { id: 'conversa', tipo: 'conversa_ao_responsavel' }

  # Passos 4 e 5: espera a Júlia voltar, conferindo toda manhã às 8h; a cada mensagem do cliente, espera a Renata
  # responder por até 2 horas e, sem resposta, passa para a agente de IA.
  def ferias
    { id: 'ferias', tipo: 'esperar_ate', prazo: 'sem_prazo', conferir_as: 8,
      condicao: { campo: valor('card.atributos.responsavel_original.ausente'), op: 'igual', valor: false },
      a_cada_mensagem: [{ id: 'espera_a_renata', tipo: 'esperar_ate', prazo: { valor: 2, unidade: 'horas' },
                          condicao: { campo: valor('conversa.responsavel_respondeu'), op: 'igual', valor: true },
                          se_vencer: [{ id: 'sofia', tipo: 'ia_assumir', agente_id: sofia.id }] }] }
  end

  # Passos 5 (o resto) e 6: devolve o card, tira a etiqueta e a IA resume para a Júlia.
  def passos_da_volta
    [{ id: 'devolve', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Devolver o card à responsável original',
       caminho: { id: valor('card.id') }, corpo: { card: { owner_id: valor('card.atributos.responsavel_original') } } },
     { id: 'tira', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar',
       descricao: 'Tirar a etiqueta cobertura de férias', caminho: { conversation_id: valor('conversa.id') },
       corpo: { tirar: ['cobertura-de-ferias'] } },
     { id: 'conta', tipo: 'resumir', le: %w[mensagens_com_respostas], linhas: 4, destino: { avisar: { responsavel_do_card: true } } }]
  end

  def paula_passa_para(pessoa)
    post "/api/v1/accounts/#{account.id}/crm/cards/bulk",
         params: { ids: [card.id], action_name: 'assign', payload: { owner_id: pessoa.id } },
         headers: paula.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), -> { "a troca em lote falhou: #{response.body}" }
    rodar_jobs_do_card
  end

  def rodar_jobs_do_card
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| item[:job] == Autonomia::Automacao::EventoDoCardJob }
      break unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
      rodar_jobs
    end
  end

  def escreve_em(momento, texto) = travel_to(momento) { cliente_escreve(conversa, texto) }

  def renata_responde_em(momento)
    travel_to(momento) do
      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :outgoing, sender: renata,
                       content: 'Oi, Maria! Já te mando a proposta.')
      rodar_jobs
    end
  end

  def varrer_em(momento)
    travel_to(momento) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      rodar_jobs
      rodar_jobs_do_card
    end
  end

  def execucao = Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).sole
  def registros = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id)
  def voltas = registros.where(passo: 'ferias', motivo: 'mensagem_do_cliente').count
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')

  before do
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name)
    flags_do_piloto(account)
    account.enable_features!(Autonomia::Automacao::Motor::FLAG_GATILHOS)
    [julia, renata].each { |agente| create(:inbox_member, user: agente, inbox: inbox) }
    create(:label, account: account, title: 'cobertura-de-ferias', description: 'Cliente em cobertura de férias')
    create(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_key: 'responsavel_original',
                                         attribute_display_name: 'Responsável original', attribute_display_type: :pessoa)
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    Autonomia::Agents::Areas.vincular!(agent: sofia, inbox: inbox)
    receptor_whatsapp_cloud
    ia_responde(account, 'automacao_resumir' => { 'resumo' => 'Maria quer a proposta revisada até sexta. Próximo passo: enviar a proposta.' })
    travel_to(troca - 1.hour) do
      AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: fuso.local(2026, 11, 12, 18))
      cliente_escreve(conversa, 'Pode me mandar a proposta revisada até sexta?')
      card
      ligar_automacao(paula, account, automacao)
      clear_enqueued_jobs
    end
    travel_to(troca) { paula_passa_para(renata) }
  end

  after { Current.reset }

  it 'a troca faz os passos 1 a 3, passa a conversa para a Renata e espera a Júlia, conferindo às 8h da manhã seguinte',
     :aggregate_failures do
    expect(registros.pluck(:passo, :resultado)).to eq([%w[resumo ok], %w[aviso_ao_cliente ok], %w[original ok], %w[etiqueta ok],
                                                       %w[conversa ok], %w[ferias ok]])
    expect(execucao).to have_attributes(estado: 'esperando', cursor: 'ferias', due_at: fuso.local(2026, 11, 3, 8))
    expect(card.reload.owner).to eq(renata)
    expect(conversa.reload.assignee).to eq(renata)
    expect(conversa.reload.label_list).to include('cobertura-de-ferias')
  end

  # G66: a conversa passou para a Renata, e `conversa.responsavel_respondeu` espera por ela.
  it 'o cliente escreve e a Renata responde em 1 h: a agente de IA não entra', :aggregate_failures do
    escreve_em(fuso.local(2026, 11, 4, 10), 'Oi, alguém aí?')
    expect(execucao.cursor).to eq('espera_a_renata')

    renata_responde_em(fuso.local(2026, 11, 4, 11))
    varrer_em(fuso.local(2026, 11, 4, 12, 5))

    expect(registros.where(passo: 'sofia')).to be_empty
    expect(execucao).to have_attributes(estado: 'esperando', cursor: 'ferias')
  end

  it 'o cliente escreve e ninguém responde em 2 h: o galho termina no passo da IA e volta a esperar a Júlia', :aggregate_failures do
    escreve_em(fuso.local(2026, 11, 4, 10), 'Oi, alguém aí?')
    expect(execucao.cursor).to eq('espera_a_renata')

    varrer_em(fuso.local(2026, 11, 4, 12, 1))

    expect(registros.where(passo: 'sofia').count).to eq(1)
    expect(registros.where(passo: 'ferias').last.motivo).to eq('voltou_a_esperar')
    expect(execucao).to have_attributes(estado: 'esperando', cursor: 'ferias', due_at: fuso.local(2026, 11, 5, 8))
  end

  # A agente de IA não entra com uma pessoa no nome da conversa (PassoDeIaAssumir: "pessoa no nome vence", D1). Depois
  # do G66 a pessoa no nome é a Renata, como o termo quer para "espera a Renata responder"; o "passa a conversa para a
  # agente de IA" que vem depois pede decisão do Rodrigo sobre a D1 neste passo.
  it 'ninguém responde em 2 h: a conversa passa para a agente de IA', :aggregate_failures do
    pending 'D1: ia_assumir pula com pessoa_atribuida, porque a conversa está no nome da Renata (decisão do Rodrigo pendente)'
    escreve_em(fuso.local(2026, 11, 4, 10), 'Oi, alguém aí?')
    varrer_em(fuso.local(2026, 11, 4, 12, 1))

    expect(registros.where(passo: 'sofia').pluck(:resultado, :motivo)).to eq([['ok', nil]])
    expect(conversa.reload.ai_assignee).to eq(Autonomia::Agents::Areas.vincular!(agent: sofia, inbox: inbox).agent_bot)
  end

  it 'uma rajada de 3 mensagens vira uma volta só', :aggregate_failures do
    travel_to(fuso.local(2026, 11, 4, 10)) do
      3.times do |vez|
        create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: maria, content: "msg #{vez}")
      end
      rodar_jobs
    end
    travel_to(fuso.local(2026, 11, 4, 10, 30)) { cliente_escreve(conversa, 'e aí?') }
    varrer_em(fuso.local(2026, 11, 4, 12, 1))

    expect(voltas).to eq(1)
    expect(registros.where(passo: 'sofia').count).to eq(1)
    expect(execucao.cursor).to eq('ferias')
  end

  it 'a Júlia volta: a mensagem da tarde não devolve, às 7h59 nada, às 8h devolve, tira a etiqueta e ela recebe o resumo',
     :aggregate_failures do
    escreve_em(fuso.local(2026, 11, 12, 15), 'Já voltou a Júlia?')
    varrer_em(fuso.local(2026, 11, 12, 17, 1))
    expect(card.reload.owner).to eq(renata)
    expect(execucao).to have_attributes(estado: 'esperando', cursor: 'ferias', due_at: fuso.local(2026, 11, 13, 8))

    varrer_em(fuso.local(2026, 11, 13, 7, 59))
    expect(card.reload.owner).to eq(renata)

    varrer_em(fuso.local(2026, 11, 13, 8, 1))
    expect(card.reload.owner).to eq(julia)
    expect(conversa.reload.label_list).not_to include('cobertura-de-ferias')
    expect(execucao.estado).to eq('concluida')
    expect(registros.last(3).pluck(:passo, :resultado)).to eq([%w[devolve ok], %w[tira ok], %w[conta ok]])
    expect(mencoes_para(julia).count).to eq(1)
    expect(ia_recebeu.last.to_json).to include('Já voltou a Júlia?')
  end

  # G67: "a IA resume para a Júlia o que aconteceu durante as férias" (passo 6). O resumir lê as últimas mensagens da
  # conversa (Decisores::Estado::MAX_MENSAGENS, 5), sem a janela da execução: em férias com mais mensagens, o começo
  # delas não chega à IA.
  it 'o resumo da volta lê as mensagens das férias desde a primeira' do
    pending 'G67: o resumir lê só as 5 últimas mensagens, não o período da execução (as férias)'
    escreve_em(fuso.local(2026, 11, 3, 10), 'Primeira mensagem das férias')
    (4..9).each { |dia| escreve_em(fuso.local(2026, 11, dia, 10), "Mensagem do dia #{dia}") }
    AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: fuso.local(2026, 11, 9, 18))
    varrer_em(fuso.local(2026, 11, 10, 8, 1))

    expect(card.reload.owner).to eq(julia)
    expect(ia_recebeu.last.to_json).to include('Primeira mensagem das férias')
  end

  it 'o teto do galho: passou, registra uma vez e a conferência da manhã continua', :aggregate_failures do
    stub_const('Autonomia::Automacao::EnquantoEspera::A_CADA_TETO', 2)
    AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: fuso.local(2026, 11, 6, 18))

    [4, 5].each do |dia|
      escreve_em(fuso.local(2026, 11, dia, 10), 'Oi?')
      varrer_em(fuso.local(2026, 11, dia, 12, 1))
    end
    escreve_em(fuso.local(2026, 11, 5, 15), 'Oi de novo?')

    expect(voltas).to eq(2)
    expect(registros.where(passo: 'ferias', motivo: 'teto_a_cada').count).to eq(1)
    varrer_em(fuso.local(2026, 11, 7, 8, 1))
    expect(card.reload.owner).to eq(julia)
  end

  # Nova York sai do horário de verão às 2h de 01/11/2026: a troca no sábado conferirá no domingo às 8h locais (13h UTC,
  # não 12h), e a conferência seguinte também.
  context 'with horário de verão no fuso da conta' do
    let(:fuso) { ActiveSupport::TimeZone['America/New_York'] }
    let(:troca) { fuso.local(2026, 10, 31, 10) }

    it 'a conferência fica às 8h locais na troca de horário', :aggregate_failures do
      expect(execucao.due_at).to eq(fuso.local(2026, 11, 1, 8))
      expect(execucao.due_at.utc.hour).to eq(13)

      varrer_em(fuso.local(2026, 11, 1, 8, 1))
      expect(execucao.due_at).to eq(fuso.local(2026, 11, 2, 8))
    end
  end

  # O ensaio só roda em gatilho de conversa (Ensaio.gatilho_suportado?): os mesmos passos 4 e 5 numa conversa. O galho
  # aparece com os passos dele e a marca de volta, sem rodar o laço.
  it 'no ensaio, o galho mostra os passos e para no fim, com a volta à espera', :aggregate_failures do
    em_conversa = JSON.parse({ gatilho: { tipo: 'conversa.criada' }, passos: [ferias] }.to_json)
    resultado = Autonomia::Automacao::Ensaio.new(receita: em_conversa, conta: account, usuario: paula, conversa_id: conversa.display_id).resultado

    passo = resultado[:conversas].first[:passos].first
    galho = passo[:ramos].find { |ramo| ramo[:chave] == 'a_cada_mensagem' }
    expect(galho[:volta]).to eq('ferias')
    expect(galho[:passos].first).to include(id: 'espera_a_renata', faria: 'esperar_ate')
  end

  # Com a hora marcada, o motor só confere às 8h: o ensaio não diz "já vale, seguiria na hora" mesmo com a condição
  # valendo agora; mostra a espera até a hora. Sem a hora, o "já vale" de sempre.
  it 'no ensaio, a condição que já vale com hora marcada mostra a espera até a hora, não "seguiria na hora"', :aggregate_failures do
    ja_vale = { campo: valor('conversa.status'), op: 'igual', valor: 'open' }
    ensaiar = lambda do |espera|
      receita = JSON.parse({ gatilho: { tipo: 'conversa.criada' }, passos: [espera] }.to_json)
      Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: paula, conversa_id: conversa.display_id)
                                  .resultado[:conversas].first[:passos].first
    end

    com_hora = ensaiar.call(ferias.merge(condicao: ja_vale))
    expect(com_hora).to include(id: 'ferias', faria: 'esperar_ate')
    expect(com_hora[:ramos].map { |ramo| ramo[:chave] }).to eq(%w[chegou a_cada_mensagem])

    expect(ensaiar.call(ferias.merge(condicao: ja_vale).except(:conferir_as, :a_cada_mensagem))).to include(faria: 'esperar_ate_ja_vale')
  end
end
