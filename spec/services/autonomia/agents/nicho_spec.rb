# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Agents::Nicho do
  let(:account) { create(:account, internal_attributes: { 'unrelated' => 'preserved' }) }

  # O padrão da instalação passa pelo cache do GlobalConfig (Redis): limpar antes e depois para um exemplo não vazar no outro.
  around do |example|
    GlobalConfig.clear_cache(described_class::PADRAO_KEY)
    example.run
    GlobalConfig.clear_cache(described_class::PADRAO_KEY)
  end

  def gravar(atributos)
    account.update!(internal_attributes: account.internal_attributes.merge(atributos))
  end

  def resumo(escolha)
    [escolha.nicho, escolha.perfil, escolha.padrao?]
  end

  describe '.for' do
    it 'fica em geral quando nem a conta nem a instalação escolheram' do
      expect(resumo(described_class.for(account))).to eq(['geral', nil, true])
    end

    it 'usa o padrão da instalação vindo da ENV' do
      with_modified_env(AUTONOMIA_NICHO_PADRAO: 'seguros:seguradora') do
        expect(resumo(described_class.for(account))).to eq(%w[seguros seguradora] + [true])
      end
    end

    it 'usa o padrão gravado em InstallationConfig antes da ENV' do
      InstallationConfig.create!(name: described_class::PADRAO_KEY, value: 'seguros:insurtech', locked: false)
      GlobalConfig.clear_cache(described_class::PADRAO_KEY)

      with_modified_env(AUTONOMIA_NICHO_PADRAO: 'geral') do
        expect(resumo(described_class.for(account))).to eq(%w[seguros insurtech] + [true])
      end
    end

    it 'completa seguros sem perfil no padrão com corretora' do
      with_modified_env(AUTONOMIA_NICHO_PADRAO: 'seguros') do
        expect(resumo(described_class.for(account))).to eq(%w[seguros corretora] + [true])
      end
    end

    it 'dá a escolha da conta por cima do padrão da instalação' do
      gravar(described_class::NICHO_KEY => 'geral')

      with_modified_env(AUTONOMIA_NICHO_PADRAO: 'seguros:corretora') do
        expect(resumo(described_class.for(account))).to eq(['geral', nil, false])
      end
    end

    it 'devolve nicho e perfil da conta em seguros' do
      gravar(described_class::NICHO_KEY => 'seguros', described_class::PERFIL_KEY => 'insurtech')

      expect(resumo(described_class.for(account))).to eq(%w[seguros insurtech] + [false])
    end

    it 'ignora perfil gravado quando a conta é geral' do
      gravar(described_class::NICHO_KEY => 'geral', described_class::PERFIL_KEY => 'seguradora')

      expect(resumo(described_class.for(account))).to eq(['geral', nil, false])
    end

    it 'cai no padrão e registra log quando o nicho gravado é inválido' do
      gravar(described_class::NICHO_KEY => 'saude')
      allow(Rails.logger).to receive(:warn)

      with_modified_env(AUTONOMIA_NICHO_PADRAO: 'seguros:corretora') do
        expect(resumo(described_class.for(account))).to eq(%w[seguros corretora] + [true])
      end
      expect(Rails.logger).to have_received(:warn).with(a_string_including('[Autonomia::Agents::Nicho]', "account=#{account.id}", 'saude'))
    end

    it 'cai no padrão e registra log quando seguros tem perfil inválido' do
      gravar(described_class::NICHO_KEY => 'seguros', described_class::PERFIL_KEY => 'banco')
      allow(Rails.logger).to receive(:warn)

      expect(resumo(described_class.for(account))).to eq(['geral', nil, true])
      expect(Rails.logger).to have_received(:warn).with(a_string_including("account=#{account.id}", 'banco'))
    end

    it 'cai em geral e registra log quando o padrão da instalação é inválido' do
      allow(Rails.logger).to receive(:warn)

      with_modified_env(AUTONOMIA_NICHO_PADRAO: 'varejo') do
        expect(resumo(described_class.for(account))).to eq(['geral', nil, true])
      end
      expect(Rails.logger).to have_received(:warn).with(a_string_including(described_class::PADRAO_KEY, 'varejo'))
    end
  end

  describe '.atribuir' do
    let(:account) do
      create(:account, internal_attributes: { 'unrelated' => 'preserved', 'autonomia_insurance_enabled' => true,
                                              'suspensions' => [{ 'category' => 'other' }] })
    end
    let(:outras_chaves) do
      { 'unrelated' => 'preserved', 'autonomia_insurance_enabled' => true, 'suspensions' => [{ 'category' => 'other' }] }
    end

    it 'grava nicho e perfil sem apagar as outras chaves de internal_attributes' do
      described_class.atribuir(account, nicho: 'seguros', perfil: 'seguradora')
      account.save!

      expect(account.reload.internal_attributes).to eq(
        outras_chaves.merge(described_class::NICHO_KEY => 'seguros', described_class::PERFIL_KEY => 'seguradora')
      )
    end

    it 'tira o perfil ao trocar para geral, mantendo as outras chaves' do
      described_class.atribuir(account, nicho: 'seguros', perfil: 'insurtech')
      account.save!
      described_class.atribuir(account, nicho: 'geral', perfil: 'insurtech')
      account.save!

      expect(account.reload.internal_attributes).to eq(outras_chaves.merge(described_class::NICHO_KEY => 'geral'))
    end

    it 'não grava valor fora da lista' do
      described_class.atribuir(account, nicho: 'saude', perfil: nil)
      described_class.atribuir(account, nicho: 'seguros', perfil: 'banco')
      account.save!

      expect(account.reload.internal_attributes).to eq(outras_chaves)
    end

    it 'não prende a conta ao padrão quando ela ainda não escolheu e recebe o próprio padrão' do
      with_modified_env(AUTONOMIA_NICHO_PADRAO: 'seguros:corretora') do
        described_class.atribuir(account, nicho: 'seguros', perfil: 'corretora')
      end
      account.save!

      expect(account.reload.internal_attributes).to eq(outras_chaves)
    end

    it 'grava o valor igual ao padrão quando a conta já tinha outra escolha' do
      described_class.atribuir(account, nicho: 'seguros', perfil: 'insurtech')
      account.save!

      described_class.atribuir(account, nicho: 'geral', perfil: nil)
      account.save!

      expect(account.reload.internal_attributes).to eq(outras_chaves.merge(described_class::NICHO_KEY => 'geral'))
    end
  end
end
