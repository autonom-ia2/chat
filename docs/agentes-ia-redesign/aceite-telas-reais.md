# Aceite das telas reais — Agentes de IA

Plano ligado ao [épico #1114](https://github.com/autonom-ia2/chat/issues/1114).

## Estado e regra de entrada

- [ ] As telas reais foram demonstradas em ambiente local isolado, com a implementação do produto. O mockup sozinho não conta como demonstração.
- [ ] A jornada completa foi demonstrada em cenários externos, internos, de cotação, rascunho, pausa, edição e usuário só ver.
- [ ] Para cada tela e estado aplicável existem capturas reais em 1440 px e 400 px, nos temas claro e escuro, com a mesma identificação do estado.
- [ ] Nenhuma captura real está branca, cortada ou com rolagem horizontal indevida; todos os controles interativos têm alvo de pelo menos 44 px.
- [ ] A página lado a lado entre produto e protótipo foi conferida e cada diferença está corrigida ou registrada como divergência autorizada abaixo.

O protótipo navegável já foi aprovado pelo Rodrigo. A inspeção visual atual das telas reais, em comparação com o protótipo, ainda está pendente. O inventário deste documento é estático e não declara que essa inspeção foi executada. A demonstração das telas reais em ambiente local isolado é requisito antes de qualquer deploy do redesign. Dados de teste no banco isolado e falhas controladas de rede/API são permitidos para reproduzir cenários. A tela deve ser a implementação real, usar o contrato da API e provar persistência e efeitos locais quando aplicáveis. Uma fachada com botões decorativos e estado apenas cenográfico não satisfaz o aceite.

Uma afirmação dura local é uma condição binária: a tela real precisa mostrar o título, estado, controles, texto e destino descritos; uma tela em branco, corte, overflow, controle decorativo, estado diferente ou ação que não leva ao resultado descrito é falha. Estado assíncrono sem resultado dentro do limite definido pelo produto também é falha. Cenário sem pré-requisito fica bloqueado e não passa.

## Matriz visual comum

Cada combinação abaixo deve ser conferida para todas as telas e estados aplicáveis ao cenário. A fonte normativa da lista de telas é o PRD §11.6; o `MAP` e as `stateBar` do mockup servem para localizar a tela e o estado de referência.

| Largura | Tema claro | Tema escuro | Afirmação dura |
|---|---|---|---|
| 1440 px | [ ] | [ ] | O conteúdo mantém a hierarquia do protótipo, sem corte, e os dois temas têm contraste legível. |
| 400 px | [ ] | [ ] | A navegação e as colunas se reorganizam para uma tela estreita, sem `scrollWidth` maior que a viewport e sem esconder a ação principal. |

Fontes estáticas de tema e responsividade do mockup: `mockup/src/styles.css:16-27`, `mockup/src/styles.css:59-63`, `mockup/src/styles.css:157-158`, `mockup/src/styles.css:217-219` e `mockup/src/styles.css:310-311`.

### Perfis

| Perfil | Pode fazer | Telas e limites que precisam aparecer |
|---|---|---|
| Pode editar | Criar, testar, editar, ligar, pausar, religar e gerir agentes | Vê a jornada completa e as abas de gestão permitidas pelo tipo do agente. |
| Só pode ver | Consultar e testar | Vê apenas “Como está indo” e “Testar”; não vê controles de escrita. As capturas F1+ não clicam em escrita. O teste pode ser executado pelo POST de leitura previsto no contrato; a marca desse teste não conta como mudança de estado. |
| Admin da plataforma | Pode editar e gerir ferramentas de plataforma | Vê “Ferramentas” para agentes que aceitam ferramentas; a aba não aparece para a Lia. |

O perfil só ver não é um atalho para provar telas de escrita: a dispensa é fundamentada em D17, §6.3, §6.6 e §11.8. O teste do perfil só ver ainda precisa passar pelo fluxo real de leitura; rotas e controles de criação/edição não ficam disponíveis para esse perfil, e tentativas diretas são recusadas. O ajudante interno não tem canal; o Agente de Cotação não recebe os controles genéricos que não têm leitor, conforme §6.5 e §6.7.

## Mapa da jornada e dos estados

Etapas visuais da jornada: `Escolha → Conte → Teste → Ligue → Pronto`. Máquina de estados: `E0 Escolhendo → E1 Começando → E2 Conversando → E3 Pronto para testar → E4 Testado/Pronto para ligar → E5 No ar → E6 Pausado`.

“Ligue” é a etapa visual do estado E4: o agente foi testado e está pronto para ligar. E5 começa quando a operação de ligar conclui no backend; “Pronto” deve refletir essa confirmação. Falha na navegação não desfaz nem duplica a operação concluída. E6 é o estado pausado. O estado de começo que falhou (`E1x`) não cria rascunho. O rascunho manual sem instrução é `E2m`: a lista mostra “Falta terminar · Falta escrever as instruções”, sem prazo de limpeza; “Continuar” leva a Ajustes › O que faz, e a pessoa precisa escrever a instrução para seguir até o ar. Depois de estar no ar, o agente nunca volta a ser mostrado como “Falta terminar”. Toda mudança anterior ao ar que altera o que ele responde ou por onde responde invalida o teste atual; religar um pausado exige instrução, sem exigir um teste novo. A fonte normativa é `docs/agentes-ia-redesign/PRD.md:404-461`.

O mapa navegável e a preparação de cada estado estão em `docs/agentes-ia-redesign/mockup/src/screens-extra.js:46-80`. A implementação real não deve levar para o produto a faixa de protótipo, o mapa, a barra de estados ou o seletor de perfil.

## Checklist de cenários

### 1. Lista com agentes, estados de carregamento e usuário só ver

- [ ] **Alvo:** lista normal com Clara e Lia; carregando; erro; vazio; só ver.
- [ ] **Motivo:** confirmar a porta de entrada, a compreensão imediata da situação dos agentes e a resposta quando os dados ainda não chegaram.
- [ ] **Afirmação dura local:** a tela real mostra “Seus agentes”, o subtítulo, o botão de criação apenas para quem pode editar, os contadores corretos, o esqueleto no carregamento, a mensagem de erro com tentativa novamente, o herói e os modelos no vazio, e a linha de bloqueio no perfil só ver. Nenhum controle de escrita aparece para esse perfil.
- [ ] **Dispensa:** no vazio, os modelos e a criação não aparecem para só ver; isso é a regra de permissão, não uma tela faltante.
- **Fonte:** `mockup/src/screens-list.js:39-94`, `mockup/src/screens-extra.js:75`, PRD §6.1, §11.6 e CA-VISUAL-03.

### 2. Cartões Clara, Lia e rascunhos

- [ ] **Alvo:** Clara externa, Lia de cotação, agente interno, rascunho, rascunho manual sem instrução (`E2m`), retomada do rascunho, abandono da montagem, pronto para ligar, atendendo e pausado; canais ocupados e agente sem canal.
- [ ] **Motivo:** o cartão precisa permitir que uma pessoa entenda o que está acontecendo sem abrir o painel.
- [ ] **Afirmação dura local:** cada cartão mostra avatar, nome, selo do tipo, situação, canal ou aviso de ausência, contexto de uso e ação coerente com o estado. Rascunho mostra o passo em que parou; “Continuar” retoma exatamente esse passo; sair da montagem a partir de Conte, Teste ou Ligue guarda o rascunho; voltar na Escolha não cria rascunho; pronto mostra o próximo passo; agente interno não inventa números de uso; agente que já esteve no ar não mostra “Falta terminar”.
- [ ] **Só ver em E1–E4:** cada rascunho oferece “Abrir”, que leva a “Como está indo” ou “Testar”, sem criação, retomada de escrita ou mudança de estado. Demonstrar os quatro estados e as recusas nas rotas de escrita. “Continuar” é exclusivo de quem edita; a omissão de “Abrir” no protótipo não altera CA-LISTA-15.
- [ ] **Dispensa:** o Agente de Cotação mantém o selo e o tratamento específico; o ajudante interno não mostra estatística de uso, conforme D14.
- **Fonte:** `mockup/src/screens-list.js:1-36`, `mockup/src/data.js:21-62`, PRD §6.1, §6.6 e §11.6.

### 3. Pausar, religar e excluir

- [ ] **Alvo:** interruptor Atendendo/Pausado, confirmação de pausa, retorno à equipe, religação, exclusão de rascunho e exclusão de agente ativo.
- [ ] **Motivo:** são as ações de maior impacto na gestão diária e precisam deixar o efeito compreensível antes da confirmação.
- [ ] **Afirmação dura local:** pausar pede confirmação e informa que as conversas vão para a equipe; depois da confirmação, o cartão fica pausado; religar devolve o estado atendendo; excluir usa o texto correspondente a rascunho, agente externo ou ajudante interno. O usuário só ver não consegue iniciar nenhuma dessas escritas.
- [ ] **Dispensa:** a validação local deve provar persistência, vínculo e devolução em banco de teste, pelo fluxo real de API implementado. Ficam fora apenas os efeitos sobre WhatsApp e clientes de produção; esses efeitos seguem o plano do PR, §11.7/§11.8 e a aprovação de produção.
- **Fonte:** `mockup/src/main.js:65-72`, `mockup/src/main.js:90-104`, `mockup/src/screens-list.js:17-36`, PRD §6.1, §6.4 (D34) e §6.6.

### 4. Escolha do trabalho e começo da criação

- [ ] **Alvo:** seis modelos externos, “Ajudar minha equipe”, “Outro trabalho”, seleção, avanço, conta sem painel do ajudante e falha ao começar (`E1x`).
- [ ] **Motivo:** uma pessoa com pouca familiaridade precisa reconhecer o trabalho pelo resultado esperado, sem decidir primeiro conceitos técnicos.
- [ ] **Afirmação dura local:** os cartões mostram nome, explicação e exemplo; selecionar um marca apenas aquele cartão; “Continuar” permanece bloqueado sem escolha; em conta sem ajudante, a opção interna some; se o começo falhar, nenhum rascunho aparece e a tela oferece nova tentativa.
- [ ] **Dispensa:** `E1x` é estado normativo novo do PRD e pode não ter item próprio no `MAP`; ainda assim precisa de demonstração real. A barra “Estado da tela” do mockup não entra no produto.
- **Fonte:** `mockup/src/data.js:64-74`, `mockup/src/screens-build.js:14-29`, `mockup/src/screens-extra.js:76`, PRD §6.2.1 e §6.6.

### 5. Conte: respostas, materiais e atualização do que o agente sabe

- [ ] **Alvo:** quatro respostas do roteiro, resposta sugerida, respostas fora de ordem, nome, link sugerido, imagens, arquivos, material aceito e material com falha.
- [ ] **Motivo:** esta é a parte que transforma uma explicação humana simples em uma configuração utilizável.
- [ ] **Afirmação dura local:** aparece uma pergunta por vez; o painel “O que já sabe” reflete as respostas atuais, inclusive quando chegam fora de ordem; depois das quatro respostas o campo continua disponível para mudar ou acrescentar algo; o teste só libera com as quatro respostas; falha ou pendência de material não impede o avanço quando o PRD permitir; anexo respeita os limites da tela.
- [ ] **Reutilizar material (CA-CON-09):** um material pronto permite atalho em um clique; dois ou mais abrem escolha; ausência mostra a mensagem prevista. A lista exclui agentes arquivados. Pedido de outra conta retorna 404. Demonstrar escolha, persistência e escopo pela API e banco isolados.
- [ ] **Dispensa:** o mockup usa controles para simular arquivo com problema, adicionar foto de exemplo e usar material da Clara; eles servem à demonstração do protótipo e não entram no produto, conforme §6.4.
- **Fonte:** `mockup/src/screens-build.js:32-107`, `mockup/src/main.js:46-64`, `mockup/src/data.js:76-90`, PRD §6.2.2, §6.4 e §6.6.

### 6. Conte: estados de espera, erro e limite

- [ ] **Alvo:** Pensando, Erro ao enviar, Não salvou, Demorando, Ainda respondendo e Muitas mensagens.
- [ ] **Motivo:** a pessoa precisa saber se deve esperar, tentar novamente ou corrigir a resposta, sem concluir que perdeu o agente.
- [ ] **Afirmação dura local:** cada estado tem uma mensagem clara, mantém o que já foi salvo, bloqueia somente o controle que precisa ser bloqueado e oferece a ação descrita pelo PRD. O limite informa espera de um minuto; o estado “Não salvou” deixa claro que nada foi gravado; erro e demora permitem a tentativa prevista.
- [ ] **Dispensa:** a simulação visual local não substitui a prova de limite e tempo do backend; esses comportamentos serão fechados no PR de desenho e na validação correspondente. Não inventar mecanismo nesta etapa.
- **Fonte:** `mockup/src/screens-build.js:45-83`, `mockup/src/kit.js:64-69`, PRD §6.2.2, BE-15, BE-20 e §11.8.

### 7. Teste da instrução atual

- [ ] **Alvo:** teste normal, apresentação alterada, erro, demora, limite, ainda montando, material novo que invalida o teste e ferramenta que grava.
- [ ] **Motivo:** ligar um agente sem que a pessoa veja uma resposta atual cria risco de surpresa no atendimento.
- [ ] **Afirmação dura local:** “Está bom, continuar” só fica habilitado depois de uma resposta concluída na conversa de teste atual; mudar nome ou primeira mensagem limpa a conversa e mostra o cumprimento novo; material que altera a instrução mostra o motivo e exige novo teste; erro, demora sem resposta, limite e montagem incompleta não contam; o teste continua sendo a referência do comportamento esperado pela jornada.
- [ ] **Dispensa:** a régua que representa limite/corte de certeza sai conforme D1-a aprovado. Isso não autoriza remover a métrica de certeza média (`avg_confidence`) nem a metadata prevista no PRD; a tela real deve manter esses dados quando forem parte do resumo ou da evidência.
- **Fonte:** `mockup/src/screens-build.js:109-166`, `mockup/src/main.js:58-64`, PRD §6.2.3, §6.4, §6.6 e §11.6.

### 8. Teste da Lia e do ajudante interno

- [ ] **Alvo:** Agente de Cotação no teste e ajudante interno com conversa de exemplo.
- [ ] **Motivo:** os dois tipos têm leitores e efeitos diferentes; tratá-los como agente externo comum induz a escolhas erradas.
- [ ] **Afirmação dura local:** a Lia não cota de verdade no teste e só mostra o aviso quando o resultado indicar ferramenta pulada; o ajudante usa a conversa de exemplo, não mostra faixa de passagem para equipe e conta uma resposta concluída como teste válido.
- [ ] **Caminho da Lia no protótipo:** “Todas as telas” → “Como está indo · Lia” → aba “Testar”. Esse caminho foi aberto no navegador; a ausência de atalho exclusivo no mapa não bloqueia a referência visual. Na tela real, abrir e testar pelo painel da Lia.
- [ ] **Dispensa:** a Lia nasce ativa pela Cotação e não percorre a criação comum; o ajudante não recebe público, horário, canal ou passagem genérica de cliente.
- **Fonte:** `mockup/src/screens-build.js:120-166`, `mockup/src/screens-panel.js:83-103`, `mockup/src/data.js:33-62`, PRD §6.2.3, §6.3, D26, D27 e D28.

### 9. Ligue: canal, horário e recusas

- [ ] **Alvo:** canal livre, canais ocupados, nenhum canal livre, falha ao ligar, canal sem horário, teste ausente e editor sem ser administrador.
- [ ] **Motivo:** a tela precisa responder “onde ele atende” e “quando atende” antes do clique que coloca o agente no ar.
- [ ] **Afirmação dura local:** canais ocupados ficam desabilitados com a explicação de exclusividade; canal livre pode ser escolhido; ausência de canal, falta de teste, falha e falta de permissão mostram a orientação correta; o resumo acompanha a opção de horário escolhida; o botão de ligar é único e coerente com o estado.
- [ ] **Dispensa:** perguntas para puxar conversa não fazem parte do produto; a conexão de WhatsApp continua em Canais/Caixas de entrada; sem canal, Agentes preserva o agente e orienta para Canais; o ajudante interno não exibe canal nem horário.
- **Fonte:** `mockup/src/screens-build.js:169-218`, `mockup/src/data.js:21-26`, PRD §6.2.4, §6.4, BE-10, BE-11 e §11.6.

### 10. Resultado de ligar e deixar pronto

- [ ] **Alvo:** sucesso externo, sucesso interno e “Deixar desligado por enquanto”.
- [ ] **Motivo:** a pessoa precisa saber se já colocou o agente no ar ou apenas guardou a montagem.
- [ ] **Afirmação dura local:** “Ligar” conclui no backend e leva a E5, com confirmação do canal externo ou do painel da equipe no interno e cartão “Atendendo”; “Deixar desligado por enquanto” mantém E4, com cartão “Pronto para ligar”, sem ativar atendimento, e permite retomar no ponto correto; os cartões de destino levam ao painel ou à lista previstos.
- [ ] **Dispensa:** a validação local deve provar persistência do estado, vínculo com a caixa de teste e transição pelo fluxo real de API e banco de teste. Ficam fora apenas atendimento de clientes de produção e efeitos no WhatsApp de produção; a tela de pronto pode esconder “Ver numa conversa” quando a pessoa não vê nenhuma caixa.
- **Fonte:** `mockup/src/screens-build.js:220-234`, `mockup/src/main.js:74-88`, PRD §6.2.5, §6.6, §11.7 e §11.8.

### 11. Painel da Clara e gestão completa

- [ ] **Alvo:** “Como está indo” com dados, carregando, erro e sem conversas; “Testar”; “O que sabe” normal, todos os estados, vazio e limite; “Onde atende” normal, sem canal, falha, pausado e não administrador; “Ajustes” normal, versões, sem ajudante, ajudante interno, os dois, sem versão guiada, rascunho testado, manual, retorno ao guiado e canais sem horário; “Ferramentas” para SuperAdmin.
- [ ] **Motivo:** gestão não termina no clique de ligar; a pessoa precisa entender resultado, ensinar, ajustar, mover canal e recuperar versões.
- [ ] **Afirmação dura local:** as abas aparecem na ordem normativa; cada estado mostra seus dados ou mensagem e ação; os cinco resultados abrem gaveta; materiais respeitam todos os estados do backend e o limite de 30; ajustes separados têm salvar separado; modo manual e retorno ao guiado pedem as confirmações previstas; “Onde atende” deixa claro o efeito de tirar ou colocar canal; só SuperAdmin vê Ferramentas.
- [ ] **Dispensa:** no perfil só ver, apenas “Como está indo” e “Testar” aparecem; no ajudante interno, “Onde atende” não aparece e números de uso não são inventados; controles internos de horário, público e passagem ficam ocultos por falta de leitor.
- **Fonte:** `mockup/src/screens-panel.js:1-246`, `mockup/src/screens-extra.js:52-71`, `mockup/src/kit.js:98-122`, PRD §6.3, §6.5, §6.6 e §11.6.

### 12. Painel da Lia e do ajudante interno

- [ ] **Alvo:** Lia em “Como está indo”, “Testar”, “O que cota” e “Ajustes”; ajudante interno no cartão e em “Como está indo”.
- [ ] **Motivo:** preservar o comportamento especial da cotação e não apresentar ao usuário configurações que não têm efeito no ajudante.
- [ ] **Afirmação dura local:** Lia mostra os ramos que cota, o aviso de responsabilidade da Hub2You e as escolhas próprias previstas em CA-AJU-12: nome, foto, horário informado ao cliente, jeito de cotar, alvo, “Para quem responde” e “Quando atende”. O horário informado e a janela de atendimento são controles distintos; salvar e reler cada escolha pela tela e API reais; não mostra “Quando passa”, ferramentas nem uma aba de materiais comum. O ajudante mostra que ajuda dentro das conversas, oferece “Ver numa conversa” e não mostra números falsos.
- [ ] **Dispensa:** “Ferramentas” não se aplica à Lia mesmo no perfil SuperAdmin; “Onde atende” não se aplica ao interno; a criação da Lia não é reencenada pelo construtor comum.
- **Fonte:** `mockup/src/screens-panel.js:11-31`, `mockup/src/screens-panel.js:104-147`, `mockup/src/data.js:33-62`, PRD §6.3, §6.5, §6.7, D14 e BE-17.

### 13. Dentro da conversa, ajudante e resposta errada

- [ ] **Alvo:** conversa com ajudante, vazio sem ajudante, nota interna de passagem, menu de mensagem, cinco motivos de resposta errada e gaveta de resultados.
- [ ] **Motivo:** são as peças que tornam a promessa do ajudante compreensível no lugar onde a equipe trabalha.
- [ ] **Afirmação dura local:** o ajudante aparece ao lado da conversa com resumo e ações; sem ajudante há orientação para criar; a nota de passagem é privada; marcar resposta errada exige um motivo antes de concluir; a gaveta mostra motivo, resposta sugerida e “Ensinar”; foco e Escape funcionam nos diálogos e gavetas.
- [ ] **Dispensa:** a página própria “Dentro de uma conversa” existe somente para demonstrar as peças do mockup; no produto, elas entram na tela real de conversa. A gaveta deve mostrar conversas reais no produto, respeitando o escopo que a pessoa pode ver.
- **Fonte:** `mockup/src/screens-extra.js:28-71`, `mockup/src/main.js:160-245`, PRD §6.4, BE-24, BE-28 e §11.6.

## Divergências autorizadas do protótipo

Estas diferenças são decisão do PRD e não devem ser tratadas como defeito visual:

- A faixa “Protótipo”, “Todas as telas”, “Ver como”, “Ver esta tela como”, selo “Novo”, textos de exemplo e botões de simulação ficam fora do produto.
- A página independente “Dentro de uma conversa” vira peças da conversa real; a frase do mockup que oculta contatos também não entra no produto, salvo a orientação autorizada sobre caixas que a pessoa não vê.
- A aba “Para enviar” e “Perguntas para puxar conversa” saem.
- A régua que representa limite/corte de certeza sai conforme D1-a aprovado; a métrica de certeza média (`avg_confidence`) e a metadata prevista no PRD permanecem quando usadas pelo resumo ou pela evidência.
- Escolhas únicas usam rádio acessível; abas têm teclado, `aria-controls` e `tabpanel`; `pick` vira `ChoiceSelect`; gavetas prendem foco e fecham com Escape; gráfico tem texto alternativo.
- `needs_review` informa que o material ainda não é usado; a frase de versão vale apenas para instruções; “Sem dados” substitui zero de certeza média.
- Conte mantém o campo depois das quatro respostas; o rascunho não nasce na Escolha; voltar ao modo guiado pede confirmação.
- O teste do ajudante não mostra passagem para a equipe; o aviso de cotação aparece somente quando houver `skipped_tools`.
- A Lia usa “jeito de cotar”; “Quando passa para a equipe” não aparece para ela; a conexão de WhatsApp fica em Canais e Agentes só associa caixas já conectadas; a nota de passagem privada é nova.

Fonte completa das divergências: `docs/agentes-ia-redesign/PRD.md:313-367`.

## Evidência mínima para fechar o aceite local

- [ ] Demonstração ao vivo das 13 famílias acima nas telas reais em ambiente isolado.
- [ ] Capturas reais por tela/estado em `{1440, 400} × {claro, escuro}`, usando os perfis aplicáveis.
- [ ] Registro dos caminhos percorridos e do resultado de cada afirmação dura; `PASS`, `FAIL` ou `BLOCKED`, sem omissão.
- [ ] Comparação lado a lado com o protótipo, registrando divergências pela lista acima.
- [ ] Conferência de foco, teclado, leitores sem controles decorativos, overflow, alvo de toque e mensagens de erro.
- [ ] Nenhum cenário local bloqueado por falta de pré-requisito antes de pedir qualquer deploy.
- [ ] **O1 — teste com três pessoas leigas:** as três chegam a “Pronto” sem pedir ajuda; a mediana é de até oito minutos com material e de até cinco minutos sem material, conforme PRD. Registrar participantes de forma anônima, cenário, duração, pedidos de ajuda e resultado. Teste automatizado não substitui essa observação humana. Este gate continua pendente antes do deploy.

Produção, banco, fila, merge e deploy seguem a coordenação da sessão Automação e as aprovações do Rodrigo. Este documento não autoriza nenhuma dessas ações.
