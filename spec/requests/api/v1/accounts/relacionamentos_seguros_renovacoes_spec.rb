require 'rails_helper'

# E5 (#2898) — "Ajustar renovações": ler e guardar onde ficam as renovações da conta. A recusa é um código em `error`, e
# o corpo nunca repete o que foi mandado. A metade de função personalizada fica em
# spec/enterprise/requests/relacionamentos/seguros_renovacao_spec.rb. Tudo fictício.
RSpec.describe 'Carteira de seguros: ajustar renovações', type: :request do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:caminho) { "/api/v1/accounts/#{account.id}/relacionamentos/seguros/renovacoes" }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Renovação') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }

  before { travel_to(agora) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def ler(quem: admin, **params)
    get caminho, params: params, headers: quem.create_new_auth_token
  end

  def guardar(dados, quem: admin)
    put caminho, params: dados, headers: quem.create_new_auth_token, as: :json
  end

  def config
    Carteira::RenovacaoConfig.find_by(account_id: account.id)
  end

  def recusa
    [response.status, response.parsed_body]
  end

  describe 'ler' do
    it 'a conta que ainda não escolheu vem com o padrão, sem funil, e nada é gravado' do
      etapa
      ler

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'ajustes' => { 'funilId' => nil, 'etapaId' => nil, 'dias' => 60, 'mensagens' => 'mandar' },
        'funis' => [{ 'id' => funil.id, 'nome' => 'Renovação', 'etapas' => [{ 'id' => etapa.id, 'nome' => 'Novo Lead' }] }],
        'vencimentos' => [], 'semPermissao' => false, 'exemplo' => nil,
        'aggerLigado' => false, 'cotaSozinha' => false, 'cotaSemConversa' => false, 'agente' => nil
      )
      expect(config).to be_nil
    end

    it 'traz as escolhas guardadas, em quantos dias cada seguro que ainda vale termina e o exemplo das prévias' do
      create(:carteira_renovacao_config, account: account, pipeline: funil, stage: etapa, dias_antes: 45, mensagens: 'nao_mandar')
      criar_apolice(marina, numero: 'EX-000002', tipo: 'residencial', fim_vigencia: hoje + 90)
      criar_apolice(marina, numero: 'EX-000001', tipo: 'auto', fim_vigencia: hoje)
      criar_apolice(marina, numero: 'EX-000003', fim_vigencia: hoje - 1)
      criar_apolice(marina, numero: 'EX-000004', fim_vigencia: hoje + 10, cancelado_em: agora)

      ler

      expect(response.parsed_body).to include(
        'ajustes' => { 'funilId' => funil.id, 'etapaId' => etapa.id, 'dias' => 45, 'mensagens' => 'nao_mandar' },
        'vencimentos' => [0, 90], 'exemplo' => { 'nome' => 'Marina', 'tipo' => 'auto', 'termina' => '2026-11-12' }
      )
    end

    it 'atende quem só vê contatos, avisando que não pode mudar' do
      ler(quem: agente)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['semPermissao']).to be(true)
    end

    it 'sem o CRM não há funil para escolher' do
      etapa
      with_modified_env(CRM_KANBAN_ENABLED: 'false') { ler }

      expect(response.parsed_body['funis']).to eq([])
    end

    it 'recusa parâmetro que a leitura não conhece' do
      ler(pagina: 2)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'guardar' do
    it 'guarda o funil, a etapa, os dias e as mensagens, com quem escolheu, e devolve os ajustes' do
      guardar({ funilId: funil.id, etapaId: etapa.id, dias: 30, mensagens: 'nao_mandar' })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('funilId' => funil.id, 'etapaId' => etapa.id, 'dias' => 30, 'mensagens' => 'nao_mandar')
      expect(config).to have_attributes(pipeline_id: funil.id, stage_id: etapa.id, dias_antes: 30, mensagens: 'nao_mandar', user_id: admin.id)
    end

    it 'só muda o que veio, e a conta continua com uma linha só' do
      guardar({ funilId: funil.id, etapaId: etapa.id })
      guardar({ dias: '15' })

      expect(response.parsed_body).to eq('funilId' => funil.id, 'etapaId' => etapa.id, 'dias' => 15, 'mensagens' => 'mandar')
      expect(Carteira::RenovacaoConfig.where(account_id: account.id).count).to eq(1)
    end

    it 'funil e etapa nulos tiram a escolha' do
      create(:carteira_renovacao_config, account: account, pipeline: funil, stage: etapa)

      guardar({ funilId: nil, etapaId: nil })

      expect(response.parsed_body).to include('funilId' => nil, 'etapaId' => nil)
      expect(config).not_to be_escolhida
    end

    it 'recusa o funil que não existe, o de outra conta, o arquivado e o funil sem a etapa junto' do
      outra = conta_com_carteira
      de_fora, etapa_de_fora = create_crm_pipeline(account: outra, user: create(:user, account: outra), name: 'De fora')
      arquivado, etapa_do_arquivado = create_crm_pipeline(account: account, user: admin, name: 'Antigo')
      arquivado.update!(status: :archived)
      tentativas = [{ funilId: 0, etapaId: etapa.id }, { funilId: de_fora.id, etapaId: etapa_de_fora.id },
                    { funilId: arquivado.id, etapaId: etapa_do_arquivado.id }, { funilId: funil.id }, { funilId: 'abc', etapaId: etapa.id }]

      respostas = tentativas.map do |dados|
        guardar(dados)
        recusa
      end

      expect(respostas).to all(eq([422, { 'error' => 'funil_desconhecido' }]))
      expect(config).to be_nil
    end

    it 'recusa a etapa de outro funil' do
      _outro, etapa_de_outro = create_crm_pipeline(account: account, user: admin, name: 'Vendas')

      guardar({ funilId: funil.id, etapaId: etapa_de_outro.id })

      expect(recusa).to eq([422, { 'error' => 'etapa_de_outro_funil' }])
      expect(config).to be_nil
    end

    it 'recusa dias que não são inteiro de 1 a 3650 e mensagens fora da lista, sem repetir o que veio' do
      dias = [0, -3, 1.5, 'dez', '', nil, 3651].map do |valor|
        guardar({ dias: valor })
        recusa
      end
      guardar({ mensagens: 'talvez' })

      expect(dias).to all(eq([422, { 'error' => 'dias_invalidos' }]))
      expect(recusa).to eq([422, { 'error' => 'mensagens_invalidas' }])
      expect(config).to be_nil
    end

    it 'recusa campo que não conhece e campo em formato errado' do
      respostas = [{ dias: 30, outro: 1 }, { dias: [30] }].map do |dados|
        guardar(dados)
        recusa
      end

      expect(respostas).to all(eq([422, { 'error' => 'pedido_invalido' }]))
      expect(config).to be_nil
    end

    it 'só administrador guarda: o agente comum recebe 401' do
      guardar({ dias: 30 }, quem: agente)

      expect(response).to have_http_status(:unauthorized)
      expect(config).to be_nil
    end
  end

  describe 'em toda rota' do
    it 'responde 401 sem login' do
      get caminho
      sem_login_ao_ler = response.status
      put caminho, params: { dias: 30 }, as: :json

      expect([sem_login_ao_ler, response.status]).to eq([401, 401])
    end

    it 'responde 404 sem a carteira: chave desligada ou conta que não é corretora de seguros' do
      comum = create(:account)
      comum.enable_features!('relacionamentos_novo', 'carteira_seguros')
      dono = create(:user, account: comum, role: :administrator)
      account.disable_features!('carteira_seguros')

      respostas = [-> { ler }, -> { guardar({ dias: 30 }) },
                   -> { get "/api/v1/accounts/#{comum.id}/relacionamentos/seguros/renovacoes", headers: dono.create_new_auth_token }].map do |pedir|
        pedir.call
        response.status
      end

      expect(respostas).to eq([404, 404, 404])
      expect(Carteira::RenovacaoConfig.count).to eq(0)
    end

    it 'cada conta só lê e só muda a própria escolha' do
      outra = conta_com_carteira
      dona = create(:user, account: outra, role: :administrator)
      create(:carteira_renovacao_config, account: account, pipeline: funil, stage: etapa, dias_antes: 45)

      da_outra = "/api/v1/accounts/#{outra.id}/relacionamentos/seguros/renovacoes"

      get da_outra, headers: dona.create_new_auth_token
      lido = response.parsed_body
      put da_outra, params: { funilId: funil.id, etapaId: etapa.id }, headers: dona.create_new_auth_token, as: :json

      expect(lido).to include('ajustes' => { 'funilId' => nil, 'etapaId' => nil, 'dias' => 60, 'mensagens' => 'mandar' }, 'funis' => [])
      expect(recusa).to eq([422, { 'error' => 'funil_desconhecido' }])
      expect(config).to have_attributes(dias_antes: 45, pipeline_id: funil.id)
      expect(Carteira::RenovacaoConfig.where(account_id: outra.id)).to be_empty
    end
  end
end
