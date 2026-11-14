# Um PDF do lote no Conferir (E6.3, #2899): o que falta para o seguro dele entrar e o que a pessoa precisa conferir.
# Lê o item só pelo Carteira::ItemLido (decisão D1).
#
# - `faltam`: o que o seguro não entra sem: o tipo, a seguradora e quando termina, com certeza; e o nome do segurado,
#   quando ninguém da conta é ele (a pessoa nasce com esse nome). "Não achei" nunca é preenchido sozinho, e o valor sem
#   certeza não conta como achado. A pessoa escreve o que falta, ou deixa o PDF de fora.
# - `confira`: o que foi achado sem certeza (o telefone e o e-mail do segurado, o valor sem "R$"). Nunca vem aceito:
#   fica fora do seguro e da ficha até a pessoa dizer que está certo. Não segura o PDF: o seguro entra sem eles.
# - `pronto?`: lido, sem nada faltando. É o que o Trazer traz.
class Carteira::Trazer::Pdfs::ItemDoConferir
  # O que falta, com o nome do leitor de cada campo.
  OBRIGATORIOS = { 'tipo' => 'tipo', 'seguradora' => 'seguradora', 'termina' => 'fim_vigencia' }.freeze
  NOME = 'segurado_nome'.freeze
  # nome do leitor => campo da tela, do que pode estar a confirmar.
  CONFIRA = { 'segurado_telefone' => 'telefone', 'segurado_email' => 'email', 'valor_centavos' => 'valor' }.freeze
  # Os estados em que o PDF aparece na lista do Conferir mesmo sem pedir nada: a pessoa precisa saber o que não entrou.
  A_MOSTRAR = %w[recusado falhou fora nao_entrou].freeze

  attr_reader :item, :pessoa, :lido

  # pessoa: a pessoa da conta que é o segurado (Carteira::Trazer::Pdfs::PessoaDoItem#achar), ou nil.
  def initialize(item, pessoa: nil)
    @item = item
    @lido = Carteira::ItemLido.new(item)
    @pessoa = pessoa
  end

  def lido?
    @item.estado == 'lido'
  end

  def faltam
    return [] unless lido?

    faltando = OBRIGATORIOS.reject { |_campo, nome| @lido.certo?(nome) }.keys
    @pessoa.nil? && !@lido.certo?(NOME) ? faltando + ['nome'] : faltando
  end

  def confira
    return [] unless lido?

    @lido.a_confirmar.slice(*CONFIRA.keys).map { |nome, valor| { campo: CONFIRA.fetch(nome), valor: na_tela(nome, valor) } }
  end

  def pronto?
    lido? && faltam.empty?
  end

  def precisa?
    lido? && (faltam.any? || confira.any?)
  end

  def mostrar?
    precisa? || A_MOSTRAR.include?(@item.estado)
  end

  # A pessoa que este PDF traz: a da conta, ou uma chave para a que vai nascer (o documento, senão o nome).
  def chave_da_pessoa
    return "pessoa:#{@pessoa.id}" if @pessoa

    "nova:#{@lido.certo('segurado_documento') || Carteira::Chave.seguradora(@lido.certo(NOME))}"
  end

  def para_a_tela
    { id: @item.id, posicao: @item.posicao + 1, estado: @item.estado, nome: @lido.valor(NOME), seguradora: @lido.valor('seguradora'),
      numero: @lido.valor('numero'), tipo: @lido.certo('tipo'), termina: @lido.certo('fim_vigencia'), faltam: faltam, confira: confira,
      pessoa: @pessoa && { id: @pessoa.id, nome: @pessoa.name } }
  end

  private

  def na_tela(nome, valor)
    nome == 'valor_centavos' ? Carteira::Campos.em_reais(valor) : valor
  end
end
