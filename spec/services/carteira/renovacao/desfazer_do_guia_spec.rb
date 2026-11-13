require 'rails_helper'

# E5 (#2898) — o Guia alcança as escritas novas da renovação (elas entram no catálogo dele, derivado das rotas) e as
# executa sem confirmação. O que protege a conta é o desfazer do Guia (#855), que repõe cada linha que os models
# gravaram durante a ação. Aqui a prova de que ele alcança o que a renovação grava: o card, o seguro e a história,
# inclusive o que o ouvinte do card escreve depois do commit. Tudo fictício.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Renovação da carteira: o desfazer do Guia' do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ajustes) { escolher_funil_de_renovacao(account, user: admin) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, numero: 'EX-000001', tipo: 'auto', fim_vigencia: hoje + 5) }
  let(:card) { por_em_renovacao(seguro, ajustes) }
  let(:execucao) { Autonomia::Guide::Execucao.abrir(account: account, user: admin) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    card
  end

  def pelo_guia(&)
    Autonomia::Guide::Diario.gravando(execucao, 0, &)
  end

  def desfazer
    Autonomia::Guide::Desfazer.new(execucao: execucao.reload, user: admin).perform
  end

  def passos(apolice = seguro)
    apolice.eventos.order(:id).pluck(:tipo)
  end

  it 'desfaz o "Renovou": o card volta a aberto e o seguro a em renovação, sem o passo na história' do
    pelo_guia { Carteira::Renovacao::Fechar.new(seguro, user: admin).renovou }
    feito = [card.reload.status, seguro.reload.renovado_em, passos]

    relatorio = desfazer

    expect(feito).to eq(['won', agora, %w[card_nasceu renovou]])
    expect([card.reload.status, seguro.reload.renovado_em, passos, relatorio['conflitos']]).to eq(['open', nil, ['card_nasceu'], []])
  end

  it 'desfaz a apólice nova feita à mão: ela some, e o anterior deixa de estar renovado' do
    dados = { 'tipo' => 'auto', 'seguradora' => 'Outra Seguradora Exemplo', 'numero' => 'OS-777001', 'termina' => '2027-11-17' }
    pelo_guia { Carteira::Renovacao::ApoliceNova.new(seguro, dados, user: admin).call }
    feito = [Carteira::Apolice.where(account_id: account.id).count, seguro.reload.renovado_em, card.reload.status]

    relatorio = desfazer

    expect(feito).to eq([2, agora, 'won'])
    expect([Carteira::Apolice.where(account_id: account.id).count, seguro.reload.renovado_em, card.reload.status, relatorio['conflitos']])
      .to eq([1, nil, 'open', []])
  end
end
# rubocop:enable RSpec/DescribeClass
