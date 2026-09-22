require 'rails_helper'

# A REGRA DO MOTIVO POR MOLDE FECHADO (fatia 2 do #420; decisões do CEO de 13/09/2026, sétima e oitava rodadas): o código
# classifica o motivo em `veiculo` ou `regiao`, e só isso vai ao modelo. A categoria sai só quando TODA palavra do texto
# está no molde da categoria e o texto nomeia o que foi recusado. Palavra desconhecida, `kind` fora de `risco`, texto
# que não é String UTF-8 válida: nil, o genérico.
RSpec.describe Autonomia::Insurance::MotivoDaRecusa do
  # Motivos de veículo e de região que o molde aceita, escritos com as palavras que os portais usam.
  aceitos = {
    'Tipo de veículo não aceito.' => 'veiculo',
    'Idade do veículo fora da política de aceitação.' => 'veiculo',
    'Modelo do veículo sem aceitação nesta seguradora.' => 'veiculo',
    'Carro acima da idade permitida.' => 'veiculo',
    'Categoria tarifária do veículo não aceita.' => 'veiculo',
    'Ano de fabricação do veículo não permitido.' => 'veiculo',
    'Cobertura auto não permitida para este modelo.' => 'veiculo',
    'CEP sem aceitação.' => 'regiao',
    'Região de circulação não atendida pela seguradora.' => 'regiao',
    'Local de pernoite sem aceitação.' => 'regiao',
    'Localidade não aceita.' => 'regiao'
  }.freeze

  def categoria(texto, kind: 'risco')
    described_class.categoria('kind' => kind, 'text' => texto)
  end

  describe 'o corpus do conector' do
    TextosDoMotivo::CORPUS.each do |texto, kind, _status, esperada|
      it "«#{texto}» (#{kind}) sai #{esperada.inspect}" do
        expect(categoria(texto, kind: kind)).to eq(esperada)
      end
    end
  end

  describe 'o que cai no genérico, mesmo classificado como risco pelo conector' do
    { 'conta da corretora' => TextosDoMotivo::CONTA, 'dado da pessoa' => TextosDoMotivo::PESSOA,
      'textos das revisões' => TextosDoMotivo::REVISOES, 'sondas da revisão da sétima rodada' => SondasDoMotivo::REVISAO_7 }
      .each do |grupo, textos|
      textos.each do |texto|
        it "#{grupo}: «#{texto}»" do
          expect(categoria(texto)).to be_nil
        end
      end
    end
  end

  describe 'o kind decide antes do texto' do
    %w[credencial outro].each do |kind|
      it "o kind #{kind} com um texto que o molde aceitaria sai genérico" do
        expect(categoria('Tipo de veículo não aceito.', kind: kind)).to be_nil
      end
    end

    # chat#323: a seguradora instável não recusou o risco, e a Lia não pode dizer só que ela não fez proposta.
    it 'o kind passageiro é instabilidade, com qualquer texto e sem ler o texto' do
      expect(categoria('Tipo de veículo não aceito.', kind: 'passageiro')).to eq(described_class::INSTABILIDADE)
      expect(described_class.categoria('kind' => 'passageiro')).to eq(described_class::INSTABILIDADE)
    end

    it 'motivo sem kind, sem texto, com texto que não é String ou que não é Hash sai genérico' do
      expect(described_class.categoria('text' => 'Tipo de veículo não aceito.')).to be_nil
      expect(described_class.categoria('kind' => 'risco', 'text' => nil)).to be_nil
      expect(described_class.categoria('kind' => 'risco', 'text' => { 'a' => 1 })).to be_nil
      expect(described_class.categoria('Tipo de veículo não aceito.')).to be_nil
      expect(described_class.categoria(nil)).to be_nil
    end
  end

  describe 'o molde fechado' do
    aceitos.each do |texto, esperada|
      it "«#{texto}» sai #{esperada}" do
        expect(categoria(texto)).to eq(esperada)
      end
    end

    # A decisão: uma palavra desconhecida manda para o genérico, em qualquer posição do texto.
    it 'uma palavra desconhecida manda para o genérico, no começo, no meio e no fim' do
      aceitos.each_key do |texto|
        expect(categoria("Seu #{texto}")).to be_nil
        expect(categoria(texto.sub(' ', ' corretor '))).to be_nil
        expect(categoria(texto.sub(/\.\z/, ' nesta plataforma.'))).to be_nil
      end
    end

    it 'os dois exemplos da decisão caem no genérico' do
      expect(categoria('Tipo de veículo sem aceitação para o seu código.')).to be_nil
      expect(categoria('Negativado: CEP sem aceitação.')).to be_nil
    end

    it 'número é palavra, e fora do molde' do
      expect(categoria('Tipo de veículo 2005 não aceito.')).to be_nil
      expect(categoria('Veículo com mais de 20 anos: idade não permitida.')).to be_nil
    end

    # "Idade", "tipo" e "categoria" também são da pessoa, da cobertura e da habilitação: sem o veículo no texto, genérico.
    it 'o molde do veículo exige o atributo e o veículo' do
      expect(categoria('Idade não permitida.')).to be_nil
      expect(categoria('Tipo de cobertura não aceito.')).to be_nil
      expect(categoria('Categoria tarifária não aceita.')).to be_nil
      expect(categoria('Veículo sem aceitação.')).to be_nil
    end

    it 'o molde da região exige o atributo da região' do
      expect(categoria('Sem aceitação nesta seguradora.')).to be_nil
      expect(categoria('Local sem aceitação.')).to be_nil
    end

    it 'texto com o veículo e a região sai genérico' do
      expect(categoria('Modelo do veículo sem aceitação neste CEP.')).to be_nil
    end

    it 'letra que a transliteração não escreve é palavra desconhecida' do
      expect(categoria('Tipo de veículo não aceito: ꜱᴇɴʜᴀ.')).to be_nil
    end

    it 'texto que não é UTF-8 válido sai genérico, sem levantar' do
      expect(categoria('Tipo de veículo não aceito.'.encode('UTF-16LE'))).to be_nil
      expect(categoria((+"Tipo de ve\xEDculo n\xE3o aceito.").force_encoding('ASCII-8BIT'))).to be_nil
      expect(categoria("Tipo de ve\xC3culo n\xE3o aceito.")).to be_nil
    end

    # O MOLDE NÃO TEM PALAVRA DE CONTA NEM DA PESSOA: é a garantia de que "Tipo de veículo sem aceitação para o <conta>"
    # e "<pessoa>: CEP sem aceitação" nunca viram categoria, por mais que alguém amplie o molde.
    it 'nenhum molde tem palavra da conta da corretora, da pessoa ou de critério interno' do
      proibidas = %w[login senha sessao token usuario acesso permissao corretor corretora corretagem credencial codigo
                     cadastro comissao bloqueio conta portal operador perfil parceiro comercial contrato plano pacote
                     agente escritorio regional unidade plataforma sistema seu sua segurado segurada condutor motorista
                     proprietario cliente pessoa proponente titular tomador beneficiario negativado score cpf cnh
                     credito financeiro sinistro bonus profissao renda restricao pendencia interno
                     interna criterio analise]
      no_molde = described_class::MOLDES.values.flat_map { |molde| proibidas.select { |palavra| molde[:palavras].include?(palavra) } }

      expect(no_molde).to be_empty
    end
  end
end
