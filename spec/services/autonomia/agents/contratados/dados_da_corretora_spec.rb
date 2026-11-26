require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados::DadosDaCorretora do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:agente) do
    Autonomia::Agents::Contratados::Contratar.new(account: account, user: user, modelo: 'seguro_viagem_universal',
                                                  nome_agente: 'Bia', nome_corretora: 'Corretora Exemplo',
                                                  sobre_corretora: 'Desde 2010.').call
  end

  before do
    enable_test_encryption!
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                             'agente_ferramentas_prontas_consultas')
    # O agente nasce pelo Contratar, que exige a chave de IA da própria conta; a de mentira não passa pelo provedor.
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => 'chave-da-conta-teste' })
  end

  def trocar(alvo = agente, **mudancas)
    dados = { nome_agente: 'Rui', nome_corretora: 'Outra Corretora Exemplo', sobre_corretora: 'Desde 1999.' }.merge(mudancas)
    described_class.new(agent: alvo, **dados).call
  end

  it 'troca os três, mantém o modelo e não enfileira a base' do
    agente
    expect { trocar }.not_to have_enqueued_job(Autonomia::Agents::Contratados::SemearBaseJob)

    agente.reload
    expect(agente.name).to eq('Rui')
    expect(agente.config['contratado']).to eq('modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Rui',
                                              'nome_corretora' => 'Outra Corretora Exemplo',
                                              'sobre_corretora' => 'Desde 1999.')
    expect(agente.instrucao_do_sistema).to include('Rui', 'Outra Corretora Exemplo', 'Desde 1999.')
  end

  it 'não volta a versão da base gravada depois de o agente ser lido' do
    lido = Autonomia::Agents::Agent.find(agente.id)
    Autonomia::Agents::Contratados::Base.gravar_versao!(agente, 'versao-nova')

    trocar(lido)

    expect(agente.reload.config).to include('contratado_base_versao' => 'versao-nova',
                                            'humanize_delivery' => true, 'with_knowledge' => true)
  end

  it 'recusa com o campo, como o Contratar (R14), e não grava nada' do
    expect { trocar(sobre_corretora: 'fale com $nomeCorretora') }
      .to raise_error(Autonomia::Agents::Contratados::Contratar::Recusado) { |e|
        expect([e.motivo, e.campo]).to eq(%w[marcador sobre_corretora])
      }
    expect(agente.reload.name).to eq('Bia')
  end

  it 'agente que não é contratado: indisponivel' do
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr')
    expect { trocar(comum) }.to raise_error(Autonomia::Agents::Contratados::Contratar::Recusado) { |e|
      expect([e.motivo, e.campo]).to eq(['indisponivel', nil])
    }
  end

  it 'conta sem a flag: indisponivel' do
    agente
    account.disable_features!('agente_seguro_viagem_universal')
    expect { trocar }.to raise_error(Autonomia::Agents::Contratados::Contratar::Recusado) { |e|
      expect(e.motivo).to eq('indisponivel')
    }
  end
end
