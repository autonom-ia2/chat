require 'rails_helper'

# #2558 (parecer da Funções personalizadas): o Decisor que lê o card só manda ao Jev o anúncio de origem do formulário
# da Meta (formulário, anúncio, campanha) com a chave do responsável. No teste, a de quem testa; na rodada, a de quem
# salvou o Decisor por último (`salvo_por`). A função com automation_manage e sem meta_ads_view não lê o anúncio de
# volta pelo Decisor. O exemplo guardado nunca leva o anúncio, porque quem tem automation_view o lê.
RSpec.describe 'Anúncio de origem no Decisor (#2558)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/decisores" }
  let(:jev_url) { 'https://api.typesafe.ai/v1/systemone' }
  let(:inbox) { create(:inbox, account: account) }
  let(:contato) { create(:contact, account: account, name: 'Joana') }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contato) }
  let!(:mensagem) do
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: 'Quero saber o preço')
  end
  let(:identificadores) { ['Formulário Primavera', 'Carrossel Primavera', 'Campanha Outono', '120200000000000001'] }
  let(:decisor) { create(:autonomia_decisor, account: account, leituras: %w[card mensagens_recentes]) }
  let(:sem_chave) { pessoa_com(base_de_permissoes) }
  let(:com_chave) { pessoa_com(base_de_permissoes + %w[meta_ads_view]) }

  before do
    allow(TypesafeAi::Config).to receive_messages(api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    stub_request(:post, jev_url).to_return(
      status: 200,
      body: { model: 'jev-1.13.0', usage: { input_tokens: 500, output_tokens: 1 },
              answers: { decisao: { type: 'choice', choice: 'sim', confidence: 0.9 } } }.to_json
    )
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contato, primary_conversation: conversa,
                              title: 'Lead do formulário', metadata: { 'meta_lead_form' => origem })
  end

  def origem
    { 'form_id' => '880001', 'form_name' => 'Formulário Primavera', 'ad_id' => '120200000000000001', 'ad_name' => 'Carrossel Primavera',
      'campaign_name' => 'Campanha Outono', 'captured_at' => '2026-11-01T12:00:00Z' }
  end

  def base_de_permissoes = %w[automation_view automation_manage conversation_manage]

  def pessoa_com(permissoes)
    create(:user, account: account, role: :agent).tap do |usuario|
      usuario.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissoes))
      create(:inbox_member, user: usuario, inbox: inbox)
    end
  end

  # O que foi ao Jev, junto.
  def lido_pelo_jev = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map(&:body).join(' ')

  def testar(usuario)
    WebMock::RequestRegistry.instance.reset!
    post "#{base}/#{decisor.id}/teste", params: { conversation_ids: [conversa.id] }, headers: usuario.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['testados']).to eq(1)
    lido_pelo_jev
  end

  describe 'POST teste' do
    it 'sem meta_ads_view: o card vai ao Jev sem formulário, anúncio nem campanha' do
      lido = testar(sem_chave)

      expect(lido).to include('Lead do formulário', '2026-11-01T12:00:00Z')
      expect(lido).not_to include(*identificadores)
    end

    it 'administrador e função com meta_ads_view: o anúncio vai' do
      [admin, com_chave].each { |usuario| expect(testar(usuario)).to include('Carrossel Primavera', 'Campanha Outono') }
    end
  end

  it 'POST exemplos: o exemplo guardado nunca leva o anúncio, nem quando quem confirma o vê' do
    post "#{base}/#{decisor.id}/exemplos", params: { conversation_id: conversa.id, resposta: 'sim' }, headers: admin.create_new_auth_token,
                                           as: :json

    expect(response).to have_http_status(:ok)
    texto = decisor.reload.exemplos.first['texto']
    expect(texto).to include('Lead do formulário')
    expect(texto).not_to include(*identificadores)
  end

  describe 'a rodada do Decisor segue a chave de quem o salvou por último' do
    def rodar
      WebMock::RequestRegistry.instance.reset!
      Autonomia::DecisorDecisao.delete_all
      Autonomia::Decisores::Pergunta.new(decisor: decisor.reload, conversation: conversa, message: mensagem).decisao
      lido_pelo_jev
    end

    def salvar(usuario)
      patch "#{base}/#{decisor.id}", params: { instrucoes: 'Pedido de preço é lead.' }, headers: usuario.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(decisor.reload.salvo_por_id).to eq(usuario.id)
    end

    it 'função com automation_manage e sem meta_ads_view salva o Decisor: a rodada não lê o anúncio' do
      salvar(sem_chave)

      lido = rodar
      expect(lido).to include('Lead do formulário')
      expect(lido).not_to include(*identificadores)
    end

    it 'administrador ou função com meta_ads_view salva: a rodada lê o anúncio' do
      [admin, com_chave].each do |usuario|
        salvar(usuario)
        expect(rodar).to include('Carrossel Primavera')
      end
    end

    it 'Decisor sem ninguém (antigo) ou de quem saiu da conta não lê o anúncio' do
      expect(decisor.salvo_por_id).to be_nil
      expect(rodar).to include('Lead do formulário')
      expect(rodar).not_to include(*identificadores)

      salvar(com_chave)
      com_chave.account_users.find_by(account: account).destroy!
      expect(rodar).to include('Lead do formulário')
      expect(rodar).not_to include(*identificadores)
    end
  end

  # O texto livre (motivo da dúvida, campos extraídos, nota e mensagem da automação) quem lê é quem tem automation_view,
  # com ou sem meta_ads_view: nunca leva o anúncio, nem quando quem salvou o Decisor o vê. O modelo falso devolve o que
  # recebeu do card, então o anúncio, se fosse, voltaria escrito.
  describe 'texto livre escrito pela IA' do
    let(:decisor) do
      create(:autonomia_decisor, account: account, leituras: %w[card mensagens_recentes], salvo_por: com_chave,
                                 campos: [{ 'chave' => 'resumo', 'descricao' => 'Resumo do pedido', 'destino' => 'card.descricao' }])
    end
    let(:card) { account.crm_cards.find_by!(title: 'Lead do formulário') }

    before do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'credencial'))
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(modelo_falso)
    end

    def modelo_falso
      instance_double(Crm::Ai::ResponsesClient).tap do |falso|
        allow(falso).to receive(:create) do |**pedido|
          eco = eco_do_card(pedido[:input])
          resposta = pedido[:schema][:name] == 'decisor_duvida' ? { resposta: 'sim', seguro: false, motivo: eco } : { resumo: eco }
          { text: resposta.to_json }
        end
      end
    end

    # O trecho do card que chegou ao modelo, a partir do título.
    def eco_do_card(entrada)
      inicio = entrada.index('Lead do formulário')
      inicio ? entrada[inicio, 400] : 'sem card'
    end

    def decisoes_vistas_por(usuario)
      get "#{base}/#{decisor.id}/decisoes", headers: usuario.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      response.parsed_body['decisoes'].to_json
    end

    it 'controle: o modelo falso devolve o anúncio quando a leitura o leva' do
      decisao = create(:autonomia_decisor_decisao, decisor: decisor, conversation: conversa, message: mensagem, status: 'duvida')
      estado = Autonomia::Decisores::Estado.new(conversation: conversa, message: mensagem, leituras: decisor.leituras_efetivas, anuncio: true)

      expect(Autonomia::Decisores::Duvida.new(decisao).perguntar(estado).motivo).to include('Carrossel Primavera')
    end

    it 'motivo da dúvida que o Guia escreve: sem o anúncio' do
      decisao = create(:autonomia_decisor_decisao, decisor: decisor, conversation: conversa, message: mensagem, status: 'duvida')

      Autonomia::Decisores::DuvidaJob.perform_now(decisao.id)

      expect(decisao.reload).to have_attributes(status: 'esperando_pessoa')
      expect(decisao.motivo).to include('Lead do formulário')
      expect(decisoes_vistas_por(sem_chave)).not_to include(*identificadores)
    end

    it 'campos extraídos e o card escrito pelo Aplicador: sem o anúncio, mesmo com a decisão lendo o anúncio' do
      rule = create(:automation_rule, account: account, event_name: 'message_created', conditions: [],
                                      actions: [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] }])
      WebMock::RequestRegistry.instance.reset!

      Autonomia::Decisores::PerguntarJob.perform_now(rule.id, conversa.id, mensagem.id, 0)

      expect(lido_pelo_jev).to include('Carrossel Primavera')
      decisao = Autonomia::DecisorDecisao.find_by!(decisor: decisor, message: mensagem)
      expect(decisao.campos_extraidos['resumo']).to include('Lead do formulário', '2026-11-01T12:00:00Z')
      expect(decisoes_vistas_por(sem_chave)).not_to include(*identificadores)
      expect(card.reload.description).to include('Lead do formulário')
      expect(card.description).not_to include(*identificadores)
    end

    it 'passo de IA da automação: a leitura que ele monta não leva o anúncio' do
      # Autonomia::Automacao::ComIa#leitura: o Estado sem `anuncio`. O esquema da receita nem aceita a leitura `card`.
      conversa_lida = Autonomia::Decisores::Estado.new(conversation: conversa, leituras: %w[card mensagens_recentes]).conversa.to_json

      expect(conversa_lida).to include('Lead do formulário')
      expect(conversa_lida).not_to include(*identificadores)
    end
  end
end
