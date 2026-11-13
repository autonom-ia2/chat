require 'rails_helper'

# #2631: o ensaio roda gatilho de card e de reunião em cards reais da conta que quem ensaia alcança, na situação que o
# motor pega. No de reunião, a reunião que o gatilho leria preenche `reuniao.*` (a data e o link); o card sem ela diz
# que não entraria. O card sem conversa segue a regra do motor (#2680). Nada é gravado nem mandado.
RSpec.describe Autonomia::Automacao::Ensaio, :automacao_motor do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }
  let(:card) { world.card }
  let(:inicio) { Time.utc(2026, 10, 20, 13, 0, 0) }
  let(:aviso) do
    mensagem_passo('p1', 'Sua reunião: ', { '$valor' => 'reuniao.inicio' }, ' em ', { '$valor' => 'reuniao.link_da_reuniao' })
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    card.update!(primary_conversation: create(:conversation, account: account, contact: world.contact))
  end

  def receita(*passos, gatilho:)
    { 'gatilho' => gatilho, 'passos' => passos }
  end

  def ensaio(receita, usuario: admin, conversa_id: nil)
    described_class.new(receita: receita, conta: account, usuario: usuario, conversa_id: conversa_id).resultado
  end

  def reuniao(**attrs)
    create_internal_meeting(world: world, starts_at: inicio, online_meeting_type: :custom_link,
                            online_meeting_url: 'https://meet.example.com/abc', **attrs)
  end

  it 'aceita os gatilhos de card e de reunião, menos o recorrente', :aggregate_failures do
    expect(described_class.gatilho_suportado?(receita(gatilho: { 'tipo' => 'card.reuniao_marcada' }))).to be(true)
    expect(described_class.gatilho_suportado?(receita(gatilho: { 'tipo' => 'card.parado' }))).to be(true)
    expect(described_class.gatilho_suportado?(receita(gatilho: { 'tipo' => 'card.recorrente' }))).to be(false)
    expect(described_class.gatilho_suportado?(receita(gatilho: { 'tipo' => 'contato.data' }))).to be(false)
    expect(described_class.de_conversa?(receita(gatilho: { 'tipo' => 'card.criado' }))).to be(false)
  end

  it 'reunião marcada: a data e o link da reunião do card no texto', :aggregate_failures do
    reuniao

    resultado = ensaio(receita(aviso, gatilho: { 'tipo' => 'card.reuniao_marcada' }))

    expect(resultado[:alvo]).to eq('card')
    item = resultado[:conversas].first
    expect(item).to include(conversa_id: card.id, nome: card.title, entraria: true)
    expect(item[:passos].first[:dados][:texto]).to eq('Sua reunião: 20/10/2026 às 10:00 em https://meet.example.com/abc')
  end

  it 'card sem reunião: diz que não entraria, sem passos' do
    item = ensaio(receita(aviso, gatilho: { 'tipo' => 'card.reuniao_marcada' }))[:conversas].first

    expect(item).to include(conversa_id: card.id, entraria: false, motivo: 'sem_reuniao', passos: [])
  end

  it 'cancelada lê a reunião cancelada; a agendada não serve' do
    reuniao

    item = ensaio(receita(aviso, gatilho: { 'tipo' => 'card.reuniao_cancelada' }))[:conversas].first
    expect(item).to include(entraria: false, motivo: 'sem_reuniao')

    reuniao(status: :canceled, starts_at: inicio + 1.day)
    texto = ensaio(receita(aviso, gatilho: { 'tipo' => 'card.reuniao_cancelada' }))[:conversas].first[:passos].first[:dados][:texto]
    expect(texto).to eq('Sua reunião: 21/10/2026 às 10:00 em https://meet.example.com/abc')
  end

  # G32: com a página escolhida, só a reunião marcada por ela.
  it 'com a página escolhida, a reunião de outra página não serve', :aggregate_failures do
    gatilho = { 'tipo' => 'card.reuniao_marcada', 'pagina_id' => world.profile.id }
    reuniao

    expect(ensaio(receita(aviso, gatilho: gatilho))[:conversas].first).to include(motivo: 'sem_reuniao')

    reuniao(metadata: { 'booking_profile_id' => world.profile.id })
    expect(ensaio(receita(aviso, gatilho: gatilho))[:conversas].first).to include(entraria: true)
  end

  it 'remarcada lê a reunião agendada, a mais recente' do
    reuniao
    reuniao(starts_at: inicio + 2.days)

    texto = ensaio(receita(aviso, gatilho: { 'tipo' => 'card.reuniao_remarcada' }))[:conversas].first[:passos].first[:dados][:texto]
    expect(texto).to eq('Sua reunião: 22/10/2026 às 10:00 em https://meet.example.com/abc')
  end

  it 'atendida lê a reunião que aconteceu; a só agendada não serve', :aggregate_failures do
    gatilho = { 'tipo' => 'card.reuniao_atendida' }
    reuniao

    expect(ensaio(receita(aviso, gatilho: gatilho))[:conversas].first).to include(entraria: false, motivo: 'sem_reuniao')

    reuniao(starts_at: inicio - 10.days, outcome: :held)
    texto = ensaio(receita(aviso, gatilho: gatilho))[:conversas].first[:passos].first[:dados][:texto]
    expect(texto).to eq('Sua reunião: 10/10/2026 às 10:00 em https://meet.example.com/abc')
  end

  # #2709: o lembrete só pega a reunião que ainda vai acontecer; a que já passou o motor não lembra.
  it 'lembrete: a próxima reunião agendada, nunca a que já passou', :aggregate_failures do
    gatilho = { 'tipo' => 'card.antes_da_reuniao', 'antes' => { 'valor' => 1, 'unidade' => 'dias' } }
    reuniao(starts_at: 1.day.ago)

    expect(ensaio(receita(aviso, gatilho: gatilho))[:conversas].first).to include(entraria: false, motivo: 'sem_reuniao')

    reuniao(starts_at: inicio + 2.days)
    reuniao
    texto = ensaio(receita(aviso, gatilho: gatilho))[:conversas].first[:passos].first[:dados][:texto]
    expect(texto).to eq('Sua reunião: 20/10/2026 às 10:00 em https://meet.example.com/abc')
  end

  it 'os cards com a reunião vêm antes dos sem ela' do
    sem = create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: world.contact)
    reuniao

    expect(ensaio(receita(aviso, gatilho: { 'tipo' => 'card.reuniao_marcada' }))[:conversas].pluck(:conversa_id)).to eq([card.id, sem.id])
  end

  it 'gatilho de etapa: só os cards da etapa escolhida, com os valores do card', :aggregate_failures do
    outra = create_crm_stage(account: account, pipeline: world.pipeline, name: 'Proposta')
    fora = create_booking_card(account: account, pipeline: world.pipeline, stage: outra, contact: world.contact)
    gatilho = { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => world.stage.id }

    resultado = ensaio(receita(mensagem_passo('p1', 'Card: ', { '$valor' => 'card.titulo' }), gatilho: gatilho))

    expect(resultado[:conversas].pluck(:conversa_id)).to eq([card.id])
    expect(resultado[:conversas].first[:passos].first[:dados][:texto]).to eq("Card: #{card.title}")
    expect(resultado[:conversas].pluck(:conversa_id)).not_to include(fora.id)
  end

  it 'nunca grava nem manda' do
    reuniao

    expect { ensaio(receita(aviso, gatilho: { 'tipo' => 'card.reuniao_marcada' })) }
      .not_to(change { [Message.count, Autonomia::Automacao::Execucao.count, Crm::Activity.count, Crm::Meeting.count] })
  end

  # A situação que a varredura pega (Tempo::Parado, Tempo::Data): o card fechado ou arquivado não aparece como "entraria"
  # onde o motor não o pegaria.
  describe 'a situação do card' do
    # O status direto no banco: fechar como ganho pede um funil com esse resultado; aqui só importa o status.
    def com_status(status, metadata = {})
      create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: world.contact)
        .tap { |alvo| alvo.update_columns(status: status, metadata: metadata) } # rubocop:disable Rails/SkipsModelValidations
    end

    def ids(gatilho) = ensaio(receita(esperar_passo('p1'), gatilho: gatilho))[:conversas].pluck(:conversa_id)

    it 'parado: o arquivado e o ganho ficam de fora; só o aberto' do
      com_status(:archived)
      com_status(:won)

      expect(ids({ 'tipo' => 'card.parado', 'etapa_id' => world.stage.id, 'dias' => 3 })).to eq([card.id])
    end

    it 'gatilho de evento: só o aberto' do
      com_status(:archived)
      com_status(:lost)

      expect(ids({ 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => world.stage.id })).to eq([card.id])
    end

    it 'data: o que deu certo entra; o perdido e o arquivado sem desfecho não', :aggregate_failures do
      certos = [com_status(:won), com_status(:archived, 'desfecho_arquivado' => 'won')]
      fora = [com_status(:lost), com_status(:archived)]

      vistos = ids({ 'tipo' => 'card.data', 'campo' => 'renovacao', 'dias' => 7, 'quando' => 'antes', 'hora' => 8 })

      expect(vistos).to contain_exactly(card.id, *certos.map(&:id))
      expect(vistos).not_to include(*fora.map(&:id))
    end
  end

  # #2680: a mesma regra do motor para o card sem conversa. Sem a caixa da conversa nova, todo passo que age numa
  # conversa pula; com ela, a mensagem abre a conversa e os passos depois dela agem nela.
  describe 'o card sem conversa' do
    let(:sem_conversa) { create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: world.contact) }
    let(:caixa) { create_crm_whatsapp_api_inbox(account: account, members: [admin]) }
    let(:passos) do
      [avisar_passo('a1', { 'responsavel' => true }, 'Novo card'), mensagem_passo('m1', 'Oi'),
       { 'id' => 'i1', 'tipo' => 'ia_assumir', 'agente_id' => 0 }]
    end

    def faria(gatilho)
      nos = ensaio(receita(*passos, gatilho: gatilho), conversa_id: sem_conversa.id)[:conversas].first[:passos]
      nos.to_h { |no| [no[:id], no[:faria]] }
    end

    it 'sem a caixa da conversa nova: o aviso, a mensagem e a agente pulam' do
      expect(faria({ 'tipo' => 'card.criado' })).to eq('a1' => 'sem_conversa', 'm1' => 'sem_conversa', 'i1' => 'sem_conversa')
    end

    it 'com a caixa: o aviso antes da mensagem pula; a mensagem abriria a conversa, e a agente responde por ela', :aggregate_failures do
      gatilho = { 'tipo' => 'card.criado', 'conversa_nova' => { 'caixa_id' => caixa.id } }
      nos = ensaio(receita(*passos, gatilho: gatilho), conversa_id: sem_conversa.id)[:conversas].first[:passos]

      expect(faria(gatilho)).to eq('a1' => 'sem_conversa', 'm1' => 'mensagem', 'i1' => 'agente_sumiu')
      expect(nos.second[:dados]).to include(texto: 'Oi', conversa_nova: caixa.name)
      expect { faria(gatilho) }.not_to(change { [Conversation.count, ContactInbox.count, Message.count] })
    end
  end

  describe 'o alcance de quem ensaia' do
    let(:agente) { create(:user, account: account, role: :agent) }
    let(:caixa) { create(:inbox, account: account) }
    let!(:visto) { create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: world.contact, inbox: caixa) }
    let!(:escondido) do
      create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: world.contact,
                          inbox: create(:inbox, account: account))
    end
    let(:gatilho) { { 'tipo' => 'card.criado' } }

    before { create(:inbox_member, user: agente, inbox: caixa) }

    it 'só os cards que ele vê', :aggregate_failures do
      ids = ensaio(receita(esperar_passo('p1'), gatilho: gatilho), usuario: agente)[:conversas].pluck(:conversa_id)

      expect(ids).to include(visto.id)
      expect(ids).not_to include(escondido.id)
    end

    it 'o card escolhido fora do alcance é como se não existisse', :aggregate_failures do
      expect { ensaio(receita(esperar_passo('p1'), gatilho: gatilho), usuario: agente, conversa_id: escondido.id) }
        .to raise_error(ActiveRecord::RecordNotFound)
      expect(ensaio(receita(esperar_passo('p1'), gatilho: gatilho), usuario: agente, conversa_id: visto.id)[:conversas].pluck(:conversa_id))
        .to eq([visto.id])
    end
  end
end
