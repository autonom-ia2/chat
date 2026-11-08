require 'rails_helper'

# #1426 (tema 4b, revisão adversarial) — o limite do autoteste por agente: o pedido da pessoa, no máximo um a cada 2 min
# e 10 rodadas por dia; a rodada automática só conta no dia quando quem paga é a plataforma (sem a chave da conta).
RSpec.describe Autonomia::Agents::Material::LimiteDoAutoteste do
  include_context 'with material do agente'

  let(:autoteste) { Autonomia::Agents::Material::Autoteste }

  before { material('cardapio.pdf') }

  def chave(fonte)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste', source: fonte }))
  end

  def estado
    agent.reload.config['autoteste']
  end

  # A rodada aberta termina (sem rodar a IA): o próximo pedido não cai no "devolve a rodada viva".
  def terminar
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', estado.merge('estado' => 'pronto'))
  end

  def pedir(quando = 'pedido')
    autoteste.pedir!(agent, quando: quando)
  end

  it 'pedido da pessoa: um a cada 2 min; depois disso, libera', :aggregate_failures do
    chave(:hook)
    pedir
    terminar

    expect { pedir }.to raise_error(described_class::Excedido) { |erro| expect(erro.motivo).to eq('espere') }
    travel(2.minutes + 1.second) { expect(pedir).to include('estado' => 'rodando') }
  end

  it 'pedido da pessoa: no máximo 10 rodadas no dia; no dia seguinte, libera', :aggregate_failures do
    chave(:hook)
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste',
                                                       { 'estado' => 'pronto', 'dia' => Time.zone.today.iso8601,
                                                         'rodadas_no_dia' => 10 })

    expect { pedir }.to raise_error(described_class::Excedido) { |erro| expect(erro.motivo).to eq('amanha') }
    travel(1.day) { expect(pedir).to include('estado' => 'rodando', 'rodadas_no_dia' => 1) }
  end

  it 'a contagem e o último pedido são gravados na mesma escrita que abre a rodada' do
    chave(:hook)

    pedir

    expect(estado).to include('estado' => 'rodando', 'dia' => Time.zone.today.iso8601, 'rodadas_no_dia' => 1,
                              'ultimo_pedido' => be_present)
  end

  it 'rodada viva: devolve a dela, sem contar nem levantar' do
    chave(:hook)
    pedir

    expect(pedir).to include('estado' => 'rodando', 'rodadas_no_dia' => 1)
  end

  describe 'a rodada automática' do
    it 'com a chave da conta: não conta no dia', :aggregate_failures do
      chave(:hook)

      pedir('base_mudou')

      expect(estado['rodadas_no_dia']).to eq(0)
      expect(estado['ultimo_pedido']).to be_nil
    end

    it 'com a chave da plataforma: conta no dia e, passado o teto, não abre (sem levantar)', :aggregate_failures do
      chave(:system)
      pedir('base_mudou')
      expect(estado['rodadas_no_dia']).to eq(1)

      Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste',
                                                         estado.merge('estado' => 'pronto', 'rodadas_no_dia' => 10))
      expect(pedir('base_mudou')).to be_nil
      expect(estado['estado']).to eq('pronto')
    end
  end
end
