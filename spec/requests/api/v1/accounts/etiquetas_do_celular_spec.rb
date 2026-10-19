require 'rails_helper'

# #1823, F1b — leitura das etiquetas que vêm do WhatsApp do celular, atrás da flag `etiquetas_do_celular`.
RSpec.describe 'Etiquetas do celular', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, name: 'Atendimento WhatsApp') }
  let(:etiqueta) { create(:label, account: account, title: 'novo_cliente') }
  let(:base) { "/api/v1/accounts/#{account.id}/etiquetas_do_celular" }

  before do
    Etiquetas::DoCelular.create!(account: account, inbox: inbox, label: etiqueta, label_wa_id: '3', nome: 'Novo cliente 🔥',
                                 color_index: 4, criada_pelo_celular: true)
  end

  def listar(user: agente)
    get base, headers: user.create_new_auth_token, as: :json
  end

  it 'responde 404 sem a flag, mesmo com a flag do nome livre ligada' do
    account.enable_features!('etiquetas_do_whatsapp')

    listar

    expect(response).to have_http_status(:not_found)
  end

  context 'with the flag' do
    before { account.enable_features!('etiquetas_do_celular') }

    it 'o agente membro da caixa lista etiqueta, caixa e nome no celular' do
      create(:inbox_member, user: agente, inbox: inbox)

      listar

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq([{
                                                      'label_id' => etiqueta.id, 'inbox_id' => inbox.id,
                                                      'caixa' => 'Atendimento WhatsApp', 'nome_no_celular' => 'Novo cliente 🔥',
                                                      'color_index' => 4, 'criada_pelo_celular' => true
                                                    }])
    end

    it 'agente fora da caixa não vê o vínculo nem o nome da caixa; o administrador vê todas' do
      outra_caixa = create(:inbox, account: account, name: 'Caixa do financeiro')
      create(:inbox_member, user: agente, inbox: inbox)
      Etiquetas::DoCelular.create!(account: account, inbox: outra_caixa, label: etiqueta, label_wa_id: '9', nome: 'Pago')

      listar
      expect(response.parsed_body['payload'].pluck('inbox_id')).to eq([inbox.id])
      expect(response.body).not_to include('Caixa do financeiro')

      listar(user: create(:user, account: account, role: :agent))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq([])

      listar(user: create(:user, account: account, role: :administrator))
      expect(response.parsed_body['payload'].pluck('inbox_id')).to eq([inbox.id, outra_caixa.id])
    end

    it 'não mostra correspondência de outra conta' do
      create(:inbox_member, user: agente, inbox: inbox)
      outra = create(:account)
      Etiquetas::DoCelular.create!(account: outra, inbox: create(:inbox, account: outra),
                                   label: create(:label, account: outra, title: 'de_fora'), label_wa_id: '1', nome: 'De fora')

      listar

      expect(response.parsed_body['payload'].pluck('label_id')).to eq([etiqueta.id])
    end

    it 'usuário de outra conta não entra' do
      outra = create(:account)
      outra.enable_features!('etiquetas_do_celular')

      listar(user: create(:user, account: outra, role: :administrator))

      expect(response).to have_http_status(:unauthorized)
    end

    it 'token de robô não acessa' do
      bot = create(:agent_bot, account: account)

      get base, headers: { api_access_token: bot.access_token.token }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
