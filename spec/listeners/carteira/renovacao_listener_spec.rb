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
    expect([desfecho, selo, passos]).to eq([{}, 'em_renovacao', ['card_nasceu']])
  end

  it 'card ganho: o seguro renovou, e a história guarda o passo com quem fechou' do
    fechar('won')

    expect(card.reload.status).to eq('won')
    expect([desfecho, selo, passos]).to eq([{ 'renovado_em' => agora }, 'renovado', %w[card_nasceu renovou]])
    expect(seguro.eventos.find_by(tipo: 'renovou')).to have_attributes(user_id: admin.id, quando: agora, valores: {})
  end

  it 'card perdido: não renovou, ainda sem motivo, e o seguro segue ativo até terminar' do
    fechar('lost')

    expect(card.reload.status).to eq('lost')
    expect([desfecho, selo, passos]).to eq([{ 'nao_renovou_em' => agora }, 'ativo', %w[card_nasceu nao_renovou]])
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
    expect(passos).to eq(%w[card_nasceu nao_renovou])
  end

  it 'o card ganho que alguém marca como perdido troca o desfecho do seguro' do
    fechar('won')
    travel 1.hour
    fechar('lost')

    expect(desfecho).to eq('nao_renovou_em' => agora + 1.hour)
    expect(passos).to eq(%w[card_nasceu renovou nao_renovou])
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

    expect([card.reload.status, desfecho, selo]).to eq(['open', {}, 'em_renovacao'])
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

    2.times { Carteira::Renovacao::Desfecho.do_card(card.id, user: admin) }

    expect([desfecho, passos]).to eq([{ 'renovado_em' => agora }, %w[card_nasceu renovou]])
  end

  it 'o card que não é de seguro nenhum não mexe em nada' do
    solto = account.crm_cards.create!(pipeline: ajustes.pipeline, stage: ajustes.stage, contact: marina, title: 'Outro assunto')

    fechar('won', o_card: solto)

    expect([solto.reload.status, desfecho, passos]).to eq(['won', {}, ['card_nasceu']])
  end

  it 'a falha ao escrever no seguro não desfaz o fechamento do card: vai para o log, só com ids' do
    allow(Rails.logger).to receive(:error)
    allow(Carteira::Renovacao::Desfecho).to receive(:do_card).and_raise(ActiveRecord::StatementTimeout, 'canceling statement')

    fechar('won')

    expect([card.reload.status, desfecho]).to eq(['won', {}])
    expect(Rails.logger).to have_received(:error)
      .with("[carteira][renovacao] desfecho não chegou ao seguro card=#{card.id} ActiveRecord::StatementTimeout")
  end
end
