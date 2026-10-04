require 'rails_helper'

# As pendências do Guia (#943): a leitura que a vigia padrão mede. Só leitura, só administrador, cada um
# vê as dele, e nada de texto da conversa.
RSpec.describe 'Guia da Plataforma — pendências do Guia', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:outro_admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:caminho) { "/api/v1/accounts/#{account.id}/autonomia/pendencias_do_guia" }

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  def execucao!(user, pendencias: ['labels'], conta: account, **extra)
    Autonomia::Guide::Execucao.create!(
      account: conta, user: user, pendencias: pendencias,
      passos: [{ 'acao' => 'DELETE labels/:id', 'frase' => 'Vou apagar a etiqueta da Maria', 'ok' => true }], **extra
    )
  end

  it 'lista só as execuções da pessoa com pendência, dentro do desfazer, sem a frase', :aggregate_failures do
    com = execucao!(admin)
    execucao!(admin, pendencias: [])
    execucao!(admin, expira_em: 1.minute.ago)
    execucao!(outro_admin)
    execucao!(admin, conta: create(:account))

    get caminho, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    itens = response.parsed_body['pendencias']
    expect(itens.pluck('id')).to eq([com.id])
    expect(itens.first).to include('acoes' => ['DELETE labels/:id'], 'pendencias' => ['labels'])
    expect(response.body).not_to include('Maria')
  end

  it '`horas` deixa só as mais recentes' do
    execucao!(admin, created_at: 30.hours.ago)
    recente = execucao!(admin, created_at: 2.hours.ago)

    get caminho, params: { horas: 24 }, headers: admin.create_new_auth_token

    expect(response.parsed_body['pendencias'].pluck('id')).to eq([recente.id])
  end

  it 'agente comum não lê' do
    get caminho, headers: agente.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'entra no catálogo do Guia, fora de `autonomia/guide/` (D3)' do
    catalogo = Autonomia::Guide::Consulta.new(account: account, user: admin).catalogo

    expect(catalogo).to include('autonomia/pendencias_do_guia')
  end

  it 'a vigia padrão mede a contagem pela leitura, como quem a criou', :aggregate_failures do
    dados = Autonomia::Guide::VigiasPadrao.todas.find { |vigia| vigia['leitura']['rota'] == 'autonomia/pendencias_do_guia' }
    vigia = Autonomia::Guide::Vigia.create!(dados.merge('account' => account, 'criado_por' => admin, 'origem' => 'padrao'))
    2.times { execucao!(admin) }

    resposta = Autonomia::Guide::Consulta.new(account: account, user: admin).ler_cru(vigia.leitura['rota'], vigia.leitura['parametros'])
    resultado = Autonomia::Guide::Medida.new(vigia.medida).de(JSON.parse(resposta.corpo))

    expect(resultado.valor).to eq(2)
    expect(vigia.cruzou?(resultado.valor)).to be(true)
  end
end
