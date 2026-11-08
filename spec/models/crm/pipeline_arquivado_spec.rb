require 'rails_helper'

# Funil arquivado sai dos Números e dos Relatórios, como já saía das Metas (Crm::Metas::Escopo).
RSpec.describe Crm::Pipeline do
  describe 'arquivado, nos Números e Relatórios' do
    let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
    let(:admin) { create(:user, account: account, role: :administrator, name: 'Marcos') }
    let(:ativo) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
    let(:antigo) { create_crm_pipeline(account: account, user: admin, name: 'Antigo') }
    let(:mes) { Crm::Numeros::Mes.new(account: account) }

    around { |example| travel_to(Time.utc(2026, 10, 19, 15, 0)) { example.run } }

    def venda((pipeline, stage), value_cents)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: admin, title: 'Venda', value_cents: value_cents)
      Crm::Cards::Closer.new(card: card, actor: admin, result: 'won').perform
    end

    def acesso = Crm::Access::VisiblePipelines.new(user: admin, account: account)

    before do
      allow(Crm::Ai::ExchangeRate).to receive(:current).and_return(rate: 5.0, fetched_at: nil)
      venda(ativo, 10_000)
      venda(antigo, 90_000)
      antigo.first.archived!
    end

    it 'Só eu: não conta a venda do funil arquivado' do
      resultado = Crm::Numeros::SoEu.new(account: account, user: admin, mes: mes, acesso: acesso).perform

      expect(resultado[:topo]).to include(feito: 100.0, fechadas: 1)
    end

    it 'Equipe: não lista nem soma o funil arquivado' do
      Current.account = account
      resultado = Crm::Numeros::Equipe.new(account: account, user: admin, mes: mes, acesso: acesso,
                                           perfil: { dono: true, custo: true, leitura: false }).perform

      expect(resultado[:topo]).to include(feito: 100.0, fechadas: 1)
    end

    it 'Relatórios: sem funil pedido, nunca abre o arquivado' do
      antigo.first.update_columns(is_default: true) # rubocop:disable Rails/SkipsModelValidations

      resumo = Crm::Reports::Summary.new(account: account).perform

      expect(resumo[:pipeline]).to include(id: ativo.first.id)
    end
  end
end
