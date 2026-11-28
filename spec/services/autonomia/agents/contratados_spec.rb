require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados do
  let(:account) { create(:account) }

  before { enable_test_encryption! }

  describe 'segmento do modelo (#3269)' do
    let(:instalacao) { 'AUTONOMIA_NICHO_PADRAO' }

    before do
      account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                               'agente_ferramentas_prontas_consultas')
    end

    it 'liberado para seguros com perfil corretora' do
      marcar_corretora!(account)
      expect(described_class.liberado?(account, 'seguro_viagem_universal')).to be(true)
    end

    it 'recusa a conta geral' do
      Autonomia::Agents::Nicho.atribuir(account, nicho: Autonomia::Agents::Nicho::GERAL, perfil: nil)
      account.save!
      expect(described_class.liberado?(account, 'seguro_viagem_universal')).to be(false)
      expect(described_class.disponiveis(account)).to eq([])
    end

    %w[seguradora insurtech saude_beneficios].each do |perfil|
      it "recusa seguros com perfil #{perfil}" do
        marcar_corretora!(account, perfil: perfil)
        expect(described_class.liberado?(account, 'seguro_viagem_universal')).to be(false)
      end
    end

    it 'conta sem escolha segue o padrão da instalação, como a carteira (Carteira::Acesso)' do
      with_modified_env(instalacao => 'seguros:corretora') do
        expect(described_class.liberado?(account, 'seguro_viagem_universal')).to be(true)
      end
      with_modified_env(instalacao => 'seguros:seguradora') do
        expect(described_class.liberado?(account, 'seguro_viagem_universal')).to be(false)
      end
      with_modified_env(instalacao => 'geral') do
        expect(described_class.liberado?(account, 'seguro_viagem_universal')).to be(false)
      end
    end
  end

  it 'disponível só com a flag do modelo, as duas das prontas e o cofre' do
    marcar_corretora!(account)
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                             'agente_ferramentas_prontas_consultas')
    expect(described_class.disponiveis(account)).to eq(['seguro_viagem_universal'])
    account.disable_features!('agente_ferramentas_prontas_consultas')
    expect(described_class.disponiveis(account)).to eq([])
  end

  it 'disponível exige a chave de IA da própria conta; liberado não (a da instalação não conta)' do
    marcar_corretora!(account)
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                             'agente_ferramentas_prontas_consultas')
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-da-instalacao-teste')
    expect(described_class.liberado?(account, 'seguro_viagem_universal')).to be(true)
    expect(described_class.disponivel?(account, 'seguro_viagem_universal')).to be(false)

    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => 'chave-da-conta-teste' })
    expect(described_class.disponivel?(account, 'seguro_viagem_universal')).to be(true)
  end

  it 'os slugs do catálogo existem no Registry' do
    slugs = described_class::MODELOS.values.flat_map { |m| m[:ferramentas_nativas] }
    expect(slugs - Autonomia::Agents::Tools::Registry.slugs).to eq([])
  end

  it 'grava as quatro chaves da conversa do PR 1 em texto' do
    expect(described_class::CONVERSA_DO_PR1.keys).to eq(
      %w[conversa_espera_a_fala conversa_em_fila conversa_entrega_inteira conversa_ritmo_do_canal]
    )
    expect(described_class::CONVERSA_DO_PR1.values.uniq).to eq([true])
  end

  it 'DadosIncompletos é tratada pelas portas da Lia' do
    expect(described_class::DadosIncompletos.ancestors)
      .to include(Autonomia::Insurance::QuoteAgent::Builder::EscolhasIncompletas)
  end

  it 'modelo e ferramentas: nil para quem não é contratado' do
    agente = Autonomia::Agents::Agent.new(account: account, config: {})
    expect(described_class.modelo(agente)).to be_nil
    expect(described_class.ferramentas(agente)).to be_nil
  end
end
