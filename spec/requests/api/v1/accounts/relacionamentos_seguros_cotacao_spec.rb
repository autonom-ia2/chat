require 'rails_helper'

# E8 (#2901) — a cotação da renovação nas rotas da carteira: as escolhas em "Ajustar renovações" (quem cota, quem envia,
# quem responde e a caixa), o consumo do mês e o "Enviar" da proposta pelo card. A recusa é um código em `error`, e o
# corpo nunca repete o que foi mandado. Tudo fictício; a Meta é dublê.
RSpec.describe 'Carteira de seguros: cotação da renovação', type: :request do
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:ajustes_path) { "/api/v1/accounts/#{account.id}/relacionamentos/seguros/renovacoes" }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  # As escolhas vêm soltas (`guardar(quemCota: 'robo')`): no Ruby 3 elas chegam como keywords, junto de `quem:`.
  def guardar(quem: admin, **dados)
    put ajustes_path, params: dados, headers: quem.create_new_auth_token, as: :json
  end

  def config
    Carteira::RenovacaoConfig.find_by(account_id: account.id)
  end

  describe 'ajustar renovações' do
    it 'sem a chave da cotação: o formato é o da E5 e as escolhas da cotação são recusadas' do
      get ajustes_path, headers: admin.create_new_auth_token

      expect(response.parsed_body).to include('aggerLigado' => false, 'cotaSozinha' => false, 'cotaSemConversa' => false, 'agente' => nil)
      expect(response.parsed_body.keys).not_to include('cotacaoLiberada', 'caixas')
      expect(response.parsed_body['ajustes'].keys).to eq(%w[funilId etapaId dias])

      guardar(quemCota: 'robo')
      expect([response.status, response.parsed_body['error']]).to eq([422, 'cotacao_desligada'])
    end

    describe 'com a chave da cotação' do
      before { Carteira::Cotacao::Liberada.ligar!(account) }

      it 'lê as escolhas (padrão), o agente e as caixas do WhatsApp oficial com a Lia ligada ou não' do
        caixa
        create_crm_inbox(account: account, name: 'Caixa de API')
        agente = agente_de_cotacao(account)
        Autonomia::Agents::AgentInbox.create!(account: account, agent: agente, inbox: caixa, agent_bot: create(:agent_bot, account: account))

        get ajustes_path, headers: admin.create_new_auth_token

        expect(response.parsed_body).to include(
          'ajustes' => { 'funilId' => nil, 'etapaId' => nil, 'dias' => 60, 'quemCota' => 'ninguem', 'quemEnvia' => 'pessoa',
                         'quemResponde' => 'equipe', 'caixaId' => nil },
          'cotaSozinha' => true, 'cotaSemConversa' => false, 'agente' => 'Lia Exemplo', 'cotacaoLiberada' => true,
          'caixas' => [{ 'id' => caixa.id, 'nome' => 'WhatsApp oficial', 'liaLigada' => true, 'distribui' => true }]
        )
      end

      it 'guarda quem cota, quem envia, quem responde e a caixa' do
        agente_de_cotacao(account)
        caixa.update!(enable_auto_assignment: false)

        guardar(quemCota: 'lia', quemEnvia: 'sozinho', quemResponde: 'lia', caixaId: caixa.id)

        expect(response).to have_http_status(:ok)
        expect(config).to have_attributes(quem_cota: 'lia', quem_envia: 'sozinho', quem_responde: 'lia', inbox_id: caixa.id)
        expect(response.parsed_body).to include('quemCota' => 'lia', 'quemEnvia' => 'sozinho', 'quemResponde' => 'lia', 'caixaId' => caixa.id)

        guardar(caixaId: nil)
        expect(config.reload.inbox_id).to be_nil
      end

      it 'a Lia respondendo numa caixa que entrega toda conversa nova a alguém da equipe: recusa sem repetir o valor' do
        agente_de_cotacao(account)

        guardar(quemCota: 'robo', quemResponde: 'lia', caixaId: caixa.id)
        expect([response.status, response.parsed_body]).to eq([422, { 'error' => 'caixa_distribui' }])
        expect(config&.quem_responde).not_to eq('lia')

        guardar(quemCota: 'robo', quemResponde: 'equipe', caixaId: caixa.id)
        expect(response).to have_http_status(:ok)

        guardar(quemResponde: 'lia')
        expect(response.parsed_body).to eq('error' => 'caixa_distribui')

        caixa.update!(enable_auto_assignment: false)
        guardar(quemResponde: 'lia')
        expect(config.reload.quem_responde).to eq('lia')
      end

      it 'robô ou Lia sem o Agente de Cotação na conta: recusa com motivo próprio' do
        %w[robo lia].each do |quem|
          guardar(quemCota: quem)
          expect([response.status, response.parsed_body['error']]).to eq([422, 'sem_agente_de_cotacao'])
        end
        guardar(quemCota: 'ninguem')
        expect(response).to have_http_status(:ok)
      end

      it 'valor fora da lista e caixa que não é do WhatsApp oficial da conta: recusa sem repetir o valor' do
        guardar(quemEnvia: 'amanha<b>')
        expect(response.parsed_body).to eq('error' => 'escolha_invalida')

        guardar(caixaId: create_crm_inbox(account: account, name: 'Caixa de API').id)
        expect(response.parsed_body).to eq('error' => 'caixa_invalida')

        guardar(caixaId: caixa_oficial(create(:account)).id)
        expect(response.parsed_body).to eq('error' => 'caixa_invalida')
      end
    end
  end

  describe 'consumo do mês' do
    let(:consumo_path) { "/api/v1/accounts/#{account.id}/relacionamentos/seguros/cotacoes" }

    it 'sem a chave: 422 cotacao_desligada' do
      get consumo_path, headers: admin.create_new_auth_token

      expect(response.parsed_body).to eq('error' => 'cotacao_desligada')
    end

    it 'com a chave: só contagens, do dia 1º até hoje' do
      Carteira::Cotacao::Liberada.ligar!(account)
      travel_to(Time.utc(2026, 11, 17, 15))

      get consumo_path, headers: admin.create_new_auth_token

      expect(response.parsed_body).to eq('inicio' => '2026-11-01', 'fim' => '2026-11-17', 'cotacoes' => 0, 'seguradorasAcionadas' => 0,
                                         'seguradorasComPreco' => 0, 'daRenovacao' => 0)
    end
  end

  describe 'enviar a proposta pelo card' do
    let(:seguro) do
      criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', valor_centavos: 200_000,
                            fim_vigencia: 30.days.from_now.to_date)
    end
    let(:enviar_path) { "/api/v1/accounts/#{account.id}/relacionamentos/seguros/#{seguro.id}/enviar_proposta" }
    let(:pdf) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new('%PDF-1.4 exemplo'), filename: 'Proposta de renovação.pdf',
                                             content_type: 'application/pdf')
    end

    before do
      allow(Whatsapp::Templates::HeaderMedia).to receive(:dispatch_file)
        .and_return('media_url' => 'https://exemplo.test/proposta.pdf', 'media_name' => 'Proposta de renovação.pdf')
      aprovar_modelos(caixa, 'renovacao_algo_mudou', 'renovacao_proposta')
      ajustes = cotacao_ligada(account, user: admin, caixa: caixa, quem_envia: 'pessoa')
      por_em_renovacao(seguro, ajustes)
    end

    # A proposta pronta como a Carteira::Cotacao::Pronta guarda: a nota privada com o PDF e o passo da história.
    def proposta_pronta!
      conversa = Carteira::Cotacao::Envio.new(seguro.reload, config).conversa
      nota = conversa.messages.new(account_id: account.id, inbox_id: caixa.id, message_type: :outgoing, private: true, content: 'Proposta')
      nota.attachments.new(account_id: account.id, file_type: :file, file: pdf.signed_id)
      nota.save!
      Carteira::Cotacao.registrar(seguro, 'proposta_pronta', premio_centavos: 210_000, seguradora: 'Seguradora B', nota: nota.id)
    end

    def enviar(quem: admin)
      post enviar_path, headers: quem.create_new_auth_token, as: :json
    end

    def propostas
      Message.where(account_id: account.id).to_a.select { |m| Carteira::Cotacao.marca_de(m)['etapa'] == 'proposta' }
    end

    it 'modo pessoa: nada sai antes do clique; no clique sai pela caixa, com quem clicou, e o seguro volta com a cotação' do
      proposta_pronta!
      expect(propostas).to be_empty

      enviar

      expect(response).to have_http_status(:ok)
      expect(propostas.sole).to have_attributes(inbox_id: caixa.id, sender_id: admin.id, private: false)
      expect(seguro.eventos.find_by(tipo: 'proposta_enviada')).to have_attributes(user_id: admin.id)
      expect(response.parsed_body['cotacao']).to include('etapa' => 'proposta_enviada', 'podeEnviar' => false, 'variacaoPercentual' => 5.0)
    end

    it 'já enviada: recusa clara e não manda de novo' do
      proposta_pronta!
      enviar

      enviar

      expect([response.status, response.parsed_body['error']]).to eq([422, 'proposta_ja_enviada'])
      expect(propostas.size).to eq(1)
    end

    it 'sem proposta pronta: recusa' do
      enviar

      expect(response.parsed_body).to eq('error' => 'sem_proposta')
    end

    it 'o contato que recusou mensagens: não sai, fica na história e avisa a equipe' do
      proposta_pronta!
      Contact.where(id: marina.id).update_all(opted_out_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      enviar

      expect(response.parsed_body).to eq('error' => 'contato_recusou')
      expect(propostas).to be_empty
      expect(seguro.eventos.find_by(tipo: 'proposta_nao_saiu').valores).to include('motivo' => 'envio', 'detalhe' => 'contato_recusou')
    end
  end
end
