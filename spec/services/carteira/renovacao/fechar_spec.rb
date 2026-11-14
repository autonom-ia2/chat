require 'rails_helper'

# E5 (#2898) — a gaveta do seguro e o quadro mexendo no mesmo card de renovação. A gaveta trava o seguro e o card, relê
# os dois e decide com o desfecho que o card tem agora, não com o que ela leu ao abrir; e grava o desfecho no seguro
# junto com o card, sem depender do ouvinte do card, que roda depois do commit e pode falhar. O caminho feliz da gaveta
# está em spec/requests/api/v1/accounts/relacionamentos_seguros_desfechos_spec.rb. Tudo fictício.
RSpec.describe Carteira::Renovacao::Fechar do
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

  def no_quadro(resultado)
    Crm::Cards::Closer.new(card: card.reload, actor: admin, result: resultado).perform
  end

  # O seguro como a gaveta o leu ao abrir, antes de o quadro mexer no card.
  def lido_pela_gaveta
    Carteira::Apolice.find(seguro.id)
  end

  def desfecho
    seguro.reload.slice(:renovado_em, :nao_renovou_em, :motivo_nao_renovou).compact
  end

  def passos
    seguro.eventos.order(:id).pluck(:tipo)
  end

  # O código da recusa, ou nil quando o pedido passou.
  def recusa
    yield
    nil
  rescue CustomExceptions::CarteiraRecusa => e
    e.codigo
  end

  # O aviso do card não chega ao seguro: o ouvinte não escreve nada.
  def calar_o_ouvinte
    %i[crm_card_won crm_card_lost crm_card_reopened].each { |evento| allow(Carteira::RenovacaoListener.instance).to receive(evento) }
  end

  describe 'a gaveta aberta enquanto alguém fecha o card no quadro' do
    it 'recusa "Renovou" no card que o quadro acabou de perder, e o card fica como o quadro deixou' do
      da_gaveta = lido_pela_gaveta
      no_quadro('lost')

      expect(recusa { described_class.new(da_gaveta, user: admin).renovou }).to eq('ja_tem_desfecho')
      expect([card.reload.status, desfecho, passos]).to eq(['lost', { 'nao_renovou_em' => agora }, %w[renovacao_card_nasceu nao_renovou]])
    end

    it 'recusa "Não renovou" no card que o quadro acabou de ganhar' do
      da_gaveta = lido_pela_gaveta
      no_quadro('won')

      expect(recusa { described_class.new(da_gaveta, user: admin).nao_renovou(motivo: 'achou_caro') }).to eq('ja_tem_desfecho')
      expect([card.reload.status, desfecho]).to eq(['won', { 'renovado_em' => agora }])
    end

    it '"Renovou" no card que o quadro acabou de ganhar não fecha de novo nem repete o passo' do
      da_gaveta = lido_pela_gaveta
      no_quadro('won')
      atividades = card.activities.count
      travel 1.hour

      renovado = described_class.new(da_gaveta, user: admin).renovou

      expect([renovado.renovado_em, card.activities.count, passos]).to eq([agora, atividades, %w[renovacao_card_nasceu renovou]])
    end

    it 'recusa o card que o quadro acabou de arquivar: a renovação saiu do quadro' do
      da_gaveta = lido_pela_gaveta
      Crm::Cards::Archiver.new(card: card.reload, actor: admin).perform

      expect(recusa { described_class.new(da_gaveta, user: admin).renovou }).to eq('sem_renovacao')
      expect([card.reload.status, desfecho]).to eq(['archived', {}])
    end

    # Todo caminho da carteira que mexe no card trava nesta ordem; ordem trocada em um deles é impasse no banco.
    it 'trava o seguro antes do card' do
      travas = []
      anotar = ->(*, dados) { travas << dados[:sql] if dados[:sql].include?('FOR UPDATE') }

      ActiveSupport::Notifications.subscribed(anotar, 'sql.active_record') { described_class.new(seguro, user: admin).renovou }

      ordem = %w[carteira_apolices crm_cards]
      tabelas = travas.map { |sql| ordem.find { |tabela| sql.include?(%("#{tabela}")) } }
      expect(tabelas.first(2)).to eq(ordem)
    end
  end

  describe 'quando o aviso do card não chega ao seguro' do
    before { calar_o_ouvinte }

    it '"Renovou" grava o desfecho no seguro junto com o card, com quem fechou' do
      described_class.new(seguro, user: admin).renovou

      expect([card.reload.status, desfecho, passos]).to eq(['won', { 'renovado_em' => agora }, %w[renovacao_card_nasceu renovou]])
      expect(seguro.eventos.order(:id).last.user_id).to eq(admin.id)
    end

    it '"Não renovou" grava o desfecho e o motivo, em vez de fechar o card e perder o motivo calado' do
      described_class.new(seguro, user: admin).nao_renovou(motivo: 'achou_caro')

      expect([card.reload.status, desfecho]).to eq(['lost', { 'nao_renovou_em' => agora, 'motivo_nao_renovou' => 'achou_caro' }])
      expect(seguro.eventos.order(:id).last).to have_attributes(tipo: 'nao_renovou', user_id: admin.id, valores: { 'motivo' => 'achou_caro' })
    end

    it '"Desfazer" reabre o card e limpa o desfecho do seguro' do
      described_class.new(seguro, user: admin).renovou
      described_class.new(seguro.reload, user: admin).desfazer

      expect([card.reload.status, desfecho, passos]).to eq(['open', {}, %w[renovacao_card_nasceu renovou desfez_desfecho]])
    end

    # O card foi perdido no quadro e o seguro ficou para trás. A gaveta acerta o seguro pelo card antes de guardar o
    # motivo; o passo fica sem autor, porque quem fechou foi o quadro.
    it 'o card perdido no quadro, com o seguro para trás, ganha o desfecho e o motivo pela gaveta' do
      no_quadro('lost')
      para_tras = desfecho
      atividades = card.activities.count

      described_class.new(seguro.reload, user: admin).nao_renovou(motivo: 'vendeu_o_bem')

      expect([para_tras, card.activities.count]).to eq([{}, atividades])
      expect(desfecho).to eq('nao_renovou_em' => agora, 'motivo_nao_renovou' => 'vendeu_o_bem')
      expect(seguro.eventos.order(:id).last).to have_attributes(tipo: 'nao_renovou', user_id: nil, valores: { 'motivo' => 'vendeu_o_bem' })
    end
  end

  it 'motivo para um seguro que não está como "não renovou" é recusado, nunca some calado' do
    expect(recusa { Carteira::Renovacao::Desfecho.new(seguro).dizer_motivo('achou_caro', nil) }).to eq('sem_desfecho')
    expect([desfecho, passos]).to eq([{}, ['renovacao_card_nasceu']])
  end
end
