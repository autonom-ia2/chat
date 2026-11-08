require 'rails_helper'

# F3 do tema 8 (#1429): a data de cada texto (versoes.yml) e as perguntas do antes e depois (perguntas.yml), um par de
# arquivos ao lado de cada agentes.md. Quem edita o agentes.md muda a versão e precisa registrar a data nova aqui.
RSpec.describe Autonomia::Segmentos::Bloco do
  let(:pasta) { described_class::PASTA }
  let(:segmentos) { Autonomia::Agents::Nicho::PERFIS.map { |perfil| "seguros/#{perfil}" } }
  let(:idiomas) { described_class::IDIOMAS_DAS_PERGUNTAS }

  def ler_yaml(segmento, arquivo)
    YAML.safe_load_file(pasta.join(segmento, arquivo), permitted_classes: [Date])
  end

  describe '.data_da_versao' do
    it 'tem a data de publicação de cada texto atual (edite o agentes.md e registre a versão nova em versoes.yml)' do
      described_class::VERSOES.each do |segmento, versao|
        expect(described_class.data_da_versao(segmento, versao)).to be_a(Date), "#{segmento}: versão #{versao} sem data"
      end
    end

    it 'devolve nil para versão ou segmento desconhecido' do
      segmento = segmentos.first
      expect(described_class.data_da_versao(segmento, 'naoexiste000')).to be_nil
      expect(described_class.data_da_versao('geral', 'qualquer')).to be_nil
      expect(described_class.data_da_versao(nil, nil)).to be_nil
      expect(described_class.data_da_versao(segmento, nil)).to be_nil
    end

    it 'fica congelada desde o boot, como TEXTOS e VERSOES' do
      expect(described_class::DATAS).to be_frozen
      expect(described_class::DATAS.values).to all(be_frozen)
    end

    it 'só aceita versão de 12 caracteres e data AAAA-MM-DD em versoes.yml' do
      segmentos.each do |segmento|
        ler_yaml(segmento, described_class::ARQUIVO_DAS_DATAS).each do |versao, data|
          expect(versao.to_s.size).to eq(12), "#{segmento}: #{versao}"
          expect { Date.iso8601(data.to_s) }.not_to raise_error
        end
      end
    end
  end

  describe 'TEXTOS' do
    it 'continua lendo só os agentes.md (versoes.yml e perguntas.yml ficam de fora do texto)' do
      com_texto = Dir.glob(pasta.join('*', '*', described_class::ARQUIVO).to_s)
                     .map { |arquivo| Pathname(arquivo).dirname.relative_path_from(pasta).to_s }

      expect(described_class::TEXTOS.keys).to match_array(com_texto)
      described_class::TEXTOS.each do |segmento, texto|
        expect(texto).to eq(File.read(pasta.join(segmento, described_class::ARQUIVO)).strip)
      end
    end
  end

  describe '.perguntas' do
    it 'cada tipo tem 3 perguntas em pt_BR e em en, com listas do mesmo tamanho' do
      segmentos.each do |segmento|
        dados = ler_yaml(segmento, described_class::ARQUIVO_DAS_PERGUNTAS)

        expect(dados.keys).to match_array(idiomas), segmento
        idiomas.each do |idioma|
          expect(dados[idioma]).to all(be_a(String).and(be_present)), "#{segmento} #{idioma}"
          expect(dados[idioma].size).to eq(described_class::PERGUNTAS_POR_TIPO), "#{segmento} #{idioma}"
          expect(dados[idioma].map(&:size)).to all(be <= described_class::PERGUNTA_MAX), "#{segmento} #{idioma}"
        end
      end
    end

    it 'devolve as do idioma pedido' do
      segmento = segmentos.first
      dados = ler_yaml(segmento, described_class::ARQUIVO_DAS_PERGUNTAS)

      expect(described_class.perguntas(segmento, 'en')).to eq(dados['en'])
      expect(described_class.perguntas(segmento, :pt_BR)).to eq(dados['pt_BR'])
    end

    it 'cai no pt_BR quando o idioma não está na lista' do
      segmento = segmentos.first

      expect(described_class.perguntas(segmento, 'es')).to eq(described_class.perguntas(segmento, 'pt_BR'))
      expect(described_class.perguntas(segmento, nil)).to eq(described_class.perguntas(segmento, 'pt_BR'))
    end

    it 'devolve lista vazia para segmento sem perguntas' do
      expect(described_class.perguntas('geral', 'pt_BR')).to eq([])
      expect(described_class.perguntas(nil, 'pt_BR')).to eq([])
    end

    it 'fica congelada desde o boot' do
      expect(described_class::PERGUNTAS).to be_frozen
      expect(described_class::PERGUNTAS.values.flat_map(&:values)).to all(be_frozen)
    end

    # As regras de texto da Segmentação, conferidas no nosso próprio arquivo (não é leitura do que o cliente escreve).
    it 'segue as palavras do ramo: corretor, cotação só na corretora, beneficiário na saúde' do
      segmentos.each do |segmento|
        textos = described_class.perguntas(segmento, 'pt_BR').map(&:downcase)

        expect(textos.none? { |texto| texto.include?('vendedor') || texto.include?('produtor') }).to be(true), segmento
        expect(textos.none? { |texto| texto.include?('cotação') }).to be(true), segmento unless segmento == 'seguros/corretora'
      end
      expect(described_class.perguntas('seguros/saude_beneficios', 'pt_BR').map(&:downcase)
                            .none? { |texto| texto.include?('segurado') }).to be(true)
    end
  end
end
