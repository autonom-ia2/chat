require 'rails_helper'

# O painel "O que eu sei" do Guia (#933): cada pessoa vê as dela e as da
# corretora; a de outra pessoa é 404, e a da corretora só administrador muda.
RSpec.describe 'Guia da Plataforma — o que eu sei', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bruno) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/guide_memorias" }

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  def anotar(texto, user: nil, autor: user || admin)
    Autonomia::Guide::Memoria.create!(account: account, user: user, texto: texto, autor_id: autor.id)
  end

  describe 'GET' do
    it 'lista as da pessoa e as da corretora, no formato do contrato', :aggregate_failures do
      conversa = Autonomia::Guide::Conversa.create!(account: account, user: ana, titulo: 't')
      turno = Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: 'oi', tela: 'home')
      dela = Autonomia::Guide::Memoria.create!(account: account, user: ana, texto: 'Prefere respostas curtas', autor_id: ana.id,
                                               turno: turno)
      da_corretora = anotar('Funil do Zé = funil Comercial (id 12)')
      anotar('Do admin', user: admin)

      get base, headers: ana.create_new_auth_token, as: :json

      corpo = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(corpo['pessoais']).to eq([{ 'id' => dela.id, 'texto' => 'Prefere respostas curtas',
                                         'atualizada_em' => dela.updated_at.iso8601, 'aprendida_em_conversa' => conversa.id }])
      expect(corpo['corretora']).to eq([{ 'id' => da_corretora.id, 'texto' => 'Funil do Zé = funil Comercial (id 12)',
                                          'atualizada_em' => da_corretora.updated_at.iso8601, 'autor' => admin.name }])
      expect(corpo['pode_editar_corretora']).to be(false)
      expect(corpo['limites']).to eq('pessoais' => 12, 'corretora' => 20)
    end

    it 'diz ao administrador que ele pode editar as da corretora' do
      get base, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['pode_editar_corretora']).to be(true)
    end

    it 'não existe em conta sem o Guia' do
      allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(false)

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH' do
    it 'corrige a própria anotação', :aggregate_failures do
      dela = anotar('Prefere respostas curtas', user: ana)

      patch "#{base}/#{dela.id}", params: { texto: '  Prefere   tópicos ' }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(dela.reload.texto).to eq('Prefere tópicos')
      expect(response.parsed_body['texto']).to eq('Prefere tópicos')
    end

    it 'recusa texto vazio ou acima de 200 caracteres', :aggregate_failures do
      dela = anotar('Prefere respostas curtas', user: ana)

      patch "#{base}/#{dela.id}", params: { texto: 'x' * 201 }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      patch "#{base}/#{dela.id}", params: { texto: ' ' }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(dela.reload.texto).to eq('Prefere respostas curtas')
    end

    # AC-M3
    it 'na da corretora, só administrador: a Ana recebe 403', :aggregate_failures do
      da_corretora = anotar('Trabalhamos com Porto')

      patch "#{base}/#{da_corretora.id}", params: { texto: 'Mudei' }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(da_corretora.reload.texto).to eq('Trabalhamos com Porto')

      patch "#{base}/#{da_corretora.id}", params: { texto: 'Trabalhamos com Porto e Allianz' },
                                          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'DELETE' do
    it 'apaga a própria anotação' do
      dela = anotar('Prefere respostas curtas', user: ana)

      delete "#{base}/#{dela.id}", headers: ana.create_new_auth_token, as: :json

      expect(Autonomia::Guide::Memoria.exists?(dela.id)).to be(false)
    end

    it 'na da corretora, a Ana recebe 403' do
      da_corretora = anotar('Trabalhamos com Porto')

      delete "#{base}/#{da_corretora.id}", headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  # AC-M4 — a pessoal de outra pessoa se comporta como uma que não existe.
  it 'responde 404 ao Bruno em qualquer pedido sobre a anotação da Ana', :aggregate_failures do
    dela = anotar('Prefere respostas curtas', user: ana)

    get base, headers: bruno.create_new_auth_token, as: :json
    expect(response.parsed_body['pessoais']).to eq([])

    patch "#{base}/#{dela.id}", params: { texto: 'Invadi' }, headers: bruno.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    delete "#{base}/#{dela.id}", headers: bruno.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(dela.reload.texto).to eq('Prefere respostas curtas')
  end

  it 'não alcança a anotação de outra conta' do
    outra = create(:account)
    create(:account_user, account: outra, user: admin, role: :administrator)
    de_fora = Autonomia::Guide::Memoria.create!(account: outra, texto: 'De outra corretora', autor_id: admin.id)

    delete "#{base}/#{de_fora.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
