require 'rails_helper'

# #3097 — as compras na Lista de Relacionamentos e na ficha: o resumo da pessoa, os grupos de compra, os filtros, as
# ordens, o quanto cada grupo comprou e as faixas da conta. O valor só vai para quem vê valor de venda
# (Crm::ValorDeVenda). A regra do grupo e do disparo está em spec/services/relacionamentos/compras/recalcular_spec.rb.
RSpec.describe 'Compras na Lista de Relacionamentos', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:agora) { Time.zone.parse('2026-11-21 12:00:00') }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let!(:ana) { pessoa('Ana Albuquerino') }
  let!(:bruno) { pessoa('Bruno Brandolim') }
  let!(:carla) { pessoa('Carla Carvalhedo') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    compra(ana, dias: 40, reais: 300)
    compra(ana, dias: 10, reais: 200)
    compra(bruno, dias: 100, reais: 900)
    Relacionamentos::Compras::Recalcular.new(account, disparar: false).call
  end

  def pessoa(nome) = create(:contact, account: account, name: nome, contact_type: :lead)

  def compra(quem, dias:, reais:)
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: quem, title: 'Pedido', value_cents: reais * 100,
                              status: :won).tap { |card| card.update!(closed_at: agora - dias.days) }
  end

  def ler(caminho, quem: agente, **params)
    get "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token
  end

  # Quem não vê valor de venda: a função personalizada sem sales_value_view (a regra está em Crm::ValorDeVenda, com
  # spec próprio); aqui só o que a lista faz com a resposta dela.
  def sem_valor
    allow(Crm::ValorDeVenda).to receive(:ve?).and_return(false)
    agente
  end

  describe 'GET pessoas/:id/compras' do
    it 'devolve o resumo, o grupo e as faixas da conta' do
      ler("pessoas/#{ana.id}/compras")

      expect(response.parsed_body).to eq(
        'quantas' => 2, 'ultima_em' => (agora - 10.days).to_i, 'intervalo_medio_dias' => 30.0, 'grupo' => 'compra_fieis',
        'por_moeda' => [{ 'moeda' => 'BRL', 'total' => 500.0, 'quantas' => 2 }],
        'faixas' => { 'campeao_compras' => 4, 'campeao_dias' => 30, 'em_risco_dias' => 90, 'perdido_dias' => 180 }
      )
    end

    it 'devolve null para quem nunca comprou' do
      ler("pessoas/#{carla.id}/compras")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_nil
    end

    it 'não manda o valor para quem não vê valor de venda' do
      ler("pessoas/#{ana.id}/compras", quem: sem_valor)

      expect(response.parsed_body).to include('quantas' => 2, 'por_moeda' => nil)
    end
  end

  describe 'a lista' do
    it 'conta cada grupo de compra e o quanto cada um comprou' do
      ler('pessoas/contagens')

      expect(response.parsed_body).to include('compra_fieis' => 1, 'compra_em_risco' => 1, 'compra_nunca' => 1)
      expect(response.parsed_body['valores_de_compra']).to eq(
        'compra_fieis' => [{ 'moeda' => 'BRL', 'total' => 500.0 }], 'compra_em_risco' => [{ 'moeda' => 'BRL', 'total' => 900.0 }],
        'todos' => [{ 'moeda' => 'BRL', 'total' => 1400.0 }]
      )
    end

    it 'abre o grupo de compra e manda o resumo de cada pessoa da linha' do
      ler('pessoas', grupo: 'compra_em_risco')

      expect(response.parsed_body['itens'].pluck('name')).to eq(['Bruno Brandolim'])
      expect(response.parsed_body['itens'].first['compras']).to include('quantas' => 1, 'grupo' => 'compra_em_risco')
    end

    it 'filtra por compras e pelo total' do
      { { compras: 'nunca' } => ['Carla Carvalhedo'], { compras: 'ja_comprou' } => ['Ana Albuquerino', 'Bruno Brandolim'],
        { compras: 'ultimos_30' } => ['Ana Albuquerino'], { total_acima: '600' } => ['Bruno Brandolim'] }.each do |filtros, nomes|
        ler('pessoas', filtros: filtros, ordem: 'nome')

        expect(response.parsed_body['itens'].pluck('name')).to eq(nomes), filtros.to_s
      end
    end

    it 'ordena por compra, com quem nunca comprou no fim' do
      { 'mais_tempo_sem_comprar' => %w[Bruno Ana Carla], 'compra_mais_recente' => %w[Ana Bruno Carla],
        'mais_comprou' => %w[Bruno Ana Carla], 'menos_comprou' => %w[Ana Bruno Carla] }.each do |ordem, nomes|
        ler('pessoas', ordem: ordem)

        expect(response.parsed_body['itens'].map { |item| item['name'].split.first }).to eq(nomes), ordem
      end
    end

    it 'recusa o valor de filtro que a lista não conhece' do
      ler('pessoas', filtros: { compras: 'ontem' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'compras desconhecido: ontem')
    end

    it 'não dá o filtro nem a ordem por valor a quem não vê valor de venda, e tira o valor das contagens' do
      quem = sem_valor

      ler('pessoas', quem: quem, filtros: { total_acima: '100' })
      expect(response).to have_http_status(:unauthorized)
      ler('pessoas', quem: quem, ordem: 'mais_comprou')
      expect(response).to have_http_status(:unauthorized)
      ler('pessoas/contagens', quem: quem)
      expect(response.parsed_body).to include('compra_fieis' => 1)
      expect(response.parsed_body).not_to have_key('valores_de_compra')
    end
  end

  describe 'GET resumo' do
    it 'diz quantas pessoas estão em cada grupo da frase e quanto compraram' do
      ler('resumo')

      expect(response.parsed_body['compras']).to eq(
        'passou_da_hora' => { 'pessoas' => 0, 'por_moeda' => [] },
        'em_risco' => { 'pessoas' => 1, 'por_moeda' => [{ 'moeda' => 'BRL', 'total' => 900.0 }] },
        'campeoes' => { 'pessoas' => 0, 'por_moeda' => [] },
        'compraram' => { 'pessoas' => 2, 'por_moeda' => [{ 'moeda' => 'BRL', 'total' => 1400.0 }] }
      )
    end
  end

  describe 'grupos_de_compra' do
    let(:novas) { { campeao_compras: 3, campeao_dias: 20, em_risco_dias: 60, perdido_dias: 120 } }

    it 'lê as faixas do padrão e diz se quem pede vê valor de venda' do
      ler('grupos_de_compra')

      expect(response.parsed_body).to eq('campeao_compras' => 4, 'campeao_dias' => 30, 'em_risco_dias' => 90,
                                         'perdido_dias' => 180, 've_valores' => true)
    end

    it 'o administrador ajusta, e a conta é reagrupada sem disparar' do
      expect do
        patch "#{base}/grupos_de_compra", params: { faixas: novas }, headers: admin.create_new_auth_token
      end.to have_enqueued_job(Relacionamentos::Compras::RecalcularJob).with(account.id, nil, false)

      expect(response.parsed_body).to include('campeao_compras' => 3, 'perdido_dias' => 120)
      expect(Relacionamentos::Compras::Faixas.da_conta(account.reload)).to include('em_risco_dias' => 60)
    end

    it 'recusa faixas fora de ordem' do
      patch "#{base}/grupos_de_compra", params: { faixas: novas.merge(perdido_dias: 50) }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'perdido_dias precisa ser maior que em_risco_dias')
    end

    it 'o agente não ajusta' do
      patch "#{base}/grupos_de_compra", params: { faixas: novas }, headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
