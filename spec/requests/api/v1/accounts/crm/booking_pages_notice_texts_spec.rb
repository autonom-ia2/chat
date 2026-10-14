require 'rails_helper'

# Texto próprio dos avisos (#1354): salvar na página (com a conferência) e "Escrever com IA" (opções, nada salvo). A IA
# é sempre simulada: nenhum spec chama IA paga.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages notice texts', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:page) { create_booking_profile(account: account, host: admin) }
  let(:member) { "/api/v1/accounts/#{account.id}/crm/booking_pages/#{page.id}" }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:good) { 'Oi, {{cliente.primeiro_nome}}! Seu horário é {{horario.data_hora}}. Para mudar: {{horario.link_gestao}}. Até lá!' }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run }
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    user
  end

  def ai_answers(*texts, status: 'ok', pergunta: nil)
    opcoes = texts.map do |texto|
      { texto: texto, chaves_usadas: [], o_que_mudou: nil, categoria_prevista: nil, certeza_categoria: nil, motivo_categoria: nil }
    end
    allow(client).to receive(:create).and_return(
      text: { status: status, pergunta: pergunta, sugestoes: [], problemas_encontrados: [], opcoes: opcoes }.to_json
    )
  end

  describe 'PATCH com notice_texts' do
    def save(texts)
      patch member, params: { booking_page: { notice_texts: texts } }, headers: admin.create_new_auth_token, as: :json
    end

    it 'guarda o texto em metadata, sem tocar nos modelos, e devolve o texto padrão e os campos para a tela' do
      save('day_before' => good)

      expect(response).to have_http_status(:ok)
      expect(page.reload.notice_texts).to eq('day_before' => good)
      expect(page.notice_templates).to eq({})
      body = response.parsed_body['payload']
      expect(body['notice_texts']).to eq('day_before' => good)
      expect(body.dig('notice_text_setup', 'defaults', 'booked'))
        .to eq('Oi, {{cliente.primeiro_nome}}! Seu horário está marcado para {{horario.data_hora}}.')
      expect(body.dig('notice_text_setup', 'fields').pluck('label')).to include('Dia e hora do horário')
      expect(body.dig('notice_text_setup', 'stop_line')).to start_with('Para parar estes avisos:')
    end

    # #1517: sem o link o texto é aceito (o sistema manda o link no botão ou na linha fixa); sem o dia e a hora, não.
    it 'guarda texto sem link e recusa texto sem o dia e a hora, com a frase simples no idioma da conta' do
      save('booked' => 'Seu horário é {{horario.data_hora}}.')

      expect(response).to have_http_status(:ok)
      expect(page.reload.notice_texts).to eq('booked' => 'Seu horário é {{horario.data_hora}}.')

      save('day_before' => 'Mude em {{horario.link_gestao}}.')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 'notice_texts')).to eq(
        ['O texto do aviso "1 dia antes" precisa do dia e da hora.']
      )
      expect(page.reload.notice_texts).to eq('booked' => 'Seu horário é {{horario.data_hora}}.')
    end

    it 'texto vazio volta ao padrão e preserva o resto do metadata' do
      page.update!(notice_texts: { 'booked' => good, 'day_before' => good })
      page.update_columns(metadata: page.metadata.merge('logo_dark_source' => 'generated')) # rubocop:disable Rails/SkipsModelValidations

      save('booked' => '', 'day_before' => good)

      expect(page.reload.notice_texts).to eq('day_before' => good)
      expect(page.metadata['logo_dark_source']).to eq('generated')
    end
  end

  describe 'POST notice_text_suggestions' do
    let(:path) { "#{member}/notice_text_suggestions" }
    # #1517: a IA não põe o link (o sistema manda pelo botão ou pela linha fixa).
    let(:ai_good) { 'Oi, {{cliente.primeiro_nome}}! Seu horário é {{horario.data_hora}}. Até lá!' }

    def ask(user = admin, kind: 'day_before', tone: 'formal')
      post path, params: { kind: kind, tone: tone }, headers: user.create_new_auth_token, as: :json
    end

    it 'devolve as opções da IA para o aviso, sem salvar, pela feature aviso_redacao' do
      # A segunda põe o campo do link, que a IA não recebe mais: é descartada.
      ai_answers(ai_good, 'Olá! Seu horário é {{horario.data_hora}}. Confirme em {{horario.link_gestao}}, por favor.')

      ask

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']['options'].pick('text')).to eq(ai_good)
      expect(response.parsed_body['payload']['options'].first['keys']).to eq(%w[cliente.primeiro_nome horario.data_hora])
      expect(page.reload.notice_texts).to eq({})
      expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'aviso_redacao', max_retries: 0))
    end

    it 'manda à IA o que a página e a conta dizem e o tom escolhido, sem dado de cliente' do
      ai_answers(ai_good)

      ask

      expect(client).to have_received(:create) do |args|
        entrada = JSON.parse(args[:input])
        expect(entrada['tom']['escolha']).to eq('formal')
        expect(entrada['contexto']).to include('atendimento' => 'Conversa de 30 min', 'duracao_minutos' => 30, 'idioma' => 'pt_BR')
        expect(entrada['contexto']['empresa']).to eq(account.name)
        # #1517: a IA não exige mais o link (vai no botão ou na linha fixa).
        expect(entrada['chaves']['obrigatorias']).to eq(%w[horario.data_hora])
        expect(entrada['chaves']['permitidas'].pluck('chave')).not_to include('horario.link_gestao')
      end
    end

    it 'devolve só as opções que passam na conferência; nenhuma boa vira mensagem simples, nada salvo' do
      ai_answers('Oi! Mude em {{horario.link_gestao}}. Até lá!', ai_good)
      ask
      expect(response.parsed_body['payload']['options'].pluck('text')).to eq([ai_good])

      ai_answers('Oi! Mude em {{horario.link_gestao}}. Até lá!')
      ask
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('Não conseguimos escrever agora. Tente de novo ou escreva do seu jeito.')
    end

    it 'sem chave de IA: mensagem simples, sem chamar o modelo' do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))

      ask

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('Não conseguimos escrever agora. Tente de novo ou escreva do seu jeito.')
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'mostra a pergunta da IA quando ela precisa de mais informação' do
      ai_answers(status: 'precisa_mais_info', pergunta: 'O que é atendido nesta página?')

      ask

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('O que é atendido nesta página?')
    end

    it 'recusa aviso desconhecido' do
      ask(kind: 'whatever')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'só quem gerencia páginas (agendamento_manage) pede à IA' do
      ai_answers(ai_good)

      ask(role_user('agendamento_manage'))
      expect(response).to have_http_status(:ok)

      ask(role_user('agendamento_view'))
      expect(response).to have_http_status(:unauthorized)
    end

    it 'não alcança página de outra conta' do
      other_account = create(:account)
      other_page = create_booking_profile(account: other_account, host: create(:user, account: other_account))

      post "/api/v1/accounts/#{account.id}/crm/booking_pages/#{other_page.id}/notice_text_suggestions",
           params: { kind: 'booked' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end
  end
end
