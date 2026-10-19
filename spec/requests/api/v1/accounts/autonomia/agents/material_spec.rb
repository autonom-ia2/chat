require 'rails_helper'

# #1426 (tema 4b) — a API das conferências e do autoteste do material: ler (problemas + autoteste), resolver um problema
# com a escolha da pessoa e pedir o autoteste. Fora da Fase 2 e na Lia, leitura vazia e ações recusadas. O save do
# agente pela API não escreve nem apaga as chaves do material.
RSpec.describe 'Autonomia agents - material', type: :request do
  include_context 'with material do agente'

  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }).tap { |conta| Autonomia::Agents::Fase2.ligar!(conta) }
  end
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:atendente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def ler(usuario = administrator)
    get "#{base}/material", headers: usuario.create_new_auth_token
  end

  it 'lê os problemas e o autoteste (nunca rodado: "nunca", porque há material aprovado)', :aggregate_failures do
    ficha = material('ficha.pdf', status: :failed, error: 'empty_extraction', trechos: [])
    material('cardapio.pdf')

    ler

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['problemas']).to eq([{ 'id' => "vazio-#{ficha.id}", 'tipo' => 'vazio', 'fontes' => [ficha.id],
                                                       'nome' => 'ficha.pdf' }])
    expect(response.parsed_body['autoteste']).to include('estado' => 'nunca', 'resultados' => [])
  end

  it 'mostra o resumo do autoteste pronto, sem o que a pessoa não precisa ver (resposta esperada, trechos)' do
    material('cardapio.pdf')
    itens = [{ 'pergunta' => 'Abre sábado?', 'origem' => 'material', 'veredito' => 'certo', 'esperado' => 'segredo',
               'trechos' => [{ 'id' => 1 }] },
             { 'pergunta' => 'Vende bolo?', 'origem' => 'fora', 'veredito' => 'recusou' }]
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', { 'rodada' => 'r', 'rodada_dos_itens' => 'r', 'estado' => 'pronto',
                                                                                'feitas' => 2, 'total' => 2, 'itens' => itens })

    ler

    expect(response.parsed_body['autoteste']).to eq(
      'estado' => 'pronto', 'quando' => nil, 'feitas' => 2, 'total' => 2, 'do_material' => 1, 'de_fora' => 1,
      'certas_do_material' => 1, 'certas_de_fora' => 1,
      'resultados' => [{ 'pergunta' => 'Abre sábado?', 'origem' => 'material', 'ok' => true },
                       { 'pergunta' => 'Vende bolo?', 'origem' => 'fora', 'ok' => true }]
    )
  end

  it 'rodando há mais que a validade aparece como parado (a tela oferece tentar de novo)' do
    material('cardapio.pdf')
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', { 'rodada' => 'r', 'estado' => 'rodando',
                                                                                'desde' => 1.hour.ago.iso8601 })

    ler

    expect(response.parsed_body.dig('autoteste', 'estado')).to eq('parado')
  end

  it 'resolve uma contradição com a escolha da pessoa e devolve a lista nova' do
    site = material('site')
    pdf = material('horarios.pdf')
    opcoes = [{ 'fonte' => site.id, 'diz' => '13h' }, { 'fonte' => pdf.id, 'diz' => '12h' }]
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', {
                                                         'contradicoes' => [{ 'id' => 'contradicao-a', 'assunto' => 'sábado', 'opcoes' => opcoes }]
                                                       })

    post "#{base}/material/problemas/contradicao-a/resolver", params: { escolha: site.id }, headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['problemas']).to eq([])
    expect(agent.reload.config.dig('conferencia_da_base', 'contradicoes', 0, 'escolha')).to eq(site.id)
  end

  it 'problema que já sumiu: 422 com texto leigo' do
    post "#{base}/material/problemas/contradicao-zzz/resolver", params: { escolha: 1 }, headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.material.problema_invalido'))
  end

  it 'pede o autoteste: rodando já na resposta, e o job enfileirado', :aggregate_failures do
    material('cardapio.pdf')

    expect { post "#{base}/material/autoteste", headers: administrator.create_new_auth_token }
      .to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
    expect(response.parsed_body.dig('autoteste', 'estado')).to eq('rodando')
  end

  it 'pedido de novo antes de 2 min: 429 com o texto leigo, sem abrir rodada', :aggregate_failures do
    material('cardapio.pdf')
    post "#{base}/material/autoteste", headers: administrator.create_new_auth_token
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste',
                                                       agent.reload.config['autoteste'].merge('estado' => 'pronto'))

    expect { post "#{base}/material/autoteste", headers: administrator.create_new_auth_token }
      .not_to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to include('error' => I18n.t('autonomia.material.autoteste_espere'), 'code' => 'autoteste_espere')
  end

  it 'sem material aprovado, o autoteste é recusado (422)' do
    post "#{base}/material/autoteste", headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'atendente sem função não lê nem age', :aggregate_failures do
    ler(atendente)
    expect(response).to have_http_status(:unauthorized)

    post "#{base}/material/autoteste", headers: atendente.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'fora da Fase 2: leitura vazia e autoteste recusado', :aggregate_failures do
    material('ficha.pdf', status: :failed, error: 'empty_extraction', trechos: [])
    Autonomia::Agents::Fase2.desligar!(account)

    ler
    expect(response.parsed_body).to eq('problemas' => [], 'autoteste' => nil)

    post "#{base}/material/autoteste", headers: administrator.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  describe 'o save do agente pela API' do
    let(:resultado) { { 'rodada' => 'r1', 'estado' => 'pronto', 'itens' => [] } }

    def salvar(config)
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { tone: 'cordial', config: config } }, headers: administrator.create_new_auth_token, as: :json
    end

    it 'não escreve as chaves do material (forjadas no pedido)' do
      Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', resultado)

      salvar('voice' => 'feminina', 'autoteste' => { 'estado' => 'pronto', 'itens' => [{ 'veredito' => 'certo' }] },
             'conferencia_da_base' => { 'contradicoes' => [] })

      expect(response).to have_http_status(:ok)
      expect(agent.reload.config).to include('voice' => 'feminina', 'autoteste' => resultado)
      expect(agent.config).not_to have_key('conferencia_da_base')
    end

    it 'não apaga o resultado gravado entre a leitura do agente e o save (a corrida)' do
      allow_any_instance_of(ActiveRecord::Relation).to receive(:find).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
        original.call(*args).tap do |achado|
          Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', resultado) if achado.is_a?(Autonomia::Agents::Agent)
        end
      end

      salvar('voice' => 'feminina')

      expect(response).to have_http_status(:ok)
      expect(agent.reload.config).to include('voice' => 'feminina', 'autoteste' => resultado)
    end
  end
end
