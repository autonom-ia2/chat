require 'rails_helper'

# #2858 — o filtro de sujeira dos Produtos das seguradoras: o diretório de produção do Open Insurance aponta endereços
# para servidor de teste, e as seguradoras publicam link de exemplo e produto de sandbox como se fossem reais.
# A conferência é por rótulo do host e por método de string, sem expressão regular.
RSpec.describe Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::Sujeira do
  describe '.servidor_de_teste?' do
    it 'acha os hosts de teste que o diretorio de producao traz nos tres ramos' do
      %w[api-hml.safra.com.br open-api-sandbox.portoseguro.com.br btgseguros.openinsurance-dev.btgpactual.com].each do |host|
        expect(described_class.servidor_de_teste?(host)).to be(true), host
      end
    end

    it 'acha as outras marcas de teste, em qualquer rotulo do host' do
      %w[homolog.seguradora.com.br api.uat.seguradora.com.br dev.seguradora.com.br apihml.seguradora.com.br
         api-homologacao.seguradora.com.br mock.seguradora.com.br api.stg.seguradora.com.br api-qa.seguradora.com.br
         API-HML.SEGURADORA.COM.BR apihm.caixaseguradora.com.br].each do |host|
        expect(described_class.servidor_de_teste?(host)).to be(true), host
      end
    end

    it 'deixa passar o host de producao, mesmo com "dev" ou "uat" dentro de uma palavra' do
      %w[api.opin.allianz.com.br auth.tokiomarine.com.br api.itau api.devonseguros.com.br api.quatro.com.br
         api.opin.yelumseguros.com.br].each do |host|
        expect(described_class.servidor_de_teste?(host)).to be(false), host
      end
    end
  end

  describe '.link_das_condicoes?' do
    it 'aceita o link HTTPS de verdade' do
      expect(described_class.link_das_condicoes?('https://www.allianz.com.br/seguros/transportes/documentos.html')).to be(true)
    end

    it 'recusa link de exemplo, o do proprio Open Insurance e o link sem pontuacao' do
      ['https://exemplo.com.br/cg.pdf', 'https://www.exemplo.com.br/cg.pdf', 'https://example.com/cg', 'https://www.example.org/x',
       'https://www.seguradora.com.br/produto/tradicional/pdf/condicoes_gerais.pdf', 'https://openinsurance.com.br/aaa',
       'https://empresaa1.com/cg', 'HTTPSWWWBRADESCOSEGUROSCOMBRCONDICOESGERAIS', 'https://httpswwwbradesco/cg',
       'http://www.allianz.com.br/cg', 'www.yelumseguros.com.br/cg', 'Seguro Garantia: Proteção', '', nil].each do |link|
        expect(described_class.link_das_condicoes?(link)).to be(false), link.inspect
      end
    end
  end

  describe '.de_exemplo?' do
    it 'reconhece o nome e a cobertura que o sandbox manda' do
      expect(described_class.produto_de_exemplo?(' Produto  de Seguro ')).to be(true)
      expect(described_class.produto_de_exemplo?('Produto de Seguro Garantia')).to be(false)
      expect(described_class.cobertura_de_exemplo?('string')).to be(true)
      expect(described_class.cobertura_de_exemplo?('Colisão')).to be(false)
    end
  end
end
