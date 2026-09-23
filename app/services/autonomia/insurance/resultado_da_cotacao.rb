# A LEITURA DO RESULTADO QUE A COTAÇÃO MAIS NOVA DE UMA CONVERSA GUARDOU (fatia 2 do #420), por produto quando a
# conversa cota mais de um (a faixa da execução, teste em produção de 23/09/2026).
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
  # O parâmetro das ferramentas que leem a cotação (`ver_resultado_da_cotacao`, `enviar_proposta_da_seguradora`): com
  # mais de um bem cotado na conversa (chat#612), é ele que diz de qual o cliente fala (`escolha`).
  PARAM_PRODUTO = { 'name' => 'produto', 'type' => 'string', 'required' => false,
                    'description' => 'De qual cotação o cliente fala: o ramo (auto, residencial) quando só há um bem ' \
                                     'daquele ramo, ou o nome exato da lista que a ferramenta devolveu. null quando ' \
                                     'a conversa só tem uma cotação.' }.freeze

  def self.cotacao
    ::Autonomia::Agents::Tools::Native::InsuranceQuote
  end

  # -> as execuções de `cotar_seguro` da conversa; só as da `faixa` (o produto) quando ela vem. Sem faixa, todas:
  # quem lê sem saber o produto fica com a mais nova, como antes de residencial correr ao lado de auto.
  def self.execucoes(conversation_id, faixa: nil)
    runs = ::Autonomia::Agents::ToolRun.for_conversation(conversation_id).where(slug: cotacao.slug)
    faixa.present? ? runs.where(faixa: faixa.to_s) : runs
  end

  # -> a execução de `cotar_seguro` mais nova da conversa (da `faixa`, quando vem), fora de `FORA`, ou nil.
  def self.execucao_mais_nova(conversation_id, faixa: nil)
    return nil if conversation_id.blank?

    execucoes(conversation_id, faixa: faixa).where.not(status: FORA).order(created_at: :desc, id: :desc).first
  end

  # -> as execuções mais novas que chegaram ao portal (`#cotou?`) ou ainda estão abertas (aceitas ou correndo), UMA POR
  # BEM do `ramo` (chat#612), da mais nova à mais antiga, no máximo `limite`. A aberta entra porque o cliente corrige
  # um dado enquanto ela corre, e o especialista precisa ver o nome que deu ao bem (revisão da chat#615). São as BASES
  # de recotação que o especialista do ramo lê (`Specialists::Materia`). Sem ramo (especialista que a Autonom.ia não
  # mantém), todos os bens.
  def self.ultimas_cotadas(conversation_id, ramo:, limite: 5)
    return [] if conversation_id.blank?

    execucoes(conversation_id).where("status IN ('pending', 'running') OR COALESCE(handle ->> 'quote_id', '') <> ''")
                              .order(created_at: :desc, id: :desc)
                              .select { |run| ramo.blank? || ::Autonomia::Insurance::Faixa.do_ramo?(run.faixa, ramo) }
                              .uniq(&:faixa).first(limite)
  end

  # -> a leitura da cotação mais nova da conversa (da `faixa`, quando vem), ou nil quando não há.
  def self.da_conversa(conversation_id, faixa: nil)
    run = execucao_mais_nova(conversation_id, faixa: faixa)
    run && new(run)
  end

  # -> a leitura da cotação mais nova que ainda corre na conversa, de qualquer produto, ou nil. Com auto e
  # residencial juntos, a mais nova pode já ter fechado enquanto a outra ainda recebe resposta.
  def self.correndo_na_conversa(conversation_id)
    return nil if conversation_id.blank?

    execucoes(conversation_id).where(status: 'running').order(created_at: :desc, id: :desc)
                              .map { |run| new(run) }.find(&:correndo?)
  end

  # -> as faixas (produto e bem) com cotação na conversa, fora de `FORA`, do mais novo ao mais antigo. Só as que chegaram
  # ao portal ou ainda correm (revisão da chat#615): a recusada antes do portal não é cotação a ler, e na lista faria o
  # modelo escolher um bem sem preço nenhum.
  def self.produtos(conversation_id)
    return [] if conversation_id.blank?

    execucoes(conversation_id).where.not(status: FORA)
                              .where("status = 'running' OR COALESCE(handle ->> 'quote_id', '') <> ''")
                              .order(created_at: :desc, id: :desc)
                              .pluck(:faixa).compact_blank.uniq
  end

  # O QUE A FERRAMENTA LÊ (chat#612): a faixa da cotação de que o modelo fala, ou a pergunta "de qual?" com a lista.
  Escolha = Struct.new(:faixa, :pergunta)

  # -> a `Escolha` da leitura, a partir do que o modelo pediu em `produto`:
  #   - o nome exato de um bem da lista ("auto:nivus fvu2f42") lê aquele bem;
  #   - só o ramo ("auto") lê o bem do ramo quando ele é o único; com mais de um, pergunta qual;
  #   - nada dito: o ramo do especialista que chama, pela mesma regra; sem especialista, a mais nova da conversa,
  #     menos quando a leitura `exigir` o bem (a proposta: a mais nova pode ser de outro bem, e o PDF sairia trocado).
  # Pedido que não casa com nada da lista vira a pergunta, e não "não há cotação", que seria falso.
  def self.escolha(conversation_id, params, especialista, exigir: false)
    lista = produtos(conversation_id)
    dito = params.to_h['produto'].to_s.squish.downcase.presence
    return escolher(lista, dito) if dito

    ramo = ::Autonomia::Insurance::QuoteAgent::Builder.ramo_do_especialista(especialista)
    return escolher(lista, ramo, sem_bem: ramo) if ramo
    return Escolha.new(nil, pergunta(lista)) if exigir && lista.size > 1

    Escolha.new(nil, nil)
  end

  # `sem_bem`: a faixa a ler quando o ramo não tem bem nenhum na lista (a leitura então diz que não há cotação).
  #
  # O RAMO SOZINHO NUNCA CASA EXATO (revisão da chat#615): "auto" é também a faixa das cotações de antes dos nomes, e
  # casá-la exato leria a cotação velha ao lado da nova do mesmo carro. A velha só é candidata quando o ramo não tem
  # nenhuma com nome.
  def self.escolher(lista, pedido, sem_bem: nil)
    return Escolha.new(pedido, nil) if ::Autonomia::Insurance::Faixa.com_bem?(pedido) && lista.include?(pedido)

    do_ramo = candidatas_do_ramo(lista, pedido)
    return Escolha.new(do_ramo.first, nil) if do_ramo.one?

    sem_um_bem(do_ramo.presence || (sem_bem ? [] : lista), sem_bem || pedido)
  end

  def self.candidatas_do_ramo(lista, ramo)
    todas = lista.select { |faixa| ::Autonomia::Insurance::Faixa.do_ramo?(faixa, ramo) }
    todas.select { |faixa| ::Autonomia::Insurance::Faixa.com_bem?(faixa) }.presence || todas
  end

  # Mais de um candidato: pergunta qual. Nenhum: lê `faixa` (o ramo sem bem, e a leitura diz que não há cotação).
  def self.sem_um_bem(candidatos, faixa)
    candidatos.empty? ? Escolha.new(faixa, nil) : Escolha.new(nil, pergunta(candidatos))
  end

  def self.pergunta(lista)
    "Esta conversa tem cotação de: #{lista.join('; ')}. Chame de novo com produto igual a um desses; se não ficou " \
      'claro de qual o cliente fala, pergunte a ele.'
  end
  private_class_method :escolher, :candidatas_do_ramo, :sem_um_bem, :pergunta

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

  # -> o que esta seguradora cotou, em português para o modelo (`CoberturaDevolvida#texto`), ou nil (chat#585).
  def cobertura(codigo)
    ::Autonomia::Insurance::CoberturaDevolvida.texto(entrada(codigo)['cobertura'])
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
    nao_respondeu_a_tempo?(codigo) ? Guardado::SEM_PROPOSTA : entrada(codigo)['desfecho']
  end

  # -> a categoria do motivo guardada (`MotivoDaRecusa::CATEGORIAS`), ou nil. O que foi guardado fora dessas
  # categorias não conta como motivo. A seguradora que ainda aguardava quando a cotação acabou não respondeu a
  # tempo: é instabilidade dela, não recusa do risco (23/09/2026, a Mitsui do residencial).
  def motivo(codigo)
    return ::Autonomia::Insurance::MotivoDaRecusa::INSTABILIDADE if nao_respondeu_a_tempo?(codigo)

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

  def nao_respondeu_a_tempo?(codigo)
    entrada(codigo)['desfecho'] == Guardado::AGUARDANDO && !correndo?
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
