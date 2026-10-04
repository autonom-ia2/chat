require 'rails_helper'

# As vigias e os avisos entram sozinhos no catálogo do Guia (#935): criar, ajustar e silenciar vigia
# passam pelo executar_acao de sempre, com desfazer de 5 dias, sem ferramenta nova (AC-I12).
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Guia: vigias pelo catálogo' do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: conta, name: 'Guia', agent_type: 'custom', status: :active, enabled: false,
                                     instruction: 'Guia.', config: { 'with_knowledge' => false })
  end
  let(:operador) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }
  let(:leitura) { { 'rota' => 'inboxes', 'medida' => { 'tipo' => 'contagem', 'onde' => { 'reauthorization_required' => true } } } }

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  def ler(params)
    Autonomia::Agents::Tools::Native::GuiaLeitura.new(agent: agente, params: params, operador: operador).call
  end

  def executar(params)
    Autonomia::Agents::Tools::Native::GuiaExecucao.new(agent: agente, params: params, operador: operador).call
  end

  it 'as rotas de vigias e avisos estão no catálogo de leitura e de ação', :aggregate_failures do
    acoes = Autonomia::Guide::Acoes.new(account: conta, user: admin).catalogo
    leituras = Autonomia::Guide::Consulta.new(account: conta, user: admin).catalogo

    expect(acoes).to include('POST autonomia/vigias', 'PATCH autonomia/vigias/:id', 'DELETE autonomia/vigias/:id',
                             'PATCH autonomia/avisos/:id')
    expect(leituras).to include('autonomia/vigias', 'autonomia/vigias/:id', 'autonomia/avisos')
  end

  it 'o formato de POST autonomia/vigias traz o esquema da leitura e do gatilho', :aggregate_failures do
    formato = Autonomia::Guide::Formatos.para('POST autonomia/vigias')

    expect(formato.dig('campos', 'leitura', 'esquema', 'required')).to eq(%w[rota medida])
    expect(formato.dig('campos', 'gatilho', 'esquema', 'properties').keys).to include('acima_de', 'vezes_a_media', 'janela_horas')
  end

  it '"me avisa se…" cria a vigia direto, com desfazer', :aggregate_failures do
    executar({ 'acao' => 'POST autonomia/vigias', 'descricao' => 'Vou te avisar quando uma conexão cair.',
               'corpo_json' => { nome: 'Conexão caída', leitura: leitura, gatilho: { acima_de: 0 } }.to_json })

    vigia = Autonomia::Guide::Vigia.find_by(account: conta)
    expect(vigia).to have_attributes(nome: 'Conexão caída', criado_por_id: admin.id, ativa: true)
    Autonomia::Guide::Desfazer.new(execucao: operador.execucao, user: admin).perform
    expect(Autonomia::Guide::Vigia.where(account: conta)).to be_empty
  end

  it 'gatilho fora do formato é recusado antes de gravar', :aggregate_failures do
    resposta = executar({ 'acao' => 'POST autonomia/vigias', 'descricao' => 'Vou te avisar.',
                          'corpo_json' => { nome: 'X', leitura: leitura, gatilho: { quando: 'sempre' } }.to_json })

    expect(resposta).to include('gatilho')
    expect(Autonomia::Guide::Vigia.where(account: conta)).to be_empty
  end

  # AC-I12: "não me avisa mais disso" é PATCH {ativa: false}, com desfazer.
  it 'silenciar é PATCH ativa: false, e o desfazer liga de novo', :aggregate_failures do
    vigia = Autonomia::Guide::Vigia.create!(account: conta, criado_por: admin, nome: 'Conexão caída', leitura: leitura,
                                            gatilho: { 'acima_de' => 0 })
    ler({ 'recurso' => 'autonomia/vigias' })

    executar({ 'acao' => 'PATCH autonomia/vigias/:id', 'descricao' => 'Não vou mais te avisar disso.',
               'caminho_json' => { id: vigia.id.to_s }.to_json, 'corpo_json' => { ativa: false }.to_json })

    expect(vigia.reload.ativa).to be(false)
    expect(Autonomia::Guide::Vigia.medindo).not_to include(vigia)
    Autonomia::Guide::Desfazer.new(execucao: operador.execucao, user: admin).perform
    expect(vigia.reload.ativa).to be(true)
  end
end
# rubocop:enable RSpec/DescribeClass
