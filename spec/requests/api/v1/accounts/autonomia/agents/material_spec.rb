require 'rails_helper'

# #1426 (tema 4b) — a API das conferências do material: ler os problemas e resolver um com a escolha da pessoa. Fora da
# Fase 2 e na Lia, leitura vazia. O save do agente pela API não escreve nem apaga as chaves do material.
# #3200: o teste automático do material saiu.
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

  it 'lê os problemas, e só eles', :aggregate_failures do
    ficha = material('ficha.pdf', status: :failed, error: 'empty_extraction', trechos: [])
    material('cardapio.pdf')

    ler

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('problemas' => [{ 'id' => "vazio-#{ficha.id}", 'tipo' => 'vazio', 'fontes' => [ficha.id],
                                                         'nome' => 'ficha.pdf' }])
  end

  # #3200: o resultado de um teste antigo, que ficou gravado no agente, não vira mais cartão nem resumo.
  it 'ignora o resultado de teste antigo que ficou gravado no agente' do
    material('cardapio.pdf')
    antigo = { 'rodada_dos_itens' => 'r', 'estado' => 'pronto',
               'itens' => [{ 'pergunta' => 'Vende bolo?', 'origem' => 'fora', 'veredito' => 'inventou' }] }
    agent.update_columns(config: agent.config.to_h.merge('autoteste' => antigo)) # rubocop:disable Rails/SkipsModelValidations

    ler

    expect(response.parsed_body).to eq('problemas' => [])
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

  it 'atendente sem função não lê nem age', :aggregate_failures do
    ler(atendente)
    expect(response).to have_http_status(:unauthorized)

    post "#{base}/material/problemas/contradicao-a/resolver", params: { escolha: 1 }, headers: atendente.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'fora da Fase 2: leitura vazia e ação recusada', :aggregate_failures do
    ficha = material('ficha.pdf', status: :failed, error: 'empty_extraction', trechos: [])
    Autonomia::Agents::Fase2.desligar!(account)

    ler
    expect(response.parsed_body).to eq('problemas' => [])

    post "#{base}/material/problemas/vazio-#{ficha.id}/resolver", params: { escolha: 'qualquer' }, headers: administrator.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  describe 'o save do agente pela API' do
    let(:resultado) { { 'hash_da_base' => 'h1', 'contradicoes' => [] } }

    def salvar(config)
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { tone: 'cordial', config: config } }, headers: administrator.create_new_auth_token, as: :json
    end

    it 'não escreve as chaves do material (forjadas no pedido)' do
      Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', resultado)

      salvar('voice' => 'feminina', 'conferencia_da_base' => { 'contradicoes' => [{ 'id' => 'forjada' }] })

      expect(response).to have_http_status(:ok)
      expect(agent.reload.config).to include('voice' => 'feminina', 'conferencia_da_base' => resultado)
    end

    it 'não apaga o resultado gravado entre a leitura do agente e o save (a corrida)' do
      allow_any_instance_of(ActiveRecord::Relation).to receive(:find).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
        original.call(*args).tap do |achado|
          Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', resultado) if achado.is_a?(Autonomia::Agents::Agent)
        end
      end

      salvar('voice' => 'feminina')

      expect(response).to have_http_status(:ok)
      expect(agent.reload.config).to include('voice' => 'feminina', 'conferencia_da_base' => resultado)
    end
  end
end
