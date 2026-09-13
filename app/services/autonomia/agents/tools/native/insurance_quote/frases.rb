# AS FRASES QUE A COTAÇÃO DIZ AO CLIENTE — quem as escreve, e o que sai quando ele não escreve.
#
# Até 12/09/2026 cada uma destas quatorze frases era uma constante em Ruby: o mesmo texto, palavra
# por palavra, para todo cliente de toda corretora, ao lado de um especialista que passa o turno
# inteiro escrevendo com as palavras dele. Decisão do CEO: elas passam a ser ESCRITAS PELO
# ESPECIALISTA, no PEDIDO — parâmetros da chamada da ferramenta, sem uma chamada de modelo a mais.
#
# O QUE CONTINUA SENDO DO CÓDIGO, e a lista é fechada: valor em reais e período, nome da seguradora,
# o molde do item da lista, o nome do arquivo PDF, os rótulos de campo e a lista de ramos. Nenhuma
# frase daqui carrega número, contagem, valor, prazo ou nome de seguradora — quem cobra isso é
# `TextoAoCliente.vetar`.
#
# ESTA TABELA É O ÍNDICE, NÃO A CASA DOS TEXTOS: cada constante de recuo continua morando no arquivo
# do assunto dela (a abertura de preços em `QuoteOffers`, o que falta em `Recusas`, o desfecho em
# `Declaracao`, a legenda em `Comparativo`). O que é desta tabela é a ORDEM, a chave de cada papel e
# o que o especialista lê para escrever a frase.
#
# TRÊS GARANTIAS, e nenhuma delas depende de o modelo colaborar:
#
#   1. TODO PAPEL PRODUZ PALAVRA. `de` é total: parâmetro ausente, execução antiga que nem conhecia o
#      nó, agente sem manual, frase em branco ou reprovada — todos recuam para a constante. É o que
#      sustenta "não aceito regressão: todo estado que hoje produz palavra ao cliente continua
#      produzindo".
#   2. OS QUATORZE TEXTOS DE UMA EXECUÇÃO SÃO DOIS A DOIS DISTINTOS. A identidade de uma entrega é o
#      SHA do texto, num espaço por execução (`ToolRun#delivery_token`): duas frases iguais fariam a
#      segunda ser lida como já publicada, e o cliente ficaria sem saber, por exemplo, que faltava a
#      placa. A prova está em `sem_repetir`.
#   3. NUNCA LEVANTA. Uma frase mal formada não pode calar o fecho — ver `Tools::Encerramento`.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Frases
  # O NOME DO NÓ NÃO PODE COLIDIR COM CAMPO DO ADAPTER. `Parametros#grupos` põe as raízes do
  # `quote/schema` por último e `Native::Base.objeto` monta `properties` por `to_h`: um campo de raiz
  # com este nome apagaria o nó em silêncio e duplicaria a chave em `required` — o que a OpenAI
  # responde com HTTP 400 na chamada INTEIRA (medido em 12/09/2026), a mesma classe de falha que
  # deixou a Lia muda em 08/09. Duas defesas, e não uma: um nome em português com sublinhado, que o
  # vocabulário camelCase do adapter não produz, e a falha dura de `Base.objeto`, que não depende
  # deste nome nem de spec nenhuma rodar em produção.
  NO = 'frases_ao_cliente'.freeze

  # A ORDEM É PARTE DA GARANTIA 2: o desempate por repetição recua o papel que vem DEPOIS, e uma
  # ordem estável faz duas passadas sobre os mesmos argumentos escolherem os mesmos textos — sem
  # isso, a identidade da entrega mudaria entre a emissão e a pergunta do fecho.
  ORDEM = %i[espera primeiros_precos mais_um_preco mais_precos aviso_sem_bonus comparativo_legenda
             comparativo_reserva falta_dado pedido_do_que_falta sem_veiculo ramo_desconhecido
             falhou incerto fecho_com_resultado].freeze

  # O que o especialista lê para escrever cada frase. É instrução de agente: sem crase (o modelo a
  # copia para o WhatsApp) e sem travessão (idem).
  DESCRICOES = {
    espera: 'Frase que diz que você recebeu o pedido e já está cuidando dele, e que volta assim que ' \
            'tiver notícia. Ela sai ANTES de o pedido chegar às seguradoras: não afirme que já foi ' \
            'enviado a elas.',
    primeiros_precos: 'Frase curta que apresenta o PRIMEIRO lote de preços. Termine com dois pontos: ' \
                      'a lista vem logo abaixo dela.',
    mais_um_preco: 'Frase curta que apresenta MAIS UMA opção da MESMA cotação. Termine com dois pontos.',
    mais_precos: 'Frase curta que apresenta MAIS opções da MESMA cotação. Não diga quantas. Termine ' \
                 'com dois pontos.',
    aviso_sem_bonus: 'Aviso que sai junto do primeiro preço quando a renovação foi cotada sem a classe ' \
                     'de bônus: diga que estes preços são os de quem faz o primeiro seguro, e que com a ' \
                     'classe de bônus da apólice atual você refaz a cotação.',
    comparativo_legenda: 'Legenda curta que sai junto do arquivo PDF com o comparativo.',
    comparativo_reserva: 'Frase curta sobre o comparativo em PDF, guardada junto do arquivo. Não escreva ' \
                         'link nem endereço de site.',
    falta_dado: 'Frase para quando falta uma informação e não há como dizer qual.',
    pedido_do_que_falta: 'Frase que abre o pedido dos dados que faltam. Não escreva os dados: a lista ' \
                         'deles é acrescentada depois da sua frase. Termine com dois pontos.',
    sem_veiculo: 'Frase que pede a placa do veículo, ou o chassi quando ele ainda não tem placa.',
    ramo_desconhecido: 'Frase que diz que você não cota esse tipo de seguro por aqui. Não liste os ' \
                       'ramos: a lista do que a corretora cota é acrescentada depois da sua frase.',
    falhou: 'Frase para quando a cotação não pôde ser concluída e um atendente vai retomar.',
    incerto: 'Frase para quando não foi possível confirmar se a cotação chegou a ser aberta, e um ' \
             'atendente vai conferir.',
    fecho_com_resultado: 'Frase que encerra a busca para quem já recebeu preços. Não diga que alguma ' \
                         'seguradora deixou de responder.'
  }.freeze

  # O que o modelo lê no nó inteiro. As proibições ficam AQUI, e não repetidas em cada folha: é o
  # texto que ele lê uma vez antes de escrever as quatorze.
  DESCRICAO_DO_NO = 'As frases que o CLIENTE vai ler em cada momento desta cotação, com as SUAS ' \
                    'palavras. Escreva todas as quatorze, curtas, em português do Brasil, no tom da ' \
                    'conversa. Em nenhuma delas escreva número, quantidade, valor, prazo ou nome de ' \
                    'seguradora: esses são acrescentados pelo sistema. Não use travessão nem acento ' \
                    'grave. Cada frase sai sozinha numa mensagem, então ela precisa fazer sentido ' \
                    'sem as outras.'.freeze

  module_function

  # O nó, na forma que `Native::Base#objeto` monta: um `object` com as quatorze folhas, o nó e as
  # folhas OBRIGATÓRIOS. Obrigatório e não anulável de propósito (medido em 12/09/2026): em `strict`
  # o modelo não consegue omitir nem mandar `null`, o que elimina por construção a entrega sem
  # frase, e custa 29 tokens por turno a menos que a forma anulável — o `"null"` de cada folha é
  # token pago. Presença o schema garante; CONTEÚDO não, e é por isso que `de` ainda recua.
  def parametro
    { 'name' => NO, 'type' => 'object', 'description' => DESCRICAO_DO_NO,
      'properties' => ORDEM.map { |papel| folha(papel) } }
  end

  def folha(papel)
    { 'name' => papel.to_s, 'type' => 'string', 'description' => DESCRICOES.fetch(papel) }
  end

  # -> { papel => texto }, os quatorze, sempre. Função PURA dos argumentos da chamada: a mesma
  # resposta na ferramenta, no motor e no encerramento, que é o que faz a identidade de uma entrega
  # ser a mesma nos três lugares.
  #
  # DUAS RAZÕES PARA RECUAR, e as duas caem na mesma constante: a frase não passou na peneira
  # (`TextoAoCliente.vetar`), ou ela é igual à constante de OUTRO papel — que reabriria a colisão de
  # identidade que a garantia 2 fecha.
  def de(argumentos)
    escritas = escritas_pelo_especialista(argumentos)

    sem_repetir(ORDEM.index_with { |papel| escritas[papel] || constantes.fetch(papel) })
  end

  # As constantes de recuo, cada uma lida do arquivo que declara o assunto dela — nenhum texto é
  # digitado duas vezes. `frases_spec` prova que as quatorze passam pela peneira e que são
  # distintas entre si: sem a primeira metade o recuo publicaria justamente o que a peneira proíbe,
  # e sem a segunda a garantia 2 não se fecharia.
  #
  # Nomes inteiros porque `module A::B::C` não enxerga os irmãos pelo nome curto.
  def constantes
    @constantes ||= begin
      quote = ::Autonomia::Agents::Tools::Native::InsuranceQuote
      { espera: quote::Declaracao::ESPERANDO,
        primeiros_precos: ::Autonomia::Insurance::QuoteOffers::PRIMEIROS_PRECOS,
        mais_um_preco: ::Autonomia::Insurance::QuoteOffers::MAIS_UM_PRECO,
        mais_precos: ::Autonomia::Insurance::QuoteOffers::MAIS_PRECOS,
        aviso_sem_bonus: quote::AVISO_SEM_BONUS,
        comparativo_legenda: quote::Comparativo::LEGENDA,
        comparativo_reserva: quote::Comparativo::RESERVA,
        falta_dado: quote::Recusas::FALTA_ALGO,
        pedido_do_que_falta: quote::Recusas::PEDIDO_DO_QUE_FALTA,
        sem_veiculo: quote::Recusas::SEM_VEICULO_CLIENTE,
        ramo_desconhecido: quote::Recusas::RAMO_DESCONHECIDO_ABERTURA,
        falhou: quote::Declaracao::FALHOU,
        incerto: quote::Declaracao::INCERTO,
        fecho_com_resultado: quote::Declaracao::FECHO_COM_RESULTADO }.freeze
    end
  end

  # O que o especialista escreveu e passou na peneira, por papel. O nó ausente (execução aberta antes
  # desta versão, ferramenta montada sem argumentos) devolve vazio, e todos recuam.
  #
  # `is_a?(Hash)` nos dois níveis, e não `to_h`: os argumentos são lidos da linha, e `to_h` sobre o
  # que não for Hash levanta — dentro do fecho, levantar é o cliente sem uma palavra.
  def escritas_pelo_especialista(argumentos)
    return {} unless argumentos.is_a?(Hash)

    no = no_das_frases(argumentos)
    return {} if no.empty?

    ORDEM.each_with_object({}) do |papel, escritas|
      texto = ::Autonomia::Agents::Tools::TextoAoCliente.vetar(no[papel.to_s])
      escritas[papel] = texto if texto && !constante_de_outro_papel?(papel, texto)
    end
  end

  # SÓ A CHAVE, E NÃO O HASH INTEIRO. Era `argumentos.deep_stringify_keys[NO]`: copiava junto o
  # formulário da cotação — os ~90 campos de auto, até dezenas de KB — para ler um nó de quatorze
  # frases, e isso umas seis vezes por fecho (`FRASES_DE_FECHO` são quatro papéis, cada um resolvido
  # e mais a constante, sem memória entre as chamadas). A chave é lida nas duas grafias porque o
  # `arguments` vem da linha com chave de texto e a ferramenta em memória pode carregá-lo com
  # símbolo. Só o NÓ é normalizado, e ele tem um nível só: as folhas são texto.
  def no_das_frases(argumentos)
    no = argumentos[NO] || argumentos[NO.to_sym]
    no.is_a?(Hash) ? no.stringify_keys : {}
  end

  # A frase do especialista que copia a constante de outro papel é recusada: sem isso, o papel dono
  # dessa constante recuaria para um texto que outro já publicou, e o desempate abaixo não teria para
  # onde recuar. É esta regra que torna a garantia 2 uma prova, e não uma aposta.
  def constante_de_outro_papel?(papel, texto)
    constantes.any? { |outro, constante| outro != papel && constante == texto }
  end

  # O DESEMPATE, em ordem fixa: o papel que repete um texto já usado recua para a própria constante.
  # Ela não pode estar tomada — só estaria se outro papel tivesse terminado com ela, o que exigiria
  # ou que esse papel fosse este (impossível, a ordem é única) ou que uma frase do especialista
  # igualasse essa constante (impedido por `constante_de_outro_papel?`).
  def sem_repetir(textos)
    vistos = {}
    textos.each_with_object({}) do |(papel, texto), saida|
      texto = constantes.fetch(papel) if vistos.key?(texto)
      vistos[texto] = papel
      saida[papel] = texto
    end
  end
end
