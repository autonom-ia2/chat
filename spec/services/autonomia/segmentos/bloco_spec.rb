require 'rails_helper'

# Contrato do bloco de segmento (tema 8, #1429) com o conteúdo do #1802, lote 6. "Nenhuma frase pronta de cliente" é
# regra de conteúdo, escrita no próprio arquivo.
RSpec.describe Autonomia::Segmentos::Bloco do
  let(:segmento) { 'seguros/corretora' }
  let(:nicho) { Autonomia::Agents::Nicho }
  let(:segmentos) { nicho::PERFIS.map { |perfil| "seguros/#{perfil}" } }

  it 'for_segmento returns nil or a String within the ceiling' do
    texto = described_class.for_segmento(segmento)

    expect(texto).to be_nil.or(be_a(String))
    expect(texto.to_s.bytesize).to be <= described_class::TEXTO_DA_BASE_MAX
  end

  it 'is stable between calls for the same segmento' do
    texto = described_class.for_segmento(segmento)
    versao = described_class.versao(segmento)

    expect(described_class.for_segmento(segmento.dup)).to eq(texto)
    expect(described_class.versao(segmento.dup)).to eq(versao)
  end

  it 'versao returns nil or a String' do
    expect(described_class.versao(segmento)).to be_nil.or(be_a(String))
  end

  # Trava do contrato: o texto e a versão dependem só do segmento (um argumento obrigatório).
  it 'depends only on the segmento' do
    %i[for_segmento versao].each do |metodo|
      obrigatorios = described_class.method(metodo).parameters.count { |tipo, _| %i[req keyreq].include?(tipo) }
      expect(obrigatorios).to eq(1)
    end
  end

  it 'no longer has for(account): nada lê o bloco pela conta' do
    expect(described_class).not_to respond_to(:for)
  end

  describe 'conteúdo (#1802, lote 6)' do
    it 'gives each insurance type its own text and version' do
      textos = segmentos.map { |seg| described_class.for_segmento(seg) }

      expect(textos).to all(be_a(String).and(be_present))
      expect(textos.uniq.size).to eq(segmentos.size)
      expect(segmentos.map { |seg| described_class.versao(seg) }.uniq.size).to eq(segmentos.size)
    end

    it 'fits every agentes.md within TEXTO_DA_BASE_MAX, so the agent is born with the text' do
      Dir.glob(described_class::PASTA.join('*', '*', described_class::ARQUIVO).to_s).each do |arquivo|
        expect(File.read(arquivo).strip.bytesize).to be <= described_class::TEXTO_DA_BASE_MAX, arquivo
      end
    end

    it 'versao is the first 12 characters of the SHA-256 of the text' do
      segmentos.each do |seg|
        expect(described_class.versao(seg)).to eq(Digest::SHA256.hexdigest(described_class.for_segmento(seg))[0, 12])
      end
    end

    it 'keeps the brokerage text about intermediation, never as the insurer' do
      expect(described_class.for_segmento('seguros/corretora')).to include('corretora de seguros', 'não é a seguradora')
    end

    it 'counts lives and lists holder and dependents, never the insured' do
      expect(described_class.for_segmento('seguros/saude_beneficios')).to include('titular e dependentes', 'Não diga segurado nem apólice')
    end

    it 'gives no text nor version to a segmento without a file' do
      expect(described_class.for_segmento('geral')).to be_nil
      expect(described_class.versao('geral')).to be_nil
      expect(described_class.for_segmento(nil)).to be_nil
      expect(described_class.versao(nil)).to be_nil
    end

    it 'stays short, so the cached prefix stays small' do
      segmentos.each { |seg| expect(described_class.for_segmento(seg).size).to be < 1500 }
    end
  end

  describe '.segmento' do
    def conta(nicho_escolhido, perfil = nil)
      create(:account, internal_attributes: { nicho::NICHO_KEY => nicho_escolhido, nicho::PERFIL_KEY => perfil }.compact)
    end

    it 'is the most specific layer of the account pack, with the switch on' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
        expect(described_class.segmento(conta('seguros', 'corretora'))).to eq('seguros/corretora')
        expect(described_class.segmento(conta('geral'))).to be_nil
      end
    end

    it 'is nil for an insurance account with the switch off' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
        expect(described_class.segmento(conta('seguros', 'corretora'))).to be_nil
      end
    end
  end
end
