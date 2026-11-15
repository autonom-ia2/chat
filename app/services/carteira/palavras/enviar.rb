# Mandar "seu seguro em palavras simples" ao cliente (E6.6, #2899), depois do clique da pessoa (decisão P1: nada sai
# sozinho). Manda o texto GUARDADO (o que a pessoa leu e ajustou), com a frase do fim, como mensagem de saída na conversa
# do contato (Carteira::Palavras::Conversa), pelo mesmo construtor da caixa da conversa (decisão P2). O texto já vem
# pronto: o construtor o deixa literal (Autonomia::LiteralMessageBuilder), sem passar pelo preenchimento de variáveis.
# Marca `palavras_enviadas_em` e a história ganha `palavras_enviadas`.
#
# Recusas (nada sai): `leitura_desligada`, `pedido_invalido` (seguro de outra corretora ou cancelado), `falta_texto` (não
# há texto guardado), `sem_conversa` e `fora_da_janela` (a tela já oferece copiar o texto nesses dois). Com o seguro
# travado: dois cliques ao mesmo tempo não mandam duas mensagens. Nada do texto vai para log.
class Carteira::Palavras::Enviar
  ENVIADAS = 'palavras_enviadas'.freeze

  def initialize(apolice, user:)
    @apolice = apolice
    @user = user
  end

  def call
    recusar(Carteira::Leitor::Resultado::DESLIGADA) unless Carteira::Leitor::Liberado.para?(@apolice.account)
    recusar('pedido_invalido') unless Carteira::Palavras.cabe?(@apolice)

    @apolice.with_lock(requires_new: true) { mandar }
    @apolice
  end

  private

  def mandar
    recusar('falta_texto') if @apolice.palavras_texto.blank?
    por_onde = Carteira::Palavras::Conversa.new(@apolice, user: @user)
    recusar(por_onde.envio) unless por_onde.envio == Carteira::Palavras::Conversa::CONVERSA

    mensagem = Autonomia::LiteralMessageBuilder.new(@user, por_onde.conversa, ActionController::Parameters.new(content: texto, private: false),
                                                    literal_content: true).perform
    @apolice.update!(palavras_enviadas_em: Time.current)
    @apolice.eventos.create!(tipo: ENVIADAS, quando: Time.current, user: @user, valores: { mensagem: mensagem.id })
  end

  def texto
    "#{@apolice.palavras_texto}\n\n#{Carteira::Palavras.vale(@apolice.account)}"
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
