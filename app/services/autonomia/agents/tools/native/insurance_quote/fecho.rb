# O QUE A COTAÇÃO ENTREGA — E O QUE ELA AFIRMA — QUANDO A EXECUÇÃO ACABA SEM FECHAR (entregas 4 e 8).
#
# Três respostas ao `Tools::Encerramento`, e nenhuma delas é do motor: o que ainda vale entregar, se
# o cliente já tem RESULTADO em mãos e se SOBROU alguma coisa. As duas últimas decidem entre a frase
# parcial e o silêncio, e só a ferramenta sabe respondê-las — `delivered_count` conta qualquer item
# aceito para publicação, inclusive a pergunta pelo dado que falta.
#
# TODAS AS TRÊS DECIDEM PELO ACEITE, NUNCA PELA EMISSÃO. São coisas diferentes, e o handle só
# conhece a segunda: `deliver` roda ANTES de `record_attempt!`, então uma entrega RECUSADA avança o
# handle com os códigos das ofertas sem que publicação nenhuma tenha sido assumida. Com a pergunta
# feita ao handle, o cliente que não recebeu preço nenhum lia "os preços acima são os que chegaram"
# — sem nada acima — e o motor ainda pedia ao portal um comparativo para ninguém.
#
# E A PERGUNTA TAMBÉM NÃO É PELA MENSAGEM. Ela foi, na rodada 2, e criou o defeito simétrico: a
# publicação ADIADA (a cadeia de entrega humanizada do turno em curso, até 90 s) é aceita e ainda
# não é mensagem. Nessa janela — que é o caminho NORMAL, não uma avaria — o fecho lia "nenhum preço
# chegou", não pedia o comparativo e não dizia uma palavra. O cliente recebia os preços pelo job
# adiado e mais nada.
#
# O ACEITE é o que o publicador de fato decidiu, e ele é gravado na hora
# (`Tools::EntregaAceita`, uma lista na LINHA): aceita imediata ou adiada, grava; recusada, não
# grava nada. As IDENTIDADES que esta execução emitiu — `PRECOS_KEY`, `COMPARATIVO_KEY` — são a
# tabela de consulta de quem pergunta: a identidade diz o que procurar, a lista do aceite diz se foi
# assumido.
#
# AS DUAS METADES DO CRUZAMENTO NÃO TÊM A MESMA DURABILIDADE — e a rodada 5 afirmou que sim, o que
# é falso (medido na rodada 6, issue R19 / #418). A identidade do preço passou a ir ao banco na
# hora da EMISSÃO, pela mesma escrita de uma linha (`ToolRun#registrar_identidade_emitida!`) que
# grava a lista do aceite, e isso fecha UMA janela: a da morte do processo entre o aceite e o fim da
# passada, que deixava o cliente com o preço na tela e o fecho em silêncio. NÃO fecha a outra: esta
# lista viaja TAMBÉM no handle da ferramenta, e o `record_attempt!` do fim da passada a REGRAVA com
# a cópia em memória — duas passadas sobre a mesma linha (o retry do Sidekiq, o varredor cruzando
# com o motor) e o token da primeira some. A lista do ACEITE não sofre isso porque é uma MARCA do
# motor (`AsyncRunJob::MARCAS`), que o `record_attempt!` não toca.
#
# A saída candidata — ler esta lista pela LINHA, como o aceite já é lido — está na R19 com o custo
# declarado: hoje o handle é a rede de segurança da escrita imediata, e sem ele uma escrita que
# falhe perde a identidade de vez.
#
# (Por que a tabela de consulta é necessária: quem aceita é o publicador, e ele não distingue um
# preço de uma pergunta pelo dado que falta — as duas são "uma entrega". Quem distingue é a
# ferramenta, e ela só sabe o TEXTO na passada que o emite. Emitir sem ser aceito não prova nada;
# é por isso que a lista de emitidos nunca é lida sozinha.)
#
# OS ESCRITORES DESSAS CHAVES MORAM AQUI TAMBÉM, e não na classe: quem grava a identidade e quem a
# lê são o mesmo assunto, e separá-los é como as duas definições do token nasceram. São quatro,
# todos privados — `token_da_entrega`, `registrar_entrega_de_preco`, `marcar_preco_legado` e
# `marcas_do_comparativo` —, chamados pelas passadas de emissão (`precos` e `Comparativo#fechar`).
#
# Separado da ferramenta pelo mesmo motivo de `Comparativo`, `Declaracao`, `Recusas`, `Envio` e
# `Veiculo`: é outro assunto, e a classe está no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Fecho
  extend ActiveSupport::Concern

  # O COMPARATIVO NÃO PODE SER REFÉM DA SEGURADORA MAIS LENTA. Ele era gerado só no ramo `done`,
  # quando o portal marcava a cotação como `completed` — e em 08/09/2026 a execução entregou cinco
  # preços e estourou o prazo na 22ª consulta, então o PDF nunca saiu. O comparativo é o que o
  # cliente leva para decidir; os preços soltos no chat são o resumo dele.
  #
  # MAS ELE É TRABALHO NOVO NO PORTAL: `comparison_pdf` faz login e uma chamada de
  # até 60 s, e o publicador ainda baixa o arquivo. No caminho do VARREDOR isso não sai — lá são até
  # 500 linhas em sequência dentro de um cron, com 25 s de shutdown do Sidekiq, e quem é morto no
  # meio joga o resto do lote para a varredura seguinte, 10 min depois. O cliente fica com os
  # preços que já leu e com o fecho honesto sobre o que ele tem; o PDF do portal continua lá.
  #
  # E NÃO SE PEDE COMPARATIVO PARA QUEM NÃO TEM PREÇO. O comparativo é o complemento dos preços na
  # tela; sem nenhum deles ter sido aceito, gerá-lo é login mais uma chamada de até 60 s por uma
  # entrega que muito provavelmente será recusada pelo mesmo motivo que recusou a primeira — e o
  # cliente precisa, ali, da frase honesta de falha. A pergunta é a do ACEITE
  # (`resultado_entregue?`).
  def closing_deliveries(handle, trabalho_novo: true)
    return [] unless trabalho_novo
    return [] unless resultado_entregue?(handle)

    [comparison_pdf(handle.to_h)].compact
  end

  # RESULTADO DA COTAÇÃO É PREÇO QUE O PUBLICADOR ACEITOU. Nunca o `pedido` — a pergunta pelo dado
  # que falta também é uma entrega aceita (`poll` a devolve, e `delivered_count` a conta), e era por
  # ela que uma cotação que só perguntou dados fechava dizendo "o que chegou está aqui em cima" sem
  # nada em cima. E nunca a lista de `entregues`: ela avança na EMISSÃO, mesmo quando a publicação é
  # recusada.
  #
  # A PROVA LEGADA É UNIÃO, NÃO ALTERNATIVA (rodada 4): a linha que atravessou o deploy tem preço na
  # tela e nenhum token nosso, e uma emissão nova recusada não pode apagar esse preço da conta. Ela
  # também julga ACEITE, e não só emissão (rodada 5) — ver `prova_legada?`.
  #
  # (`self.class::` porque o nome curto não se resolve dentro de um módulo compacto — o mesmo
  # cuidado de `Comparativo`.)
  def resultado_entregue?(handle)
    handle = handle.to_h

    Array(handle[self.class::PRECOS_KEY]).any? { |token| aceita?(token) } || prova_legada?(handle)
  end

  # SOBRA ENQUANTO O PORTAL NÃO TIVER FECHADO — e depois dele, enquanto faltar chegar o que já foi
  # emitido.
  #
  # "Sempre sobra, por construção" era falso, e o estado que o desmente é alcançável HOJE: o
  # `finish!('done')` vem DEPOIS do `record_attempt!` que persistiu o handle, então um worker morto
  # entre os dois deixa a linha `running` com o portal já fechado, e o varredor a encerra. Quem
  # recebeu os preços E o comparativo lia "algumas seguradoras não responderam a tempo".
  #
  # QUEM PROVA QUE O PORTAL FECHOU É `FECHADO_KEY`, e não `PDF_SENT_KEY`: a segunda só é gravada
  # quando houve comparativo a emitir, e uma cotação que fecha sem URL de comparativo não a grava —
  # ler a ausência como "ainda vem coisa" é a mesma frase falsa, pela outra ponta (Codex).
  #
  # A SEGUNDA METADE é o comparativo EMITIDO que não foi aceito: a publicação voltou `blocked` com a
  # sentinela já gravada. Aí sobrou mesmo, e calar seria esconder do cliente que falta algo.
  #
  # A TERCEIRA (fatia 1 do PDF rápido, 13/09/2026) é o comparativo que ainda seria tentado
  # (`Comparativo#comparativo_por_tentar?`): a passada que fechou a cotação não conseguiu o PDF (a
  # geração falhou, ou o publicador não o aceitou) e a execução seguiu para pedir de novo. Se a
  # corrente de jobs morre antes da passada seguinte, quem encerra é o varredor, que não pede
  # comparativo (`trabalho_novo: false`); a resposta verdadeira ali é que sobrou o comparativo.
  # Esgotado o teto sem comparativo, não sobra.
  #
  # As chaves lidas aqui sobrevivem ao corte das marcas do motor (`AsyncRunJob::MARCAS` não as lista),
  # então chegam pelo handle que o encerramento entrega.
  def resta_entregar?(handle)
    handle = handle.to_h
    !portal_fechado?(handle) || comparativo_pendente?(handle) || comparativo_por_tentar?(handle)
  end

  private

  # A IDENTIDADE DA MENSAGEM QUE ESTE PREÇO VAI TER, guardada na passada que o emite — é a única em
  # que se sabe o TEXTO, e é do texto que o token nasce. É TABELA DE CONSULTA, não prova: quem
  # responde "chegou?" é a lista do aceite, e esta lista diz por quais identidades perguntar. O
  # contador da execução não serviria (conta qualquer item aceito, inclusive a pergunta pelo dado
  # que falta) e a lista de `entregues` também não (são códigos de oferta, não identidades de
  # entrega). ACUMULA, porque cada lote de preços é uma mensagem.
  # Sem execução não há token, e aí não se grava nada: o fecho cala, que é o lado conservador.
  #
  # E ELA VAI AO BANCO AGORA, junto do handle que a passada devolve (rodada 5). A outra metade do
  # cruzamento — a lista do ACEITE — é durável no instante do aceite, e esta viajava no handle até
  # o `record_attempt!` do fim da passada: morto o processo entre uma coisa e a outra (deploy, 25 s
  # de shutdown do Sidekiq), o cliente ficava com o preço na tela, o aceite registrado e NENHUMA
  # identidade por onde perguntar — o fecho calava onde a `main` dizia a frase parcial verdadeira.
  #
  # O QUE ISSO NÃO COMPRA (rodada 6, medido): o valor CONTINUA no handle que a passada devolve, e
  # o `record_attempt!` do fim regrava a chave inteira com essa cópia — uma passada que leu o
  # handle ANTES apaga o token que a outra gravou. Dizer que as duas listas ficaram com a mesma
  # durabilidade era falso; ver o cabeçalho e a R19 (#418). O handle continua aqui porque ele é a
  # rede da escrita imediata (`gravar_na_linha` engole a falha), e trocar uma coisa pela outra é a
  # decisão que a issue carrega.
  #
  # `texto` CHEGA AQUI JÁ NA FORMA EM QUE VAI SAIR (12/09/2026). Até esta entrega o token nascia do
  # texto CRU e o `Progress` ainda o aparava e cortava depois; o publicador então calculava o token
  # sobre ESSE outro texto, e `resultado_entregue?` cruzava duas listas de universos diferentes —
  # nunca casava, e nem o comparativo saía. Quem depura agora é `precos`, antes de chamar isto.
  def registrar_entrega_de_preco(texto, handle, already)
    handle = marcar_preco_legado(handle, already)
    token = token_da_entrega(texto)
    return handle if token.blank?

    gravar_na_linha { run.registrar_identidade_emitida!(self.class::PRECOS_KEY, token) }
    handle.merge(self.class::PRECOS_KEY => (Array(handle[self.class::PRECOS_KEY]).map(&:to_s) + [token]).uniq)
  end

  # A ESCRITA IMEDIATA É REFORÇO, NUNCA REQUISITO: o valor segue no handle que a passada devolve, e
  # o `record_attempt!` do fim o persiste como sempre — esta escrita só fecha a janela entre os
  # dois. Falhar aqui degrada para o comportamento de antes, e nunca derruba a passada que acabou
  # de entregar preço ao cliente: o que levantasse subiria para o `advance` do motor, que trataria
  # uma entrega bem-sucedida como falha da consulta.
  def gravar_na_linha
    yield
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] identidade da entrega nao durou run=#{run&.id} #{e.class}")
  end

  # HAVIA PREÇO EMITIDO ANTES DE ESTA VERSÃO COMEÇAR A REGISTRAR O ACEITE? Gravado UMA vez, na
  # primeira passada desta versão que emite preço nesta execução, e é o que dá COBERTURA à prova
  # legada: sem ele, a única maneira de saber se `entregues` guarda preço de antes seria a presença
  # da chave nova — e presença não é cobertura. Uma linha que atravessou o deploy com preço na tela
  # e emitiu um preço novo (recusado) passava a ser julgada só pelo token novo, e o preço antigo
  # sumia da conta: nem comparativo, nem uma palavra, para quem tinha preço na tela.
  #
  # `already` são os códigos que a execução já tinha entregue ANTES deste lote: emitidos por esta
  # versão (e então há token para eles) ou pela anterior (e então não há). Falso é o caso comum — a
  # execução que nasce depois do deploy —, e é ele que impede o fallback de reabrir a frase falsa da
  # rodada 1.
  def marcar_preco_legado(handle, already)
    return handle if handle.key?(self.class::PRECO_LEGADO_KEY)

    handle.merge(self.class::PRECO_LEGADO_KEY => Array(already).any?)
  end

  # AS DUAS MARCAS DO COMPARATIVO, e elas dizem coisas diferentes: `PDF_SENT_KEY` é "já emiti este
  # comparativo" (o que impede a segunda emissão) e `COMPARATIVO_KEY` é a IDENTIDADE da entrega —
  # é por ela que o fecho pergunta à lista do aceite se o publicador a assumiu. Sem execução não
  # há identidade a gravar, e aí sai só a sentinela.
  #
  # A AUSÊNCIA DA IDENTIDADE SE RESOLVE AQUI, e não com um `compact` sobre o handle mesclado: aquele
  # apagava QUALQUER chave nula do handle da ferramenta, não só esta. Hoje nenhuma é nula — a
  # diferença era inerte —, mas um apagamento silencioso de handle é exatamente o tipo de coisa que
  # só aparece depois, na chave que alguém acrescentar.
  #
  # E ESTA IDENTIDADE NÃO GANHA A ESCRITA IMEDIATA QUE A DO PREÇO GANHOU (rodada 5), porque ela não
  # decide nada sozinha: `COMPARATIVO_KEY` só é lida por `comparativo_pendente?`, e `resta_entregar?`
  # só chega nela quando `portal_fechado?` é VERDADE — fato que viaja em `FECHADO_KEY`/`PDF_SENT_KEY`,
  # gravadas no MESMO `record_attempt!` que esta. Perdida a passada, perdem-se as três juntas, e não
  # há cruzamento com durabilidades diferentes para fechar. (Adiantar `PDF_SENT_KEY` seria pior: ela
  # é a sentinela que impede a segunda emissão, e torná-la durável antes da publicação transformaria
  # a morte no meio em comparativo que ninguém reemite — a ponta que a issue #414 já carrega.)
  #
  # O QUE SE PAGA POR ISSO, DITO INTEIRO (rodada 6, R18): perdida a passada, a linha abandonada lê
  # `portal_fechado` ausente e o fecho publica a frase parcial para quem recebeu preços E
  # comparativo. Pela porta do MOTOR isso não é regressão (a `main` publica a parcial sempre que
  # `delivered_count` é positivo); pela porta do VARREDOR É — lá a `main` calava com contador
  # positivo. A janela é estreita (entre o aceite do comparativo e a persistência seguinte não há
  # trabalho), e a decisão de não bloquear por ela está na auditoria.
  def marcas_do_comparativo(pdf)
    token = token_da_entrega(pdf)
    marcas = { self.class::PDF_SENT_KEY => true }
    token.blank? ? marcas : marcas.merge(self.class::COMPARATIVO_KEY => token)
  end

  # O token de uma entrega DESTA execução, pela mesma definição que o publicador usa.
  def token_da_entrega(entrega)
    ::Autonomia::Agents::Tools::EntregaPublicada.token_de(run, entrega)
  end

  # A PROVA LEGADA DE QUE O PREÇO CHEGOU, e só para o preço emitido ANTES desta versão.
  #
  # A execução que já estava voando quando esta versão subiu emitiu o dela na versão anterior: o
  # handle tem `entregues` e nenhuma identidade nossa. Sem esta leitura, o fecho dessa linha conclui
  # "nenhum preço chegou" — e o cliente que já tinha preço na tela fica sem o comparativo E sem uma
  # palavra. É o incidente de 08/09/2026 de volta, durante toda a vida das execuções em voo.
  #
  # SÃO DUAS METADES, E ATÉ A RODADA 4 ELA EXIGIA SÓ UMA. `entregues` e `PRECO_LEGADO_KEY` são
  # EMISSÃO legada: as duas avançam na passada que emite, mesmo quando a publicação é recusada. Com
  # a emissão valendo sozinha, a linha em voo cujo preço da versão anterior foi RECUSADO publicava o
  # comparativo (mais uma chamada paga ao portal) e a frase "os preços acima são os que chegaram" —
  # sem nada acima —, onde a `main` dizia a frase honesta de falha. Era o defeito da rodada 1 de
  # volta, com a `main` acertando e esta PR errando. E pelo ramo da marca ele ficava permanente: a
  # emissão nova também recusada grava a cobertura como verdadeira, e o estado falso passava a valer
  # pelo resto da vida da linha.
  #
  # O ACEITE LEGADO É `delivered_count`, e ele existe (a auditoria da rodada 4 afirmou que "não há
  # outra prova possível", e isso era falso): a versão ANTERIOR já o incrementava só em publicação
  # ACEITA — imediata ou adiada — e nunca no aviso de espera nem nas frases de fecho, que não passam
  # por `deliver`. Nos dois estados defeituosos que motivaram a correção ele vale zero; na linha
  # legada de verdade vale um ou mais. E não há falso positivo pelo `pedido`: a pergunta pelo dado
  # que falta é contada, mas o handle dela nunca tem `entregues` (quem grava `entregues => []` é
  # `submeter`, e a recusa do `start` não chega lá), então a emissão legada já a exclui.
  #
  # O CONTADOR NÃO DIZ O QUE FOI ACEITO, e há um TERCEIRO estado em que ele mente a favor (rodada
  # 6): linha legada com os preços recusados, cujo COMPARATIVO desta versão foi aceito na mesma
  # passada — o contador vale um por causa dele, `entregues` é a emissão legada, e a prova legada
  # passa sem que preço nenhum tenha chegado. Para virar frase falsa ainda é preciso que a passada
  # morra antes do `record_attempt!` (com `portal_fechado` gravado não sobra nada e o fecho cala).
  # NÃO é regressão — a `main` publica a parcial por `delivered_count` sozinho, e pede o comparativo
  # pelo mesmo `entregues`. E NÃO SE FECHA AQUI, mas a justificativa da rodada 6 era forte demais: o
  # que não existe é o discriminador PERFEITO, não um discriminador honesto. Contar os aceites desta
  # versão de fato não serve (o contador sobe também na republicação deduplicada, que não acrescenta
  # token), mas existe algo melhor, achado na rodada 7: a FOTO DO CONTADOR no instante em que
  # `PRECO_LEGADO_KEY` é gravada. É a mesma escrita, e ela acontece dentro do `poll`, antes de
  # `AsyncRunJob#apply` aceitar qualquer coisa desta passada — então a foto é o aceite que a versão
  # ANTERIOR deixou, sem nada desta. Neste terceiro estado ela vale zero e separa o caso. REDUZ E NÃO
  # ELIMINA: a linha legada cujo COMPARATIVO da versão anterior foi aceito (com os preços recusados)
  # fotografa um, e continua passando. Trocar uma chave a mais no handle por uma redução parcial de
  # um estado que a `main` também tem é decisão de produto, e está na issue R19 (#418) com a
  # reprodução.
  #
  # O QUE TORNA ISTO SEGURO É A COBERTURA, não o valor lido: `PRECO_LEGADO_KEY` é gravada na
  # primeira emissão desta versão e responde, com o que se sabia NAQUELE momento, se havia preço de
  # antes. Toda execução nascida depois do deploy a grava como falsa na primeira emissão — inclusive
  # quando a publicação é recusada, porque ela é gravada na EMISSÃO —, então nenhuma alcança a prova
  # legada, e a frase falsa que a rodada 1 corrigiu não reabre. Um fallback por PRESENÇA da chave
  # nova (rodada 3) também não reabria, mas perdia o preço antigo da linha de histórico misto.
  #
  # Sem a marca, a linha nunca emitiu preço nesta versão e `entregues` é toda a emissão que existe.
  # Lista vazia não é preço: `submeter` grava `entregues => []` desde a primeira passada.
  def prova_legada?(handle)
    return false unless aceite_legado?
    return handle[self.class::PRECO_LEGADO_KEY].present? if handle.key?(self.class::PRECO_LEGADO_KEY)

    Array(handle[self.class::DELIVERED_KEY]).any?
  end

  # O publicador assumiu ALGUMA entrega desta execução? É a metade do ACEITE da prova legada, e o
  # contador é a única forma dela que a versão anterior deixou. Sem execução não há contador, e aí
  # não há prova nenhuma: o fecho cala, que é o lado conservador.
  def aceite_legado?
    run.present? && run.delivered_count.positive?
  end

  # O portal fechou? `FECHADO_KEY` é a resposta; `PDF_SENT_KEY` vale como prova para as execuções
  # que já estavam VOANDO quando esta versão subiu — ela só é gravada no mesmo ramo, depois
  # do `return … unless finished?(…)`, então quem a tem fechou. Sem esta segunda leitura, a
  # linha que atravessou o deploy com o comparativo entregue fecharia dizendo "algumas seguradoras
  # não responderam a tempo" a quem recebeu tudo — o defeito que esta entrega corrige, ressuscitado
  # pela janela do deploy.
  def portal_fechado?(handle)
    handle[self.class::FECHADO_KEY].present? || handle[self.class::PDF_SENT_KEY].present?
  end

  # O comparativo foi emitido e o publicador NÃO o assumiu? Sem token gravado não há emissão
  # conhecida — e o que não foi emitido não está faltando.
  def comparativo_pendente?(handle)
    token = handle[self.class::COMPARATIVO_KEY]
    token.present? && !aceita?(token)
  end

  def aceita?(token)
    ::Autonomia::Agents::Tools::EntregaAceita.aceita?(run, token)
  end
end
