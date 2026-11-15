require 'rails_helper'

# E6.5 e E6.6 (#2899) — o Guia não lê nem guarda o seguro de outra corretora, não o apaga, não escreve o seguro em
# palavras simples (chamada paga) e não o manda ao cliente: só na tela, com a frase nos dois idiomas.
RSpec.describe Autonomia::Guide::SoNaTelaDosModulos do
  let(:idiomas) { %i[en pt_BR] }
  let(:rotas) do
    Rails.application.routes.routes.map do |rota|
      "#{rota.verb} #{Autonomia::Guide::Rotas.recurso(rota.path.spec.to_s.sub('(.:format)', ''))}"
    end
  end

  {
    Carteira::DeFora::SO_NA_TELA_DO_GUIA => {
      frase: 'seguro_de_fora',
      acoes: ['POST relacionamentos/pessoas/:id/seguros_de_fora/leitura', 'GET relacionamentos/pessoas/:id/seguros_de_fora/leitura/:leitura_id',
              'POST relacionamentos/pessoas/:id/seguros_de_fora', 'DELETE relacionamentos/seguros/:id']
    },
    Carteira::Palavras::SO_NA_TELA_DO_GUIA => {
      frase: 'seguro_palavras',
      acoes: ['POST relacionamentos/seguros/:id/palavras/escrever', 'POST relacionamentos/seguros/:id/palavras/enviar']
    }
  }.each do |trava, esperado|
    it "#{esperado[:frase]}: as rotas existem, ficam fora do catálogo e têm a frase em en e pt_BR" do
      expect(trava.keys).to match_array(esperado[:acoes])
      expect(trava.values.uniq).to eq([esperado[:frase]])
      expect(rotas).to include(*trava.keys)
      expect(Autonomia::Guide::Acoes::SO_NA_TELA).to include(trava)
      expect(trava.keys.map { |acao| Autonomia::Guide::Acoes.fora_do_catalogo?(acao) }).to all(be(true))
      expect(idiomas.map { |idioma| I18n.exists?("autonomia.guide.only_on_screen.#{esperado[:frase]}", idioma) }).to eq([true, true])
    end
  end
end
