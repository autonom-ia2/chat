# A LEITURA DO RESULTADO QUE A COTAÇÃO MAIS NOVA DE UMA CONVERSA GUARDOU (fatia 2 do #420).
#
# Quem usa é a ferramenta da Lia (`Native::InsuranceQuoteResult`). Tudo aqui lê o banco: o handle da
# execução de `cotar_seguro`, gravado por `InsuranceQuote::Resultado` em toda consulta ao portal.
class Autonomia::Insurance::ResultadoDaCotacao
  Guardado = ::Autonomia::Insurance::ResultadoPorSeguradora
  Ofertas = ::Autonomia::Insurance::QuoteOffers

  # As execuções de `cotar_seguro` que não contam como a cotação da conversa: trocadas por um pedido novo,
  # descartadas com o turno, barradas pelo operador, ou aceitas e ainda não despachadas.
  FORA = %w[superseded discarded blocked pending].freeze
  # As palavras que não distinguem uma seguradora de outra no nome ("Porto Seguro", "Sancor Seguros").
  PALAVRAS_VAZIAS = %w[a o as os e de da do das dos seguro seguros seguradora seguradoras cia companhia sa].freeze

  def self.cotacao
    ::Autonomia::Agents::Tools::Native::InsuranceQuote
  end

  # -> a execução de `cotar_seguro` mais nova da conversa, fora de `FORA`, ou nil.
  def self.execucao_mais_nova(conversation_id)
    return nil if conversation_id.blank?

    ::Autonomia::Agents::ToolRun.for_conversation(conversation_id).where(slug: cotacao.slug)
                                .where.not(status: FORA).order(created_at: :desc, id: :desc).first
  end

  # -> a leitura da cotação mais nova da conversa, ou nil quando não há.
  def self.da_conversa(conversation_id)
    run = execucao_mais_nova(conversation_id)
    run && new(run)
  end

  # -> as palavras que distinguem um texto: sem acento, em minúsculas, sem repetir e sem `PALAVRAS_VAZIAS`.
  def self.palavras(texto)
    ActiveSupport::Inflector.transliterate(texto.to_s).downcase.scan(/[a-z0-9]+/).uniq - PALAVRAS_VAZIAS
  end

  attr_reader :run

  def initialize(run)
    @run = run
  end

  # -> a execução gravou o resultado por seguradora? A que só consultou o portal antes desta versão, não.
  def guardado?
    run.handle.to_h[cotacao::Resultado::RESULTADO_KEY].is_a?(Hash)
  end

  # -> a cotação ainda recebe resposta de seguradora: a execução está viva e o portal não fechou.
  def correndo?
    run.running? && run.handle.to_h[cotacao::FECHADO_KEY].blank?
  end

  # -> a execução recebeu o número da cotação no portal? A recusada no `start` (faltou dado, ramo desconhecido)
  # não recebeu.
  def cotou?
    run.handle.to_h['quote_id'].present?
  end

  # -> a execução decidiu submeter e o número nunca chegou (`ToolRun#envio_incerto?`): a cotação pode existir
  # no portal.
  def envio_incerto?
    run.envio_incerto?
  end

  # -> a cotação foi feita sem a classe de bônus da apólice atual (`InsuranceQuote::SEM_BONUS_KEY`)?
  def sem_bonus?
    run.handle.to_h[cotacao::SEM_BONUS_KEY].present?
  end

  # -> os códigos de toda seguradora guardada.
  def codigos
    entradas.keys
  end

  # -> os códigos com preço entre `codigos` (todos, quando omitido), na ordem da lista de preços.
  def com_preco(codigos = entradas.keys)
    ofertas(codigos).map { |oferta| Ofertas.code(oferta) }
  end

  # -> alguma seguradora desta cotação ficou sem proposta?
  def sem_proposta?
    entradas.keys.any? { |codigo| desfecho(codigo) == Guardado::SEM_PROPOSTA }
  end

  # -> o preço desta seguradora como a Lia o recebe (fatia 3 do #420): o valor com o período
  # (`PremiumText#resumo`) e o parcelamento ou a ressalva de período não informado (`PremiumText#detalhe`).
  # nil sem preço.
  def preco(codigo)
    guardada = oferta(codigo.to_s)
    return nil if guardada.nil?

    premio = ::Autonomia::Insurance::PremiumText.new(guardada['premium'])
    [premio.resumo, premio.detalhe].compact.join(', ')
  end

  # -> o nome de toda seguradora desta cotação, como o item o escreve.
  def nomes
    entradas.keys.map { |codigo| nome(codigo) }.compact_blank
  end

  # -> o comparativo em PDF desta cotação foi aceito pelo publicador? A identidade dele na lista do aceite
  # (`InsuranceQuote::COMPARATIVO_KEY`) ou a sentinela das execuções anteriores (`PDF_SENT_KEY`).
  def comparativo_enviado?
    handle = run.handle.to_h
    token = handle[cotacao::COMPARATIVO_KEY]
    handle[cotacao::PDF_SENT_KEY].present? || ::Autonomia::Agents::Tools::EntregaAceita.aceita?(run, token)
  end

  # -> o nome da seguradora, limpo como o item o escreve (`QuoteOffers.nome`).
  def nome(codigo)
    Ofertas.nome('insurer' => { 'name' => entrada(codigo)['nome'] })
  end

  # -> o desfecho guardado; `aguardando` responde `sem_proposta` quando a cotação não corre mais.
  def desfecho(codigo)
    guardado = entrada(codigo)['desfecho']
    guardado == Guardado::AGUARDANDO && !correndo? ? Guardado::SEM_PROPOSTA : guardado
  end

  # -> a categoria do motivo guardada (`MotivoDaRecusa::CATEGORIAS`), ou nil. O que foi guardado fora dessas
  # categorias não conta como motivo.
  def motivo(codigo)
    guardado = entrada(codigo)['motivo']
    ::Autonomia::Insurance::MotivoDaRecusa::CATEGORIAS.include?(guardado) ? guardado : nil
  end

  # -> os códigos das seguradoras que `consulta` nomeia, primeiro as do passo 2 e depois as do passo 3:
  #   1. a seguradora cujas palavras do nome aparecem TODAS na consulta ("porto" nomeia "Porto Seguro");
  #   2. entre as do passo 1, sai a de palavras contidas nas de outra ("Bp Assinatura" tira "Bp");
  #   3. palavra da consulta que nenhuma do passo 2 cobre nomeia quem a tem no nome ("liberty" nomeia
  #      "Liberty Site").
  def procurar(consulta)
    pedidas = self.class.palavras(consulta)
    return [] if pedidas.empty?

    inteiras = sem_contidas(nomeaveis.select { |codigo| (palavras_do_nome(codigo) - pedidas).empty? })
    soltas = pedidas - inteiras.flat_map { |codigo| palavras_do_nome(codigo) }
    inteiras + (nomeaveis - inteiras).select { |codigo| palavras_do_nome(codigo).intersect?(soltas) }
  end

  private

  def cotacao
    self.class.cotacao
  end

  def entradas
    @entradas ||= guardado? ? run.handle.to_h[cotacao::Resultado::RESULTADO_KEY] : {}
  end

  def entrada(codigo)
    valor = entradas[codigo.to_s]
    valor.is_a?(Hash) ? valor : {}
  end

  # Os códigos cuja entrada tem nome com alguma palavra: sem nome, uma entrada casaria com qualquer consulta.
  def nomeaveis
    @nomeaveis ||= entradas.keys.select { |codigo| palavras_do_nome(codigo).any? }
  end

  def palavras_do_nome(codigo)
    self.class.palavras(entrada(codigo)['nome'])
  end

  def sem_contidas(codigos)
    codigos.reject do |codigo|
      proprias = palavras_do_nome(codigo)
      codigos.any? { |outro| (proprias - palavras_do_nome(outro)).empty? && palavras_do_nome(outro).size > proprias.size }
    end
  end

  # As ofertas com preço destes códigos, na forma que `QuoteOffers` lê, na ordem de `QuoteOffers#quoted`.
  def ofertas(codigos)
    lista = Array(codigos).map(&:to_s).uniq.filter_map { |codigo| oferta(codigo) }
    Ofertas.new('offers' => lista).quoted
  end

  def oferta(codigo)
    guardada = entrada(codigo)
    return nil unless guardada['desfecho'] == Guardado::COM_PRECO && guardada['premio'].is_a?(Hash)

    { 'insurer' => { 'code' => codigo, 'name' => guardada['nome'] }, 'status' => 'quoted', 'premium' => guardada['premio'] }
  end
end
