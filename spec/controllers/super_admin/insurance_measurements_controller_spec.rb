require 'rails_helper'

# TERMO 4 — A CONSULTA NÃO DEPENDE DE ENGENHEIRO. A operação abre a página, escolhe o período e lê
# os dois números por corretora. Sem token, sem `curl`, sem console.
RSpec.describe 'Super Admin Insurance Measurement', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:dezessete) { %w[1 3 4 5 7 8 11 12 19 20 26 44 46 47 48 50 55] }

  def cotacao!(handle:, criada_em: Time.current)
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Mia', agent_type: 'insurance_quote',
                                              status: :active, enabled: true, instruction: 'Cote.')
    conversa = create(:conversation, account: account, inbox: create(:inbox, account: account))
    Autonomia::Agents::ToolRun.create!(account: account, agent: agente, conversation_id: conversa.id,
                                       slug: Autonomia::Agents::Tools::Native::InsuranceQuote.slug,
                                       status: 'done', execution_key: SecureRandom.uuid,
                                       handle: handle, created_at: criada_em)
  end

  it 'exige super admin' do
    get '/super_admin/insurance_measurement'

    expect(response).to have_http_status(:redirect)
  end

  context 'when o super admin esta autenticado' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'mostra a corretora com os dois numeros' do
      # Arrange
      cotacao!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                         'entregues' => %w[1 3 4 5 7 8 11 12 19 20 26] })

      # Act
      get '/super_admin/insurance_measurement'

      # Assert
      expect(response).to have_http_status(:success)
      expect(response.body).to include(account.name)
      expect(response.body).to include('Seguradoras acionadas')
      expect(response.body).to include('>17<')
    end

    # TERMO 3 na tela: COTAÇÕES que viraram proposta e a soma dos códigos são DUAS colunas. Uma
    # cotação com duas propostas é uma cotação — a coluna da fatura não pode dobrar por causa da soma.
    it 'mostra cotações com proposta e propostas emitidas em colunas separadas' do
      cotacao!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                         Autonomia::Agents::Tools::Native::InsuranceQuote::PROPOSTAS_KEY => %w[8 3] })

      get '/super_admin/insurance_measurement'

      expect(response.body).to include('Cotações com proposta', 'Propostas emitidas')
      celulas = response.body.scan(%r{<td[^>]*>(\d+)</td>}).flatten
      expect(celulas).to eq(%w[1 17 0 1 2 0 0 0])
    end

    it 'aceita a janela pedida' do
      cotacao!(handle: { 'quote_id' => 'velha', 'seguradoras_acionadas' => dezessete }, criada_em: 40.days.ago)

      get '/super_admin/insurance_measurement', params: { from: 60.days.ago.to_date.to_s, to: Time.zone.today.to_s }

      expect(response.body).to include('>17<')
    end

    # Data ilegível não vira janela padrão em silêncio: a página avisa e não mostra número nenhum.
    it 'avisa em vez de escolher a janela sozinho' do
      cotacao!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete })

      get '/super_admin/insurance_measurement', params: { from: 'ontem' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Período inválido')
      expect(response.body).not_to include('>17<')
    end

    it 'nao inventa linha para corretora sem cotação' do
      get '/super_admin/insurance_measurement'

      expect(response.body).to include('Nenhuma cotação no período')
    end
  end
end
