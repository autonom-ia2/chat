# Cada registro que o conector devolveu vira um item da busca (E7, #2900), na forma em que o Conferir e o gravador leem
# (Carteira::ItemLido: os nomes do leitor de PDF, os valores na forma do banco). O conector já entrega os campos
# separados, então nada fica "a confirmar": o que veio no formato certo vale, e o que veio fora dele não vem.
#
# - `pagina(itens, ignorados:)`: os registros de uma página. O registro que já é item (o mesmo `ref`, o mesmo começo da
#   vigência e o mesmo endosso) não vira outro: no mesmo pedido, é contado em `repetidos`; vindo de um pedido anterior
#   desta busca ("Buscar de novo" pede o período inteiro outra vez), em `ja_lidos`, porque o item dele já está contado.
#   O que o adapter não leu vem contado em `ignorados`. Assim, para cada pedido, o Conferir fecha com o `total` do
#   conector.
# - O item sem `ref` fica `falhou` ("não deu para trazer"): sem a referência, a busca seguinte não acharia o mesmo
#   seguro e criaria outro. O sem seguradora ou sem fim da vigência também: o seguro não entra sem eles.
# - `tipos!`: no fim da busca, o tipo de cada item sai do ramo (Carteira::Conector::TiposDoRamo). O item cujo tipo foi
#   respondido (pela conta ou pelo modelo) fica marcado (TiposDoRamo::RESPONDIDO): a próxima busca não pergunta de novo.
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
    contas = Hash.new(0)
    Array(itens).each do |registro|
      ja_veio = ja_veio(registro)
      next contas[ja_veio] += 1 if ja_veio

      criar(registro, posicao)
      posicao += 1
    end
    somar('recebidos' => Array(itens).size, 'repetidos' => contas['repetidos'], 'ja_lidos' => contas['ja_lidos'], 'ignorados' => ignorados.to_i)
  end

  def tipos!
    lidos = @leitura.itens.where(estado: LIDO)
    tipos = Carteira::Conector::TiposDoRamo.new(@leitura.account).call(lidos.map { |item| Carteira::ItemLido.new(item).valor('ramo_original') })
    lidos.find_each(batch_size: BLOCO) do |item|
      lido = Carteira::ItemLido.new(item)
      tipo = tipos[Carteira::Trazer::TipoDoRamo.agrupado(lido.valor('ramo_original'))]
      item.update!(lido.com('tipo' => tipo || Carteira::Conector::TiposDoRamo::OUTRO, Carteira::Conector::TiposDoRamo::RESPONDIDO => tipo && 1))
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

  # 'repetidos' (o mesmo registro já veio neste pedido), 'ja_lidos' (veio num pedido anterior desta busca) ou nil (é novo).
  # O começo da vigência faz parte: a renovação que mantém o `ref` é outro termo, outro seguro (Carteira::Termo), e
  # precisa virar item para ser gravada e se ligar ao termo anterior.
  def ja_veio(registro)
    return unless registro.is_a?(Hash) && texto(registro['ref'])

    posicoes = @leitura.itens.where("carteira_leitura_itens.campos ->> 'ref' = ?", texto(registro['ref']))
                       .where("COALESCE(carteira_leitura_itens.campos ->> 'inicio_vigencia', '') = ?", data(registro['inicio_vigencia']).to_s)
                       .where("COALESCE(carteira_leitura_itens.campos ->> 'endosso', '') = ?", endosso(registro).to_s).pluck(:posicao)
    return if posicoes.empty?

    posicoes.max >= desde_posicao ? 'repetidos' : 'ja_lidos'
  end

  def desde_posicao
    @desde_posicao ||= Carteira::Conector::Pedido.new(@leitura).desde_posicao
  end

  def campos_do(registro)
    { 'ref' => texto(registro['ref']), 'pdf_ref' => texto(registro['pdf_ref']), 'endosso' => endosso(registro),
      'endosso_data' => endosso_data(registro),
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

  # A data do endosso ordena a gravação (Carteira::Conector::Gravar::ORDEM): o mais novo fica por cima.
  def endosso_data(registro)
    registro['endosso'].is_a?(Hash) ? data(registro['endosso']['data']) : nil
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
