require 'rails_helper'

# #3100 — as telas do cartão fidelidade: o cartão da conta (ler, criar, mudar, pausar e ligar), os números do painel, o
# cartão da pessoa na ficha (ler, o histórico, dar o prêmio, o ajuste à mão) e o filtro "perto do prêmio" da Lista de
# Relacionamentos. No OSS, `fidelidade_view` e `fidelidade_manage` respondem administrator? (a função personalizada está
# em spec/enterprise/requests/fidelidade_access_spec.rb). Dar o prêmio é de quem pode mexer no contato (D1).
RSpec.describe 'Fidelidade', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:agora) { Time.zone.parse('2026-11-23 12:00:00') }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let!(:ana) { create(:contact, account: account, name: 'Ana Albuquerino') }

  before { travel_to(agora) }

  def pedir(verbo, caminho, quem: admin, params: {}, headers: {})
    public_send(verbo, "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token.merge(headers), as: :json)
  end

  def criar_programa(**mudancas)
    Fidelidade::Programa.create!({ account: account, tipo: 'carimbos', a_cada_centavos: 5_000, ganha: 1, meta: 10,
                                   premio: 'Uma lavagem grátis', ligado: true, ligado_em: agora - 1.day }.merge(mudancas))
  end

  def dar_carimbos(pessoa, quantos, programa)
    Fidelidade::Carteira.new(programa, pessoa).entrar(tipo: 'presente', quantos: quantos, motivo: 'Aniversário')
  end

  describe 'fidelidade/programa' do
    let(:regras) { { tipo: 'carimbos', a_cada: 50, ganha: 1, meta: 10, premio: 'Uma lavagem grátis', validade_meses: 6 } }

    it 'sem cartão, devolve null' do
      pedir(:get, 'fidelidade/programa')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_nil
    end

    it 'cria o cartão ligado, valendo de agora em diante, com "a cada" em reais' do
      pedir(:put, 'fidelidade/programa', params: { programa: regras })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('tipo' => 'carimbos', 'a_cada' => 50, 'meta' => 10, 'ligado' => true,
                                              'ligado_em' => agora.to_i, 'validade_meses' => 6)
      expect(Fidelidade::Programa.da_conta(account)).to have_attributes(a_cada_centavos: 5_000, created_by: admin)
    end

    it 'mudar as regras não recomeça a contagem' do
      programa = criar_programa

      pedir(:put, 'fidelidade/programa', params: { programa: regras.merge(meta: 12) })

      expect(programa.reload).to have_attributes(meta: 12, ligado_em: agora - 1.day)
    end

    it 'regra errada responde 422 com o campo' do
      pedir(:put, 'fidelidade/programa', params: { programa: regras.merge(meta: 50) })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to have_key('meta')
      expect(Fidelidade::Programa.count).to eq(0)
    end

    it 'pausar guarda os carimbos; ligar de novo recomeça a contagem agora' do
      programa = criar_programa

      pedir(:patch, 'fidelidade/programa', params: { ligado: false })
      expect(programa.reload).to have_attributes(ligado: false, ligado_em: agora - 1.day)

      travel 2.days
      pedir(:patch, 'fidelidade/programa', params: { ligado: true })
      expect(programa.reload).to have_attributes(ligado: true, ligado_em: Time.current)
    end

    it 'o atendente sem a permissão não lê nem muda' do
      criar_programa

      pedir(:get, 'fidelidade/programa', quem: agente)
      expect(response).to have_http_status(:unauthorized)
      pedir(:put, 'fidelidade/programa', quem: agente, params: { programa: regras })
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'fidelidade/resumo' do
    it 'conta quem tem carimbos, quem está perto, os completos e os prêmios de 30 dias' do
      programa = criar_programa
      bruno = create(:contact, account: account, name: 'Bruno Brandolim')
      carla = create(:contact, account: account, name: 'Carla Carvalhedo')
      dar_carimbos(ana, 3, programa)
      dar_carimbos(bruno, 9, programa)
      dar_carimbos(carla, 21, programa)
      Fidelidade::DarPremio.new(programa, carla, admin).call

      pedir(:get, 'fidelidade/resumo')

      expect(response.parsed_body).to eq('com_saldo' => 3, 'perto' => 1, 'completos' => 1, 'premios_30d' => 1)
    end
  end

  describe 'relacionamentos/pessoas/:id/fidelidade' do
    let!(:programa) { criar_programa(validade_meses: 3) }

    it 'sem cartão na conta, devolve null' do
      programa.destroy!

      pedir(:get, "relacionamentos/pessoas/#{ana.id}/fidelidade", quem: agente)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_nil
    end

    it 'o atendente lê o cartão, o saldo, o que vence e os últimos movimentos' do
      Fidelidade::Carteira.new(programa, ana).entrar(tipo: 'presente', quantos: 2, agora: agora - 80.days, motivo: 'Indicação')
      dar_carimbos(ana, 5, programa)

      pedir(:get, "relacionamentos/pessoas/#{ana.id}/fidelidade", quem: agente)

      corpo = response.parsed_body
      expect(corpo).to include('tem' => 7, 'historico_total' => 2, 'cupons' => [])
      expect(corpo['programa']).to include('meta' => 10, 'premio' => 'Uma lavagem grátis')
      expect(corpo['vencem']).to eq('quantos' => 2, 'em' => (agora - 80.days + 3.months).to_i)
      expect(corpo['historico'].first).to include('tipo' => 'presente', 'quantos' => 5, 'motivo' => 'Aniversário', 'valor' => nil)
    end

    it 'o histórico inteiro vem por página' do
      3.times { dar_carimbos(ana, 1, programa) }

      pedir(:get, "relacionamentos/pessoas/#{ana.id}/fidelidade/movimentos", params: { pagina: 1 })

      expect(response.parsed_body).to include('total' => 3, 'pagina' => 1)
      expect(response.parsed_body['itens'].size).to eq(3)
    end

    it 'não acha pessoa de outra conta' do
      outra = create(:contact, account: create(:account))

      pedir(:get, "relacionamentos/pessoas/#{outra.id}/fidelidade")

      expect(response).to have_http_status(:not_found)
    end

    describe 'POST premios' do
      it 'o atendente dá o prêmio com o cartão completo, e fica anotado quem deu' do
        dar_carimbos(ana, 12, programa)

        pedir(:post, "relacionamentos/pessoas/#{ana.id}/fidelidade/premios", quem: agente)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body['movimento']).to include('tipo' => 'premio', 'quantos' => -10, 'quem' => agente.name)
        expect(response.parsed_body['fidelidade']).to include('tem' => 2)
      end

      it 'sem o cartão completo, responde 422 e não tira nada' do
        dar_carimbos(ana, 9, programa)

        pedir(:post, "relacionamentos/pessoas/#{ana.id}/fidelidade/premios", quem: agente)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'saldo_insuficiente')
        expect(Fidelidade::Saldo.find_by(contact_id: ana.id).saldo).to eq(9)
      end

      it 'o mesmo toque repetido (mesma chave) não tira a meta duas vezes' do
        dar_carimbos(ana, 20, programa)
        chave = { 'Idempotency-Key' => 'premio-1' }

        2.times { pedir(:post, "relacionamentos/pessoas/#{ana.id}/fidelidade/premios", quem: agente, headers: chave) }

        expect(response).to have_http_status(:created)
        expect(response.headers['Idempotency-Replayed']).to eq('true')
        expect(Fidelidade::Saldo.find_by(contact_id: ana.id).saldo).to eq(10)
      end
    end

    describe 'POST ajustes' do
      it 'o administrador dá ou tira à mão, com o motivo' do
        pedir(:post, "relacionamentos/pessoas/#{ana.id}/fidelidade/ajustes", params: { quantos: 3, motivo: 'Compra no papel' })

        expect(response).to have_http_status(:created)
        expect(response.parsed_body['movimento']).to include('tipo' => 'ajuste', 'quantos' => 3, 'motivo' => 'Compra no papel')
      end

      it 'o atendente sem fidelidade_manage não ajusta' do
        pedir(:post, "relacionamentos/pessoas/#{ana.id}/fidelidade/ajustes", quem: agente, params: { quantos: 3 })

        expect(response).to have_http_status(:unauthorized)
        expect(Fidelidade::Movimento.count).to eq(0)
      end

      it 'recusa zero e tirar mais do que a pessoa tem', :aggregate_failures do
        pedir(:post, "relacionamentos/pessoas/#{ana.id}/fidelidade/ajustes", params: { quantos: 0 })
        expect(response).to have_http_status(:unprocessable_entity)

        pedir(:post, "relacionamentos/pessoas/#{ana.id}/fidelidade/ajustes", params: { quantos: -1 })
        expect(response.parsed_body).to eq('error' => 'saldo_insuficiente')
      end
    end
  end

  describe 'filtro fidelidade da Lista de Relacionamentos' do
    let!(:programa) { criar_programa }
    let!(:bruno) { create(:contact, account: account, name: 'Bruno Brandolim', email: 'bruno@exemplo.com') }
    let!(:carla) { create(:contact, account: account, name: 'Carla Carvalhedo', email: 'carla@exemplo.com') }

    before do
      ana.update!(email: 'ana@exemplo.com')
      dar_carimbos(ana, 3, programa)
      dar_carimbos(bruno, 8, programa)
      dar_carimbos(carla, 10, programa)
    end

    def nomes(valor)
      get "#{base}/relacionamentos/pessoas", params: { filtros: { fidelidade: valor } }, headers: admin.create_new_auth_token
      response.parsed_body['itens'].pluck('name')
    end

    it 'perto: falta até 20% da meta, sem ter completado; completo: já juntou a meta', :aggregate_failures do
      expect(nomes('perto')).to eq(['Bruno Brandolim'])
      expect(nomes('completo')).to eq(['Carla Carvalhedo'])
    end

    it 'recusa valor que o filtro não conhece' do
      get "#{base}/relacionamentos/pessoas", params: { filtros: { fidelidade: 'quase' } }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
