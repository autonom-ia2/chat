require 'rails_helper'

# #1823, F1a — nome livre das etiquetas: listar, gravar (upsert) e apagar, atrás da flag `etiquetas_do_whatsapp`.
RSpec.describe 'Nomes das etiquetas', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:etiqueta) { create(:label, account: account, title: 'novo_cliente') }
  let(:base) { "/api/v1/accounts/#{account.id}/nomes_de_etiquetas" }

  def gravar(label, nome, user: admin)
    put "#{base}/#{label.id}", params: { nome: nome }, headers: user.create_new_auth_token, as: :json
  end

  def listar(user: agente)
    get base, headers: user.create_new_auth_token, as: :json
  end

  context 'without the flag' do
    it 'responde 404 para ler, gravar e apagar, sem gravar nada' do
      listar(user: admin)
      expect(response).to have_http_status(:not_found)

      gravar(etiqueta, 'Novo Cliente')
      expect(response).to have_http_status(:not_found)

      delete "#{base}/#{etiqueta.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Etiquetas::Nome.count).to eq(0)
    end
  end

  context 'with the flag' do
    before { account.enable_features!('etiquetas_do_whatsapp') }

    it 'administrador grava, regrava o mesmo registro e o agente lê' do
      gravar(etiqueta, '  Novo Cliente  ')
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq('label_id' => etiqueta.id, 'nome' => 'Novo Cliente')

      gravar(etiqueta, 'Cliente novo 🔥')
      expect(Etiquetas::Nome.where(label: etiqueta).count).to eq(1)

      listar
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq([{ 'label_id' => etiqueta.id, 'nome' => 'Cliente novo 🔥' }])
      expect(etiqueta.reload.title).to eq('novo_cliente')
    end

    it 'administrador apaga o nome; a etiqueta fica' do
      gravar(etiqueta, 'Novo Cliente')

      delete "#{base}/#{etiqueta.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(Etiquetas::Nome.count).to eq(0)
      expect(Label.exists?(etiqueta.id)).to be(true)
    end

    it 'agente sem função lê, mas não grava nem apaga' do
      gravar(etiqueta, 'Novo Cliente')

      gravar(etiqueta, 'Outro nome', user: agente)
      expect(response).to have_http_status(:unauthorized)

      delete "#{base}/#{etiqueta.id}", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(Etiquetas::Nome.sole.nome).to eq('Novo Cliente')
    end

    it 'recusa nome em branco e nome com mais de 80 caracteres' do
      gravar(etiqueta, '   ')
      expect(response).to have_http_status(:unprocessable_entity)

      gravar(etiqueta, 'a' * 81)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Etiquetas::Nome.count).to eq(0)
    end

    it 'apagar a etiqueta apaga o nome junto (cascade)' do
      gravar(etiqueta, 'Novo Cliente')

      delete "/api/v1/accounts/#{account.id}/labels/#{etiqueta.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(Etiquetas::Nome.count).to eq(0)
    end

    it 'token de robô não acessa' do
      bot = create(:agent_bot, account: account)

      get base, headers: { api_access_token: bot.access_token.token }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    context 'with another account' do
      let(:outra_conta) { create(:account) }
      let(:etiqueta_de_fora) { create(:label, account: outra_conta, title: 'de_fora') }
      let(:admin_de_fora) { create(:user, account: outra_conta, role: :administrator) }

      before do
        outra_conta.enable_features!('etiquetas_do_whatsapp')
        Etiquetas::Nome.create!(account: outra_conta, label: etiqueta_de_fora, nome: 'De fora')
      end

      it 'não lista, não grava nem apaga nome de etiqueta de outra conta' do
        listar
        expect(response.parsed_body['payload']).to eq([])

        gravar(etiqueta_de_fora, 'Invadido')
        expect(response).to have_http_status(:not_found)

        delete "#{base}/#{etiqueta_de_fora.id}", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
        expect(Etiquetas::Nome.find_by(label: etiqueta_de_fora).nome).to eq('De fora')
      end

      it 'usuário de outra conta não entra nesta' do
        get base, headers: admin_de_fora.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
