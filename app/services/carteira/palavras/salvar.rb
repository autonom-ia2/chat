# Guardar o texto de "seu seguro em palavras simples" que a pessoa ajustou (E6.6, #2899). O texto vem sem a frase do fim
# ("Vale o que está escrito na sua apólice."), que vai sempre no envio. Recusas: `falta_texto` (vazio), `texto_longo`
# (passa de Carteira::Palavras::TEXTO_MAXIMO), `pedido_invalido` (seguro de outra corretora ou cancelado). O erro nunca
# repete o texto.
class Carteira::Palavras::Salvar
  def initialize(apolice)
    @apolice = apolice
  end

  def call(texto)
    recusar('pedido_invalido') unless texto.is_a?(String) && Carteira::Palavras.cabe?(@apolice)

    texto = texto.strip
    recusar('falta_texto') if texto.empty?
    recusar('texto_longo') if texto.length > Carteira::Palavras::TEXTO_MAXIMO

    @apolice.update!(palavras_texto: texto)
    @apolice
  end

  private

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
