require 'rails_helper'

# #3211 — `PATCH autonomia/agents/:agent_id/contratado` entra no catálogo do Guia (derivado das rotas) com desfazer. O
# caderno do Guia (#855) guarda as colunas que o model gravou (`name` e `config` inteiro) e o desfazer as põe de volta
# por SQL. Aqui a prova de que o nome e a marca voltam juntos, e de que um `config` mexido depois (a versão da base,
# gravada por `jsonb_set`) vira conflito sem voltar nada pela metade. Tudo fictício.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Dados da corretora do agente contratado: o desfazer do Guia' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato do nascimento',
                                     config: { 'contratado' => marca, 'contratado_base_versao' => 'v1' })
  end
  let(:execucao) { Autonomia::Guide::Execucao.abrir(account: account, user: admin) }

  before do
    enable_test_encryption!
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas', 'agente_ferramentas_prontas_consultas')
    agente
  end

  def pelo_guia(&)
    Autonomia::Guide::Diario.gravando(execucao, 0, &)
  end

  def desfazer
    Autonomia::Guide::Desfazer.new(execucao: execucao.reload, user: admin).perform
  end

  def trocar_os_dados
    dados = { nome_agente: 'Rita', nome_corretora: 'Corretora Nova', sobre_corretora: 'Seguros de viagem.' }
    pelo_guia { Autonomia::Agents::Contratados::DadosDaCorretora.new(agent: agente, **dados).call }
  end

  it 'volta o nome e a marca do contratado, juntos e sem conflito' do
    trocar_os_dados
    feito = [agente.reload.name, agente.config['contratado']['nome_corretora']]

    relatorio = desfazer

    expect(feito).to eq(['Rita', 'Corretora Nova'])
    agente.reload
    expect([agente.name, agente.config['contratado'], agente.config['contratado_base_versao'], relatorio['conflitos']])
      .to eq(['Bia', marca, 'v1', []])
  end

  it 'config mexido depois (versão da base nova): conflito, e nada volta pela metade' do
    trocar_os_dados
    Autonomia::Agents::Contratados::Base.gravar_versao!(agente, 'v2')

    relatorio = desfazer

    agente.reload
    expect([agente.name, agente.config['contratado']['nome_corretora'], agente.config['contratado_base_versao']])
      .to eq(['Rita', 'Corretora Nova', 'v2'])
    expect(relatorio['conflitos'].pluck('motivo')).to eq(['changed_after'])
  end
end
# rubocop:enable RSpec/DescribeClass
