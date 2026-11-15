# O que a pessoa faz com um PDF do lote no Conferir (E6.3, #2899), antes de trazer:
#
#   { campos: { tipo:, seguradora:, termina:, nome: }, confirmar: [telefone|email|valor], recusar: [...], fora: true|false }
#
# - `campos`: escreve o que faltou (ou corrige o que veio). O que a pessoa escreve fica certo (Carteira::ItemLido#com).
#   O tipo é um dos da carteira; a data, AAAA-MM-DD, e não pode ser antes do começo da vigência (`termina_antes`); a
#   seguradora e o nome não podem vir vazios. Outro valor: `campo_invalido`.
# - `confirmar`: o telefone, o e-mail ou o valor achados sem certeza são do cliente: passam a valer como estão.
# - `recusar`: não são do cliente: viram "não achei" e não vão para lugar nenhum (o telefone do corretor, por exemplo).
# - `fora: true` deixa o PDF de fora do lote; `fora: false` o traz de volta.
# Só o PDF lido (ou deixado de fora) muda, e só enquanto o lote não foi trazido (`leitura_fechada`).
class Carteira::Trazer::Pdfs::MudarItem
  ESCRITOS = { 'tipo' => 'tipo', 'seguradora' => 'seguradora', 'termina' => 'fim_vigencia', 'nome' => 'segurado_nome' }.freeze
  CONFIRMAVEIS = Carteira::Trazer::Pdfs::ItemDoConferir::CONFIRA.invert.freeze
  TEXTO_MAXIMO = 200

  def initialize(item)
    @item = item
    @leitura = item.leitura
  end

  # Com a leitura travada: o Trazer, que também a trava, não leva o PDF no meio da mudança.
  def call(pedido)
    @leitura.with_lock do
      @item.reload
      recusar('leitura_fechada') unless %w[lendo lida].include?(@leitura.estado)
      recusar('item_fechado') unless %w[lido fora].include?(@item.estado)

      mudar_os_campos(pedido)
      mudar_o_estado(pedido['fora'])
    end
  end

  private

  def mudar_os_campos(pedido)
    escritos = escritos(pedido['campos'].to_h)
    confirmar = nomes(pedido['confirmar'])
    recusados = nomes(pedido['recusar'])
    lido = Carteira::ItemLido.new(@item)
    novos = lido.com(escritos.merge(confirmar.index_with { |nome| lido.valor(nome) }.compact))
    @item.assign_attributes(novos)
    @item.assign_attributes(Carteira::ItemLido.new(@item).sem(recusados)) if recusados.any?
    conferir_vigencia
    @item.save!
  end

  def mudar_o_estado(fora)
    return if fora.nil?

    @item.update!(estado: ActiveModel::Type::Boolean.new.cast(fora) ? 'fora' : 'lido')
  end

  def escritos(campos)
    recusar('campo_invalido') unless (campos.keys - ESCRITOS.keys).empty?

    campos.to_h { |campo, valor| [ESCRITOS.fetch(campo), valor_conferido(campo, valor)] }
  end

  def valor_conferido(campo, valor)
    texto = valor.to_s.strip
    return texto if campo == 'tipo' && Carteira::Apolice::TIPOS.include?(texto)
    return data(texto) if campo == 'termina'
    return texto if %w[seguradora nome].include?(campo) && texto.present? && texto.length <= TEXTO_MAXIMO

    recusar('campo_invalido')
  end

  def data(texto)
    Date.iso8601(texto).iso8601
  rescue Date::Error
    recusar('campo_invalido')
  end

  def nomes(campos)
    campos = Array(campos).map(&:to_s)
    recusar('campo_invalido') unless (campos - CONFIRMAVEIS.keys).empty?

    campos.map { |campo| CONFIRMAVEIS.fetch(campo) }
  end

  def conferir_vigencia
    lido = Carteira::ItemLido.new(@item)
    comeca = lido.certo('inicio_vigencia')
    termina = lido.certo('fim_vigencia')
    recusar('termina_antes') if comeca && termina && Date.parse(termina.to_s) < Date.parse(comeca.to_s)
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa.new(codigo), cause: nil
  end
end
