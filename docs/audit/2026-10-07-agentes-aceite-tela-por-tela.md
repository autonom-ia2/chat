# Retomada — telas reais e aceite uma a uma

Rodrigo confirmou a mudança de WhatsApp: conectar/cadastrar número permanece na área central de canais existente; Agentes apenas escolhe e associa canais já conectados/disponíveis. Em seguida pediu ver as telas antes de subir e tratar uma a uma para buscar somente melhorias, preservando o funcionamento atual.

## Forma de entrega

Cada tela só pode ser apresentada como pronta com aplicação real, dados sintéticos locais persistidos pela API/banco isolado, capturas lidas e registro dos cenários. O mockup orienta composição visual; nunca substitui a execução do produto. A aprovação do Rodrigo para uma tela não autoriza merge/deploy, alteração de produção ou outra tela.

Sequência de aceite: Seus agentes (lista, cartões, retomada e confirmações) → Escolha → Conte → Teste → Ligue → Pronto → painéis externo/Lia/interno e suas abas → conversa e gavetas. A nova tela interna de QR é retirada por decisão do Rodrigo; ficam 13 famílias. A orientação/atalho à área central de canais é conferida em Ligue e Onde atende. O detalhamento normativo fica no PRD/aceite-telas-reais, atualizado no mesmo bloco por ownership.

Em cada apresentação: objetivo e ação principal em linguagem simples; computador 1440 px/celular 400 px; claro/escuro; perfis editar/só ver/admin aplicáveis; sucesso, carregamento, vazio e erros alcançáveis; jornada de chegada/saída/retomada; efeito verificado por resposta HTTP, GET posterior e reload. Comparar com o mockup e o comportamento atual. Campo, botão ou estado sem contrato real fica bloqueado, sem payload de sucesso fabricado.

## Primeira tela: Seus agentes

Aceite pendente. Cenários obrigatórios: lista normal, carregando, erro com tentativa, vazia, só ver; Clara externa, Lia, interno, rascunhos E1–E4/manual, atendendo e pausado; Abrir/Continuar preserva agente/thread e respeita a permissão; exclusão lógica, pausa e religação conservam o efeito previsto em equipe/vínculos. Sem instrução oculta, dados de outra conta, uso falso para interno ou métricas inventadas. A área antiga permanece funcional com a flag desligada.

Pré-requisitos reais: B1 corrigido/validado/checado; contratos de B2 para gate, projeção, estado, canais e disponibilidade; B3/BE-05 para retomada; fundação F0 e F1 real. Não reduzir essa dependência exibindo uma lista cenográfica ou inferindo estado no frontend. A primeira captura ainda não existe.

## Estado técnico da retomada

RED dos sete achados B1 já executado e registrado no audit de causa raiz: 127 exemplos Ruby, 16 falhas esperadas; 14 testes JS, uma falha esperada. Owners retomam somente as correções consolidadas, seguidas de validação local e checagem focada. Sem nova revisão normal do mesmo B1. Qualquer erro residual segue o limite de causa/final/parada definido pelo Rodrigo.

Não há garantia absoluta de ausência de regressões: a entrega exige evidência dos fluxos afetados, invariantes, permissões e retorno à interface antiga. Não declarar aceite por contagem de testes, build ou screenshot isolado. Todas as telas permanecem pendentes até execução e OK do Rodrigo.

Atualização: as correções dos sete achados passaram na execução focada (180 exemplos Ruby e 43 testes frontend) anterior às últimas refatorações de lint. As três checagens limitadas não encontraram residual nesses achados. O lint consolidado atual deixou seis abreviações de hash no BuildThread; causa e pausa antes da correção registradas no audit de causa raiz B1. A execução ampla atualizada permanece pendente. A primeira tela real ainda não está pronta para apresentação.

Nenhum push para o PR documental #1115, merge, enfileiramento, deploy ou nova consulta/escrita de produção autorizado nesta retomada. Automação continua coordenando a fila/deploys por intermédio do Rodrigo.
