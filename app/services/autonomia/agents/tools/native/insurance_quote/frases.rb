# AS FRASES QUE A COTAÇÃO DIZ AO CLIENTE — quem as escreve, e o que sai quando ele não escreve.
#
# Até 12/09/2026 cada uma destas frases (hoje doze) era uma constante em Ruby: o mesmo texto, palavra
# por palavra, para todo cliente de toda corretora, ao lado de um especialista que passa o turno
# inteiro escrevendo com as palavras dele. Decisão do CEO: elas passam a ser ESCRITAS PELO
# ESPECIALISTA, no PEDIDO — parâmetros da chamada da ferramenta, sem uma chamada de modelo a mais.
#
# O QUE CONTINUA SENDO DO CÓDIGO, e a lista é fechada: o nome do arquivo PDF, os rótulos de campo e a
# lista de ramos. Valor em reais e nome de seguradora deixaram de ser (fatia 3 do #420): quem os
# escreve é a Lia, quando o cliente pergunta. Nenhuma frase daqui carrega número, contagem, valor,
# prazo ou nome de seguradora — quem cobra isso é `TextoAoCliente.vetar`.
#
# ESTA TABELA É O ÍNDICE, NÃO A CASA DOS TEXTOS: cada constante de recuo continua morando no arquivo
# do assunto dela (o que falta em `Recusas`, o desfecho em `Declaracao`, a legenda em `Comparativo`). O que é
# desta tabela é a ORDEM, a chave de cada papel e
# o que o especialista lê para escrever a frase.
#
# TRÊS GARANTIAS, e nenhuma delas depende de o modelo colaborar:
#
#   1. TODO PAPEL PRODUZ PALAVRA. `de` é total: parâmetro ausente, execução antiga que nem conhecia o
#      nó, agente sem manual, frase em branco ou reprovada — todos recuam para a constante. É o que
#      sustenta "não aceito regressão: todo estado que hoje produz palavra ao cliente continua
#      produzindo".
#   2. OS DOZE TEXTOS DE UMA EXECUÇÃO SÃO DOIS A DOIS DISTINTOS. A identidade de uma entrega é o
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
  ORDEM = %i[espera aviso_sem_bonus comparativo_legenda comparativo_reserva falta_dado pedido_do_que_falta
             sem_veiculo ramo_desconhecido falhou incerto fecho_com_resultado valores_na_conversa].freeze

  # O que o especialista lê para escrever cada frase. É instrução de agente: sem crase (o modelo a
  # copia para o WhatsApp) e sem travessão (idem).
  #
  # DIREÇÃO, NÃO RÓTULO DE CAMPO (21/09/2026). Até aqui cada descrição dizia o que o SLOT era ("Frase que
  # encerra a busca para quem já recebeu o comparativo"), e o modelo preenchia slot com voz de slot: "A
  # busca foi concluída e o comparativo está pronto para você." Ele devolveu a nossa palavra. Agora cada
  # uma descreve o MOMENTO do ponto de vista da pessoa e o que ela precisa ouvir ali; as palavras são dele.
  # Nenhuma traz frase de exemplo, de propósito: exemplo é copiado inteiro, e sai igual para todo cliente.
  # Quem entende como uma pessoa fala é o modelo; o que ele precisa de nós é saber onde está e com quem fala.
  DESCRICOES = {
    espera: 'A pessoa acabou de te passar o que você precisava, e às vezes esta frase sai de novo se a cotação demorar. Ela quer saber ' \
            'que você pegou o pedido dela e está nisso. Diga o que você está fazendo por ela, na primeira pessoa, e que volta quando ' \
            'tiver o que mostrar. Não afirme que o pedido já chegou às seguradoras, nem que ainda não chegou.',
    aviso_sem_bonus: 'Vai junto das opções quando a pessoa está renovando e você cotou sem a classe de bônus da apólice dela. Ela vai ' \
                     'estranhar os preços, e precisa entender o porquê do jeito que você explicaria a um cliente: esses são os preços de ' \
                     'quem faz o primeiro seguro, e com a classe de bônus da apólice atual você refaz a cotação.',
    comparativo_legenda: 'Acompanha o arquivo com as opções que você encontrou para ela, e quase sempre é a última mensagem desta ' \
                         'cotação. Fale do que ela tem nas mãos agora e do que pode fazer com isso, como quem entrega um trabalho feito ' \
                         'para ela, e não do arquivo nem de como ele foi feito.',
    comparativo_reserva: 'Vai guardada com o arquivo e aparece quando ele não pode ser mostrado como anexo. O mesmo sentido da legenda, ' \
                         'dito de outro jeito. Não escreva link nem endereço de site.',
    falta_dado: 'Falta alguma coisa para você cotar e não dá para dizer o quê. Peça ajuda como uma pessoa pediria, sem soar como erro de ' \
                'sistema.',
    pedido_do_que_falta: 'Abre o pedido do que ainda falta para você cotar. Os itens entram logo depois da sua frase, então não os ' \
                         'escreva. Fale como quem está quase lá junto com ela, não como formulário. Termine com dois pontos.',
    sem_veiculo: 'Você ainda não sabe qual é o carro dela. Peça a placa, ou o chassi se ele ainda não tiver placa, do jeito que você ' \
                 'pediria a alguém no WhatsApp.',
    ramo_desconhecido: 'A pessoa pediu um seguro que a corretora não cota por aqui. O que a corretora cota entra logo depois da sua ' \
                       'frase, então não o liste. Diga que esse você não consegue por aqui sem soar como recusa de sistema, e deixe a ' \
                       'porta aberta para o que dá.',
    falhou: 'Você não conseguiu fazer a cotação agora, e alguém da equipe vai assumir daqui. Diga isso com honestidade e sem drama, na ' \
            'primeira pessoa.',
    incerto: 'Você não tem certeza se o pedido chegou às seguradoras, e alguém da equipe vai conferir e retomar. Diga o que você sabe e o ' \
             'que vai acontecer, sem esconder a dúvida e sem alarmar.',
    fecho_com_resultado: 'O tempo desta cotação acabou depois que ela já recebeu opções. Ela precisa saber que o que recebeu é o que tem, ' \
                         'e o que pode fazer agora: você refaz a cotação ou chama alguém da equipe. Não diga que alguma resposta ficou ' \
                         'faltando.',
    valores_na_conversa: 'Você tem os preços, mas o arquivo com as opções não pôde ser enviado. Diga que os valores estão com você e que ' \
                         'ela pode te pedir aqui mesmo.'
  }.freeze

  # O que o modelo lê no nó inteiro. As proibições ficam AQUI, e não repetidas em cada folha: é o
  # texto que ele lê uma vez antes de escrever as doze.
  #
  # QUEM FALA É VOCÊ, E A PESSOA NÃO SABE QUE EXISTE ESPECIALISTA (21/09/2026). A voz que as frases
  # tinham era impessoal ("a cotação está em andamento", "o comparativo está pronto"): processo sem
  # sujeito, que é o jeito de sistema falar. A Gabriela, a IA do Rodrigo que já soa como gente, diz o
  # que ELA vai fazer. É isso que o nó pede antes de tudo.
  DESCRICAO_DO_NO = 'As frases que o CLIENTE vai ler durante esta cotação. Quem fala nelas é você, a mesma pessoa que está conversando ' \
                    'com ele, e ele não sabe que existe um especialista por trás. Escreva na primeira pessoa, com você fazendo as coisas ' \
                    'por ele, e nunca como processo sem sujeito: gente não diz que algo foi concluído ou está em andamento, diz o que fez ' \
                    'e o que vai fazer. Escreva como alguém da corretora escreveria no WhatsApp para um cliente: curto, direto, caloroso ' \
                    'sem exagero. As descrições abaixo dizem o momento de cada frase, não as palavras; não copie palavra delas. Escreva ' \
                    'todas as doze, em português do Brasil, e duas nunca podem ser iguais. Em nenhuma escreva número, quantidade, valor, ' \
                    'prazo ou nome de seguradora. Não use travessão nem acento grave. Cada frase sai sozinha numa mensagem, então precisa ' \
                    'fazer sentido sem as outras.'.freeze

  module_function

  # O nó, na forma que `Native::Base#objeto` monta: um `object` com as doze folhas, o nó e as
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

  # -> { papel => texto }, os doze, sempre. Função PURA dos argumentos da chamada: a mesma
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

  # -> os papéis cuja constante de recuo aparece neste texto. O publicador pergunta isto de toda mensagem
  # que cria e registra no log cada recuo que saiu (`AsyncPublisher#registrar_recuos`). `include?`, e não
  # igualdade: o pedido do que falta e o ramo desconhecido saem com a lista depois da frase, e o aviso sem
  # bônus sai dentro da legenda do comparativo.
  def recuos_em(texto)
    texto = texto.to_s
    constantes.select { |_papel, constante| texto.include?(constante) }.keys
  end

  # As constantes de recuo, cada uma lida do arquivo que declara o assunto dela — nenhum texto é
  # digitado duas vezes. `frases_spec` prova que as doze passam pela peneira e que são
  # distintas entre si: sem a primeira metade o recuo publicaria justamente o que a peneira proíbe,
  # e sem a segunda a garantia 2 não se fecharia.
  #
  # Nomes inteiros porque `module A::B::C` não enxerga os irmãos pelo nome curto.
  def constantes
    @constantes ||= begin
      quote = ::Autonomia::Agents::Tools::Native::InsuranceQuote
      { espera: quote::Declaracao::ESPERANDO,
        aviso_sem_bonus: quote::AVISO_SEM_BONUS,
        comparativo_legenda: quote::Comparativo::LEGENDA,
        comparativo_reserva: quote::Comparativo::RESERVA,
        falta_dado: quote::Recusas::FALTA_ALGO,
        pedido_do_que_falta: quote::Recusas::PEDIDO_DO_QUE_FALTA,
        sem_veiculo: quote::Recusas::SEM_VEICULO_CLIENTE,
        ramo_desconhecido: quote::Recusas::RAMO_DESCONHECIDO_ABERTURA,
        falhou: quote::Declaracao::FALHOU,
        incerto: quote::Declaracao::INCERTO,
        fecho_com_resultado: quote::Declaracao::FECHO_COM_RESULTADO,
        valores_na_conversa: quote::Declaracao::VALORES_NA_CONVERSA }.freeze
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
  # formulário da cotação — os ~90 campos de auto, até dezenas de KB — para ler um nó de doze
  # frases, e isso umas seis vezes por fecho (`FRASES_DE_FECHO` são cinco papéis, cada um resolvido
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
