# Revisão normal 1 — F2/F3 — produto e UX

**Data:** 2026-10-08  
**Escopo:** inspeção visual das 13 capturas reais desktop/ claro da rodada 45, comparadas às cinco referências desktop/ claro do `ref42`. A captura `03c` foi tratada como detalhe complementar do rodapé de `03`, conforme o fluxo de evidência.  
**Método:** leitura das imagens em resolução original. Não executei navegador, testes, build, banco ou produção e não alterei produto. `03`, `04` e `06` representam estados diferentes das referências correspondentes; não foram classificados como equivalência visual exata. As correções posteriores comunicadas pelo coordenador ainda precisam de nova captura para serem confirmadas.

## Achados

### F2-F3-R1-01 — alto — aviso de falha permanece na tela de sucesso

**Prova:** `.codex/preview/agents/screenshots/creation45/criacao-08-pronto-chromium-1440-light.png` mostra a conclusão “Bia revisada está atendendo em” e, simultaneamente, o toast “Não foi possível ligar este agente. Confira o canal e tente novamente.”.

**Efeito:** a pessoa recebe duas mensagens incompatíveis: o agente aparece ativo, mas o aviso manda tentar ligar novamente. Isso pode induzir uma segunda ação ou fazer a pessoa desconfiar de um estado que já foi concluído.

**Correção mínima:** limpar o erro de publicação antes de exibir o sucesso e impedir que o toast da tentativa anterior atravesse a transição para `Pronto`.

### F2-F3-R1-02 — alto — detalhe técnico exposto no erro de publicação

**Prova:** `.codex/preview/agents/screenshots/creation45/criacao-07-falha-transporte-na-publicacao-chromium-1440-light.png` exibe `AxiosError: Network Error` no alerta vermelho. O toast superior já possui uma mensagem humana: “Não foi possível ligar este agente. Confira o canal e tente novamente.”.

**Efeito:** a tela entrega um detalhe interno da implementação para uma pessoa que só precisa saber o que aconteceu e qual ação pode tentar. A mensagem técnica também torna o produto menos confiável para alguém sem conhecimento de tecnologia.

**Correção mínima:** traduzir o erro de transporte para a mensagem localizada de falha e reservar o detalhe técnico para diagnóstico interno.

### F2-F3-R1-03 — alto — conclusão não informa o canal conectado

**Prova:** em `criacao-08-pronto-chromium-1440-light.png`, o título termina em “Bia revisada está atendendo em”, sem nome do canal. A referência `ref42/reference-08-desktop-light.png` informa “A Bia está atendendo no Chat do site hub2you.”.

**Efeito:** a pessoa não consegue confirmar onde o agente foi ligado, e a frase fica gramaticalmente incompleta. Isso é especialmente problemático quando a conta possui mais de um canal.

**Correção mínima:** renderizar o nome do canal retornado pelo estado final do agente (`inbox_name`) no título e manter a frase completa quando o canal estiver presente.

### F2-F3-R1-COPY — médio — contador de canais ocupados tem texto provisório

**Prova:** `criacao-06-ligue-chromium-1440-light.png` mostra “3 canal(is) já em uso”. A referência usa “Canais ocupados (2)”; os estados têm contagens diferentes, então o achado é de redação e não de número.

**Efeito:** “canal(is)” expõe uma marca de implementação e exige interpretação da pessoa usuária. A gestão de canais perde a apresentação simples esperada.

**Correção mínima:** usar a forma localizada com pluralização real, por exemplo `Canais ocupados (3)`.

## Evidência complementar

`criacao-03c-conte-continuar-chromium-1440-light.png` começa no rodapé da etapa Conte e mostra o CTA “Continuar para Teste”. Ela deve ser rotulada como **Conte concluído — detalhe do rodapé/CTA**, sempre emparelhada com `criacao-03-conte-concluido-chromium-1440-light.png`; não deve ser apresentada como uma captura independente da tela inteira.

Diferenças do shell real em relação ao wrapper visual do protótipo — sidebar, barra de apresentação e controles de referência — ficaram fora desta revisão. Mobile, escuro e a confirmação das correções posteriores permanecem pendentes da revisão 2 após a rodada 46.

## Conclusão

A rodada visual 45 deixou três problemas concretos de comportamento/apresentação e um problema de redação. Esta revisão não aprova a prévia nem substitui a nova captura após as correções. A mesma lente produto/UX deve repetir somente a conferência limitada na rodada 46.
