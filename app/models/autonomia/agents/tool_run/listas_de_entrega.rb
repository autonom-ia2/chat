# AS LISTAS DE IDENTIDADE DO HANDLE (entrega 8a) — quem escreve, e o que cada uma prova.
#
# São duas, e elas respondem a metades diferentes da mesma pergunta ("o cliente recebeu o
# resultado?"): o ACEITE diz QUAIS entregas o publicador assumiu, e é o motor quem a escreve
# (`Tools::EntregaAceita`); a lista da FERRAMENTA diz o que cada identidade É — um preço, e não a
# pergunta pelo dado que falta —, porque só ela conhece o texto de onde o token nasce. O contador
# (`record_delivery!`) não serve para nada disso: ele soma qualquer item aceito.
#
# Separado de `ToolRun` pelo mesmo motivo de `InsuranceQuote::Fecho`: é outro assunto, e a classe
# estava no teto de linhas.
module Autonomia::Agents::ToolRun::ListasDeEntrega
  extend ActiveSupport::Concern

  # O QUE O PUBLICADOR ACEITOU (entrega 8a): a lista das identidades de entrega que voltaram
  # `published` ou `deferred`. É o REGISTRO DO ACEITE — o que separa "eu tentei entregar" de "o
  # publicador assumiu esta entrega" —, e quem o escreve é sempre quem publicou
  # (`Tools::EntregaAceita`). A recusa não escreve nada. É MARCA DO MOTOR (`AsyncRunJob::MARCAS`):
  # a ferramenta não a vê no handle que recebe e não pode escrevê-la.
  ENTREGAS_ACEITAS = 'autonomia_entregas_aceitas'.freeze

  # ACRESCENTA À LISTA DO ACEITE a identidade de uma entrega que o publicador assumiu.
  #
  # O IRMÃO DE `record_delivery!`: aquele conta QUANTAS entregas foram aceitas, esta diz QUAIS.
  #
  # ESCRITA NA HORA DO ACEITE, E NÃO NO FIM DA PASSADA. O que ela compra é o ADIAMENTO: a
  # publicação adiada é aceita e ainda não é mensagem, e sem este registro o fecho não tinha como
  # saber disso (rodada 4). O que ela NÃO compra, e o texto daqui afirmava até a rodada 5, é
  # impedir "não consegui" ao lado do preço: o portão externo do fecho é `delivered_count`
  # (`Encerramento#fecho`), gravado no `record_delivery!` que vem DEPOIS desta escrita — morto o
  # processo entre as duas, a frase de falha sai do mesmo jeito.
  #
  # A OUTRA METADE DO CRUZAMENTO é a lista da ferramenta, escrita pelo mesmo caminho
  # (`registrar_identidade_emitida!`) na hora da emissão. AS DUAS NÃO TÊM A MESMA DURABILIDADE, e
  # o texto daqui afirmou o contrário na rodada 5: esta é MARCA do motor, então o `record_attempt!`
  # do fim da passada não passa por cima dela; a da ferramenta viaja também no handle e É regravada
  # por ele com a cópia em memória — uma passada com handle velho apaga o token que outra acabou de
  # gravar. Medido na rodada 6 e registrado na issue R19 (#418); o que a escrita imediata comprou foi a
  # janela da morte de processo, não a do entrelaçamento.
  #
  # A FALHA DESTA ESCRITA NÃO É O FIM: o token fica pendente em memória e o `record_attempt!` do
  # fim da passada o reescreve (`reforcar_aceites!`) — é a rede que a identidade sempre teve, e que
  # o aceite não tinha. Morta a passada, perdem-se as duas metades juntas, como já era.
  def registrar_entrega_aceita!(token)
    anexar_ao_handle!(ENTREGAS_ACEITAS, token)
  rescue StandardError
    @aceites_pendentes = aceites_pendentes | [token.to_s]
    raise
  end

  # A IDENTIDADE DE UMA ENTREGA QUE A FERRAMENTA EMITIU, na chave DELA. A chave nomeia a NATUREZA
  # da entrega (`entregas_de_preco`) e o token é a IDENTIDADE dela.
  #
  # A CHAVE É DA FERRAMENTA, E O GUARDA-CORPO É O MESMO DE SEMPRE: ela não vê (`tool_handle`) nem
  # escreve (`parte_da_ferramenta`) as marcas do motor, e sem esta recusa este método seria a porta
  # dos fundos — uma ferramenta poderia inventar um aceite, ou pôr `autonomia_closed` no handle e
  # calar o encerramento de todas as passadas seguintes. Nenhum chamador de hoje tenta; a guarda
  # existe para que o próximo não consiga. A lista das marcas é lida de `AsyncRunJob::MARCAS`, que
  # é onde ela já mora — duas definições da mesma fronteira divergiriam no dia em que ela mudasse.
  def registrar_identidade_emitida!(chave, token)
    raise ArgumentError, "#{chave} e uma marca do motor" if marca_do_motor?(chave)

    anexar_ao_handle!(chave, token)
  end

  private

  # ACRESCENTA UM TOKEN A UMA LISTA DO HANDLE, no banco, em UM UPDATE. As duas listas passam por
  # aqui, e as duas precisam ser duráveis NO INSTANTE em que o fato acontece.
  #
  # PRIVADA, E COM DOIS NOMES POR NATUREZA NA FRENTE (rodada 6): pública e aceitando qualquer
  # chave, ela contornava o guarda-corpo que impede a ferramenta de escrever marca do motor.
  #
  # SEM LER-MODIFICAR-ESCREVER: a lista é concatenada pelo BANCO (`|| ?::jsonb`), então dois
  # escritores da mesma execução não apagam um o token do outro. O `WHERE` com `@>` torna a escrita
  # idempotente — o retry do Sidekiq que republica a mesma entrega (e recebe `published` pela dedupe
  # do token), ou a consulta que reemite o mesmo lote, não acrescenta uma segunda cópia. `COALESCE`
  # nos dois lados porque a chave só existe depois do primeiro token, e `?::text` nos dois usos da
  # chave porque `handle -> <literal sem tipo>` é ambíguo entre o operador de chave e o de índice.
  #
  # NÃO É GUARDADA PELO STATUS, de propósito: o aceite e a emissão são fatos consumados, e uma
  # linha que acabou de ser supersedida não pode fazer a escrita do que JÁ saiu virar um no-op.
  def anexar_ao_handle!(chave, token)
    lista = "COALESCE(handle -> ?::text, '[]'::jsonb)"
    escrita = "handle = jsonb_set(handle, ARRAY[?::text], #{lista} || ?::jsonb), updated_at = ?"
    updated = self.class.where(id: id)
                  .where.not("#{lista} @> ?::jsonb", chave, [token].to_json)
                  .update_all([escrita, chave, chave, [token].to_json, Time.current]) # rubocop:disable Rails/SkipsModelValidations
    reload
    updated.positive?
  end

  def marca_do_motor?(chave)
    ::Autonomia::Agents::Tools::AsyncRunJob::MARCAS.include?(chave.to_s)
  end

  # Os aceites cuja escrita imediata falhou, guardados só em MEMÓRIA e só enquanto esta passada
  # viver. Não é fila: é o mesmo fato esperando a segunda escrita, do mesmo jeito que a identidade
  # da entrega espera o `record_attempt!` no handle que a ferramenta devolveu.
  def aceites_pendentes
    @aceites_pendentes ||= []
  end

  # A SEGUNDA (E ÚLTIMA) CHANCE DA LISTA DO ACEITE, no fim da passada (`record_attempt!`). Nunca
  # levanta: derrubar a escrita do handle por causa do reforço trocaria um fecho calado por uma
  # passada perdida. O que falhar de novo volta à lista, e morre com o processo — que é exatamente
  # o alcance da rede da identidade.
  def reforcar_aceites!
    pendentes = aceites_pendentes
    return false if pendentes.empty?

    @aceites_pendentes = []
    pendentes.each { |token| reescrever_aceite(token) }
    aceites_pendentes.empty?
  end

  def reescrever_aceite(token)
    registrar_entrega_aceita!(token)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] reforco do aceite falhou run=#{id} #{e.class}")
  end
end
