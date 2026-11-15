# Cada registro que o conector devolveu vira um item da busca (E7, #2900), na forma em que o Conferir e o gravador leem
# (Carteira::ItemLido: os nomes do leitor de PDF, os valores na forma do banco). O conector já entrega os campos
# separados, então nada fica "a confirmar": o que veio no formato certo vale, e o que veio fora dele não vem.
#
# - `pagina(itens, ignorados:)`: os registros de uma página. O registro repetido (o mesmo `ref` e o mesmo endosso) não
#   vira outro item: é contado em `repetidos`. O que o adapter não leu vem contado em `ignorados`.
# - O item sem `ref` fica `falhou` ("não deu para trazer"): sem a referência, a busca seguinte não acharia o mesmo
#   seguro e criaria outro. O sem seguradora ou sem fim da vigência também: o seguro não entra sem eles.
# - `tipos!`: no fim da busca, o tipo de cada item sai do ramo (Carteira::Conector::TiposDoRamo).
#
# Os registros têm dado de cliente (nome, documento, e-mail, número da apólice, `pdf_ref`): ficam só nos itens, que saem
# quando a guarda vence, e nada daqui vai para log, argumento de job ou cache.
class Carteira::Conector::Ler
  LIDO = 'lido'.freeze
  FALHOU = 'falhou'.freeze
  TEXTO_MAXIMO = 255
  BLOCO = 500

  def initialize(leitura)
    @leitura = leitura
  end

  def pagina(itens, ignorados: 0)
    posicao = (@leitura.itens.maximum(:posicao) || Carteira::Conector::Pedido::POSICAO) + 1
    repetidos = 0
    Array(itens).each do |registro|
      next repetidos += 1 if repetido?(registro)

      criar(registro, posicao)
      posicao += 1
    end
    somar('recebidos' => Array(itens).size, 'repetidos' => repetidos, 'ignorados' => ignorados.to_i)
  end

  def tipos!
    lidos = @leitura.itens.where(estado: LIDO)
    tipos = Carteira::Conector::TiposDoRamo.new(@leitura.account).call(lidos.map { |item| Carteira::ItemLido.new(item).valor('ramo_original') })
    lidos.find_each(batch_size: BLOCO) do |item|
      ramo = Carteira::Trazer::TipoDoRamo.agrupado(Carteira::ItemLido.new(item).valor('ramo_original'))
      item.update!(Carteira::ItemLido.new(item).com('tipo' => tipos.fetch(ramo, Carteira::Conector::TiposDoRamo::OUTRO)))
    end
  end

  private

  def criar(registro, posicao)
    campos = registro.is_a?(Hash) ? campos_do(registro) : {}
    @leitura.itens.create!(posicao: posicao, estado: pode_entrar?(campos) ? LIDO : FALHOU, campos: campos.compact, duvidas: [])
  end

  def pode_entrar?(campos)
    campos['ref'].present? && campos['seguradora'].present? && campos['fim_vigencia'].present?
  end

  def repetido?(registro)
    return false unless registro.is_a?(Hash) && texto(registro['ref'])

    @leitura.itens.where("carteira_leitura_itens.campos ->> 'ref' = ?", texto(registro['ref']))
            .exists?(["COALESCE(carteira_leitura_itens.campos ->> 'endosso', '') = ?", endosso(registro).to_s])
  end

  def campos_do(registro)
    { 'ref' => texto(registro['ref']), 'pdf_ref' => texto(registro['pdf_ref']), 'endosso' => endosso(registro),
      'seguradora' => texto(registro['seguradora']), 'numero' => texto(registro['numero']), 'ramo_original' => texto(registro['ramo']),
      'inicio_vigencia' => data(registro['inicio_vigencia']), 'fim_vigencia' => data(registro['fim_vigencia']),
      'valor_centavos' => centavos(registro['premio_centavos']), 'bem' => texto(registro['item']) }.merge(segurado_do(registro))
  end

  def segurado_do(registro)
    segurado = registro['segurado'].is_a?(Hash) ? registro['segurado'] : {}
    { 'segurado_nome' => texto(segurado['nome']), 'segurado_documento' => documento(segurado['documento']),
      'segurado_email' => email(segurado['email']) }
  end

  def endosso(registro)
    registro['endosso'].is_a?(Hash) ? texto(registro['endosso']['numero']) : nil
  end

  def texto(valor)
    return unless valor.is_a?(String) || valor.is_a?(Numeric)

    valor.to_s.strip.presence&.truncate(TEXTO_MAXIMO)
  end

  def data(valor)
    Date.iso8601(valor.to_s).iso8601 if valor.is_a?(String)
  rescue Date::Error
    nil
  end

  def centavos(valor)
    valor if valor.is_a?(Integer) && !valor.negative?
  end

  # Só dígitos, como o contrato diz; outra coisa não é documento de ninguém.
  def documento(valor)
    numero = texto(valor)
    numero if numero&.each_char&.all? { |caractere| caractere.between?('0', '9') }
  end

  # A mesma régua da ficha (Contact valida o e-mail com Devise.email_regexp): o e-mail fora dela não iria para a pessoa.
  def email(valor)
    endereco = texto(valor)
    endereco if endereco && Devise.email_regexp.match?(endereco)
  end

  def somar(contagens)
    @leitura.with_lock do
      totais = @leitura.totais.to_h
      @leitura.update!(totais: totais.merge(contagens.to_h { |chave, quanto| [chave, totais[chave].to_i + quanto] }))
    end
  end
end
