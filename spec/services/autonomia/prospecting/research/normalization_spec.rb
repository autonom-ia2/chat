require 'rails_helper'

# Porte de lib/services/research/company-owner/normalization.ts e do validateCnpj do Orth (#679).
RSpec.describe Autonomia::Prospecting::Research::Normalization do
  describe '.text' do
    it 'tira acento, caixa, pontuação e espaço repetido' do
      expect(described_class.text("  Açaí   do João's — Ltda. ")).to eq('acai do joao s ltda')
      expect(described_class.text(nil)).to eq('')
    end
  end

  describe '.business_name' do
    it 'descarta os sufixos societários da tabela fechada' do
      expect(described_class.business_name('Alfa Oficina LTDA')).to eq('alfa oficina')
      expect(described_class.business_name('Beta S/A')).to eq('beta')
      expect(described_class.business_name('Gama EIRELI ME')).to eq('gama')
      expect(described_class.business_name('Alfa Oficina')).to eq(described_class.business_name('Alfa Oficina Ltda'))
    end
  end

  describe '.phone' do
    it 'lê número sem + como brasileiro e com + como internacional' do
      expect(described_class.phone('(11) 99900-0001')).to eq('5511999000001')
      expect(described_class.phone('+55 11 99900-0001')).to eq('5511999000001')
      expect(described_class.phone('+1 (415) 555-2671')).to eq('14155552671')
      expect(described_class.phone('')).to be_nil
      expect(described_class.phone('abc')).to be_nil
    end
  end

  describe '.uf' do
    it 'aceita só duas letras' do
      expect(described_class.uf(' sp ')).to eq('SP')
      expect(described_class.uf('São Paulo')).to be_nil
      expect(described_class.uf('S1')).to be_nil
      expect(described_class.uf(nil)).to be_nil
    end
  end

  describe '.registrable_domain' do
    it 'reduz ao domínio registrável e recusa endereço inseguro' do
      expect(described_class.registrable_domain('https://app.alfa-oficina.com.br/contato')).to eq('alfa-oficina.com.br')
      expect(described_class.registrable_domain('www.alfa-oficina.com.br')).to eq('alfa-oficina.com.br')
      expect(described_class.registrable_domain('http://alfa.com.br')).to be_nil
      expect(described_class.registrable_domain('https://user:pass@alfa.com.br')).to be_nil
      expect(described_class.registrable_domain('https://alfa.com.br:8443')).to be_nil
      expect(described_class.registrable_domain('   ')).to be_nil
    end

    it 'exige https explícito quando pedido (site do lead)' do
      expect(described_class.registrable_domain('alfa.com.br', require_https: true)).to be_nil
      expect(described_class.registrable_domain('https://alfa.com.br', require_https: true)).to eq('alfa.com.br')
    end
  end

  describe Autonomia::Prospecting::Research::Cnpj do
    it 'valida os dígitos verificadores' do
      expect(described_class.valid?('11222333000181')).to be(true)
      expect(described_class.valid?('11222333000182')).to be(false)
      expect(described_class.valid?('11111111111111')).to be(false)
      expect(described_class.valid?('1122233300018')).to be(false)
      expect(described_class.valid?(nil)).to be(false)
    end

    it 'normaliza CNPJ formatado ou só com dígitos e descarta o inválido' do
      expect(described_class.normalize('11.222.333/0001-81')).to eq('11222333000181')
      expect(described_class.normalize('11222333000181')).to eq('11222333000181')
      expect(described_class.normalize('11.222.333/0001-80')).to be_nil
      expect(described_class.normalize('')).to be_nil
    end
  end
end
