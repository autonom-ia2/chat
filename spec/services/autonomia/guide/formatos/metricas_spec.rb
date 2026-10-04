require 'rails_helper'

# AC-G11: o relatório mede a cobertura por dentro, e as leituras cruas ganham tipo pelo uso no código.
RSpec.describe Autonomia::Guide::Formatos::Metricas do
  let(:metricas) { described_class.new(Autonomia::Guide::Formatos.todos) }

  it 'tipa pelo menos 100 leituras cruas, e cada uma que sobra tem motivo', :aggregate_failures do
    expect(metricas.tipadas).to be >= 100
    expect(metricas.sem_tipo_lista).to all(satisfy { |_controller, _campo, motivo| motivo.present? })
  end

  it 'conta os campos JSON com esquema' do
    expect(metricas.com_esquema).to be >= 4
  end

  it 'imprime as duas métricas no relatório versionado', :aggregate_failures do
    relatorio = Autonomia::Guide::Formatos::RELATORIO.read

    expect(relatorio).to include("| Campos aninhados com vocabulário | #{metricas.com_esquema} de #{metricas.aninhados.size} |")
    expect(relatorio).to include("| Leituras cruas tipadas | #{metricas.tipadas} de #{metricas.tipadas + metricas.sem_tipo_lista.size} |")
    expect(relatorio).to include('## Leituras cruas sem tipo')
  end

  it 'tipa pelo que o código faz com a leitura', :aggregate_failures do
    campos = ->(acao) { Autonomia::Guide::Formatos.para(acao)['campos'] }

    expect(campos.call('POST contacts/filter')['page']).to include('tipo' => 'inteiro', 'tipo_pela_leitura' => 'uso')
    expect(campos.call('POST inboxes/:id/set_call_recording')['recording_enabled']).to include('tipo' => 'booleano')
    expect(campos.call('POST teams/:team_id/team_members')['user_ids']).to include('tipo' => 'lista')
    expect(campos.call('POST contacts/import')['import_file']).to include('tipo' => 'arquivo')
  end
end
