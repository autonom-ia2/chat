require 'rails_helper'

# E5 (#2898) — o desfecho do card de renovação chega ao seguro por um caminho só: quem fecha, reabre ou arquiva o CARD
# (o quadro, a gaveta do seguro, a IA, uma automação) faz o seguro se acertar pelo estado do card. Aqui o card é mexido
# como o quadro mexe (Crm::Cards::Closer, Crm::Cards::Archiver e a API do CRM). Tudo fictício.
RSpec.describe Carteira::RenovacaoListener do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ajustes) { escolher_funil_de_renovacao(account, user: admin) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, numero: 'EX-000001', fim_vigencia: hoje + 30) }
  let(:card) { por_em_renovacao(seguro, ajustes) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    card
  end

  def fechar(resultado, quem: admin, o_card: card)
    Crm::Cards::Closer.new(card: o_card.reload, actor: quem, result: resultado).perform
  end

  def arquivar(o_card = card)
    Crm::Cards::Archiver.new(card: o_card.reload, actor: admin).perform
  end

  def desfecho(apolice = seguro)
    apolice.reload.slice(:renovado_em, :nao_renovou_em, :motivo_nao_renovou, :motivo_escrito, :renovacao_card_removido_em).compact
  end

  def passos(apolice = seguro)
    apolice.eventos.order(:id).pluck(:tipo)
  end

  def selo(apolice = seguro)
    Carteira::Selo.de(apolice.reload, hoje: hoje)
  end

  it 'antes de qualquer desfecho o seguro está em renovação' do
    expect([desfecho, selo, passos]).to eq([{}, 'em_renovacao', ['renovacao_card_nasceu']])
  end

  it 'card ganho: o seguro renovou, e a história guarda o passo com quem fechou' do
    fechar('won')

    expect(card.reload.status).to eq('won')
    expect([desfecho, selo, passos]).to eq([{ 'renovado_em' => agora }, 'renovado', %w[renovacao_card_nasceu renovou]])
    expect(seguro.eventos.find_by(tipo: 'renovou')).to have_attributes(user_id: admin.id, quando: agora, valores: {})
  end

  it 'card perdido: não renovou, ainda sem motivo, e o seguro segue ativo até terminar' do
    fechar('lost')

    expect(card.reload.status).to eq('lost')
    expect([desfecho, selo, passos]).to eq([{ 'nao_renovou_em' => agora }, 'ativo', %w[renovacao_card_nasceu nao_renovou]])
    expect(seguro.eventos.find_by(tipo: 'nao_renovou')).to have_attributes(user_id: admin.id, valores: {})
  end

  it 'em funil que não conta como venda o card fecha como resolvido ou cancelado, e o seguro entende igual' do
    ajustes.pipeline.update!(counts_as_sale: false)
    outro = criar_apolice(marina, numero: 'EX-000002', fim_vigencia: hoje + 40)
    card_do_outro = por_em_renovacao(outro, ajustes)

    fechar('won')
    fechar('lost', o_card: card_do_outro)

    expect([card.reload.status, card_do_outro.reload.status]).to eq(%w[resolved cancelled])
    expect([desfecho, desfecho(outro)]).to eq([{ 'renovado_em' => agora }, { 'nao_renovou_em' => agora }])
  end

  # O card cancelado não tem motivo de perda (o motivo do quadro é só do perdido): o seguro fica "não renovou" sem
  # motivo, sem quebrar, e o motivo pode ser dito depois, na gaveta.
  it 'o card cancelado deixa o seguro como não renovou, sem motivo, e o motivo pode vir depois' do
    ajustes.pipeline.update!(counts_as_sale: false)

    fechar('lost')
    sem_motivo = seguro.reload.slice(:motivo_nao_renovou, :motivo_escrito).values
    passo = seguro.eventos.find_by(tipo: 'nao_renovou')
    Carteira::Renovacao::Desfecho.new(seguro).dizer_motivo('nao_respondeu', nil)

    expect([card.reload.status, card.lost_reason, sem_motivo, passo.valores]).to eq(['cancelled', nil, [nil, nil], {}])
    expect(seguro).to be_valid
    expect([desfecho, selo]).to eq([{ 'nao_renovou_em' => agora, 'motivo_nao_renovou' => 'nao_respondeu' }, 'ativo'])
  end

  it 'quem fecha sem ser uma pessoa (a IA, uma automação) deixa o passo sem autor' do
    fechar('won', quem: nil)

    expect(seguro.eventos.find_by(tipo: 'renovou').user_id).to be_nil
    expect(desfecho).to eq('renovado_em' => agora)
  end

  it 'reabrir o card desfaz o desfecho, com o motivo, e o seguro volta a estar em renovação' do
    fechar('lost')
    Carteira::Renovacao::Desfecho.new(seguro.reload).dizer_motivo('achou_caro', nil)
    com_motivo = desfecho

    fechar('reopen')

    expect(com_motivo).to eq('nao_renovou_em' => agora, 'motivo_nao_renovou' => 'achou_caro')
    expect([card.reload.status, desfecho, selo]).to eq(['open', {}, 'em_renovacao'])
    expect(passos).to eq(%w[renovacao_card_nasceu nao_renovou desfez_desfecho])
    expect(seguro.eventos.order(:id).last).to have_attributes(user_id: admin.id, quando: agora, valores: { 'anterior' => 'nao_renovou' })
  end

  it 'reabrir o card ganho guarda na história que o desfecho desfeito era "renovou"' do
    fechar('won')
    fechar('reopen')

    expect(passos).to eq(%w[renovacao_card_nasceu renovou desfez_desfecho])
    expect(seguro.eventos.order(:id).last.valores).to eq('anterior' => 'renovou')
  end

  it 'o card ganho que alguém marca como perdido troca o desfecho do seguro' do
    fechar('won')
    travel 1.hour
    fechar('lost')

    expect(desfecho).to eq('nao_renovou_em' => agora + 1.hour)
    expect(passos).to eq(%w[renovacao_card_nasceu renovou nao_renovou])
  end

  it 'arquivar o card aberto tira a renovação do seguro, e a rotina não cria outro card nesta vigência' do
    arquivar

    Carteira::Renovacao::DaContaJob.perform_now(account.id)

    expect([desfecho, selo]).to eq([{ 'renovacao_card_removido_em' => agora }, 'ativo'])
    expect([Crm::Card.where(account_id: account.id).count, seguro.reload.crm_card_id]).to eq([1, card.id])
  end

  it 'o card arquivado que volta ao quadro devolve a renovação ao seguro' do
    arquivar
    fechar('reopen')

    expect([card.reload.status, desfecho, selo, passos]).to eq(['open', {}, 'em_renovacao', ['renovacao_card_nasceu']])
  end

  # Restaurar pela tela dos arquivados (Crm::Cards::Restorer) reabre o card pelo mesmo evento: a marca gravada no
  # arquivamento sai, o seguro volta a mostrar a renovação em andamento e a rotina não cria um segundo card.
  it 'restaurar o card arquivado tira a marca do seguro, que volta a estar em renovação com o mesmo card' do
    arquivar
    marcado = desfecho

    restaurado = Crm::Cards::Restorer.new(card: card.reload, actor: admin).perform
    Carteira::Renovacao::DaContaJob.perform_now(account.id)

    expect([marcado, restaurado.restored?]).to eq([{ 'renovacao_card_removido_em' => agora }, true])
    expect([card.reload.status, desfecho, selo, passos]).to eq(['open', {}, 'em_renovacao', ['renovacao_card_nasceu']])
    expect([Crm::Card.where(account_id: account.id).count, seguro.reload.crm_card_id]).to eq([1, card.id])
  end

  it 'restaurar o card arquivado depois de ganho mantém o seguro renovado' do
    fechar('won')
    arquivar

    restaurado = Crm::Cards::Restorer.new(card: card.reload, actor: admin).perform

    expect([restaurado.restored?, card.reload.status, desfecho, selo]).to eq([true, 'won', { 'renovado_em' => agora }, 'renovado'])
  end

  it 'arquivar o card já ganho não desfaz a renovação' do
    fechar('won')
    arquivar

    expect([card.reload.status, desfecho, selo]).to eq(['archived', { 'renovado_em' => agora }, 'renovado'])
  end

  describe 'pela API do quadro', type: :request do
    it 'chega ao seguro em conta sem webhook, sem anúncio e sem automação' do
      post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/close", params: { result: 'won' }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect([account.webhooks.count, desfecho]).to eq([0, { 'renovado_em' => agora }])
    end
  end

  it 'receber o mesmo evento de novo não muda nada nem repete o passo da história' do
    fechar('won')
    travel 1.hour

    2.times { Carteira::Renovacao::Desfecho.new(seguro.reload, user: admin).acertar }

    expect([desfecho, passos]).to eq([{ 'renovado_em' => agora }, %w[renovacao_card_nasceu renovou]])
  end

  it 'o card que não é de seguro nenhum não mexe em nada' do
    solto = account.crm_cards.create!(pipeline: ajustes.pipeline, stage: ajustes.stage, contact: marina, title: 'Outro assunto')

    fechar('won', o_card: solto)

    expect([solto.reload.status, desfecho, passos]).to eq(['won', {}, ['renovacao_card_nasceu']])
  end

  it 'a falha ao escrever no seguro não desfaz o fechamento do card: vai para o log, só com ids' do
    allow(Rails.logger).to receive(:error)
    allow(Carteira::Renovacao::Desfecho).to receive(:new).and_raise(ActiveRecord::StatementTimeout, 'canceling statement')

    fechar('won')

    expect([card.reload.status, desfecho]).to eq(['won', {}])
    expect(Rails.logger).to have_received(:error)
      .with("[carteira][renovacao] desfecho não chegou ao seguro card=#{card.id} ActiveRecord::StatementTimeout")
  end

  # Estes eventos saem para todo card de toda conta que tenha qualquer assinante (webhook, anúncio, automação), e a
  # pergunta do emissor roda a cada desfecho de card. A conta sem a carteira não paga consulta nenhuma por isso; o card
  # que não é de seguro paga só a leitura que diz que ele não é. Ninguém procura quem fechou o card antes disso.
  describe 'o que a escuta custa a quem não tem seguro no card' do
    let(:solto) { account.crm_cards.create!(pipeline: ajustes.pipeline, stage: ajustes.stage, contact: marina, title: 'Outro assunto') }

    def perguntar(o_card)
      Carteira::Renovacao::Escuta.assinante?(account, Events::Types::CRM_CARD_WON, card_id: o_card.id)
    end

    # Como num pedido do painel: a conta do pedido já está carregada.
    def consultas_do_ouvinte(o_card)
      evento = Events::Base.new(Events::Types::CRM_CARD_WON, Time.zone.now, account_id: account.id, card_id: o_card.id, activity_id: 0)
      Current.account = account
      consultas_da_carteira { described_class.instance.crm_card_won(evento) }
    ensure
      Current.reset
    end

    it 'na conta sem a carteira não faz consulta nenhuma, nem no emissor nem no ouvinte, mesmo com card de seguro' do
      account.disable_features!('carteira_seguros')

      expect([consultas_da_carteira { perguntar(card) }, consultas_do_ouvinte(card)]).to eq([0, 0])
      expect(perguntar(card)).to be(false)
    end

    it 'na conta com a carteira, o card que não é de seguro custa só a leitura que procura o seguro' do
      solto

      expect([consultas_da_carteira { perguntar(solto) }, consultas_do_ouvinte(solto)]).to eq([1, 1])
      expect([perguntar(solto), perguntar(card)]).to eq([false, true])
    end

    it 'o card de seguro de outra conta não passa pelo portão desta' do
      outra = conta_com_carteira

      expect(Carteira::Renovacao::Escuta.assinante?(outra, Events::Types::CRM_CARD_WON, card_id: card.id)).to be(false)
    end

    it 'a conta que ficou sem a carteira não tem o seguro mexido quando o card fecha' do
      account.disable_features!('carteira_seguros')

      fechar('won')

      expect([card.reload.status, desfecho, passos]).to eq(['won', {}, ['renovacao_card_nasceu']])
    end
  end
end
