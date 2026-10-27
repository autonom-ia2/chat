# Painel de desempenho v2 — como foi feito com uma conta real (#2226)

Registro do processo pedido pelo Rodrigo em 26/10/2026, depois de a v1 receber nota 4/10. Este documento não traz
dado de cliente: nada de nome, frase de conversa ou número da conta de referência. Os dados reais ficaram só na
pasta temporária da sessão e no arquivo local `public/desempenho-vida-real.json`, que está no `.git/info/exclude`.

## Por que a v1 foi reprovada

- O visual ficou abaixo dos dashboards que o próprio Rodrigo já usava com o cliente de referência. Eram páginas
  densas, com número e explicação, gráficos com eixo, mapa de horários sempre visível e tabelas.
- Faltava o caso da empresa que não anuncia, só orgânico.
- Faltava visão detalhada, com tabela das procuras.
- Faltava exportação completa em PDF e Excel.

## O processo, em 6 etapas

1. **Extração só de leitura.** Todas as conversas da conta de referência saíram da produção por SSM, com o banco
   em modo somente leitura. O arquivo foi gerado no host, compactado e baixado em pedaços de 20 mil caracteres.
   - O SSM corta a saída em 24 mil e anexa `--output truncated--`, que corrompe o pedaço se ele não ficar abaixo
     do limite.
   - A integridade foi conferida pelo md5 do host contra o md5 local. O arquivo temporário do host foi apagado
     no fim.
2. **Chave de leitura.** Um agente leu a instrução inteira do agente de IA e amostras de conversas. Com isso, ele
   escreveu uma chave curta com:
   - campos e valores fechados: tipo de pedido, tema, perfil, marcos do fluxo, resultado, motivo de trava e origem;
   - regras da instrução com código, para citar quando o agente erra;
   - a regra de corte da **procura**, que muda quando o assunto muda.

   Os leitores não releem a instrução inteira, só a chave. Esse é o ganho de eficiência.
3. **Leitura completa.** Setenta leitores leram, mensagem por mensagem, um lote de conversas cada um. Cada um
   gravou uma linha por procura e conferiu que todas as conversas do seu lote foram cobertas.
4. **Auditoria cética.** Sete auditores sortearam 84 procuras e conferiram cada uma contra a conversa inteira; na
   dúvida, contaram como erro.
   - O acerto ficou entre 89% e 96% nos campos de decisão.
   - A qualidade do agente acertou 74% e as regras quebradas 66%. Nos dois casos o erro real é maior que o
     mostrado.
   - O painel mostra essa confiança perto dos números.
5. **Números.** Um analista juntou as leituras com o horário real das mensagens e montou o contrato de dados do
   painel. O contrato tem totais, série semanal, funil de marcos, temas, origem, mapa 7×24, qualidade, passagem
   para pessoa, perdas evitáveis, recomendações com prova e a lista de procuras.
6. **Desenho, construção e crítica.**
   - Um diretor de arte destilou as referências e a lista de motivos da reprovação, com arquivo e linha, e
     escreveu o desenho v2.
   - Quatro frentes construíram em paralelo, cada uma dona dos seus arquivos:
     - (A) página e aba Resumo;
     - (B) aba Detalhe;
     - (C) exportação PDF/Excel no servidor, com `caxlsx` e `prawn`, gems que já existiam;
     - (D) adaptador de dados.
   - Um integrador juntou as frentes, rodou os testes e subiu a demo no M2.
   - Cinco críticos deram notas: dono do negócio, design, números, privacidade e exportação. Depois houve duas
     rodadas de correção e uma rodada final focada nos bloqueantes.

## O que a crítica pegou e mudou de verdade

- **Comparação com filtros diferentes.** A comparação "com retorno marcado × sem retorno" usava um filtro em cada
  lado, e o lado "sem retorno" dava 0% por construção.
  - Ela foi refeita com o mesmo filtro nos dois lados.
  - Agora só vale com 20 casos de cada lado; abaixo disso aparece "poucos casos para comparar".
  - O lado de uma comparação não aceita mais filtro pelo resultado.
- **Ganho sem período.** O ganho estimado de uma recomendação aparecia num período curto, mas era calculado
  sobre o histórico inteiro. Agora todo ganho diz de que datas é.
- **Diferença em pontos.** Ela era calculada sobre percentuais já arredondados. Agora a conta é exata e só o
  resultado final é arredondado.
- **Celular.** Tabela e comparação quebravam na tela estreita e passaram a empilhar.

## Notas dos críticos

| Rodada | Dono | Design | Números | Privacidade | Exportação |
|---|---|---|---|---|---|
| 1ª crítica | 6,8 | 7,0 | 5,5 | 6,0 | 6,6 |
| Correção 1 | 7,5 | 7,8 | 7,5 | 8,8 | 7,8 |
| Correção 2 | 8,0 | 8,0 | 8,0 | 9,2 | 8,0 |

Depois da correção 2 houve uma rodada final só com os bloqueantes que restavam: comparação, ganho, pontos,
celular e PDF de temas.

## Custo

- A leitura com agentes da sessão gastou cerca de 17 milhões de tokens.
- O desenho e a construção gastaram outros ~5 milhões.
- A sessão estourou o limite de uso uma vez e retomou do ponto em que parou; os lotes já lidos voltaram do cache.
- No produto, essa leitura é feita uma vez por conversa, com a chave de IA do próprio cliente, como diz a
  ESPEC.md.

## O que ainda falta antes do produto

Feito no #2251: a leitura guardada no banco (fichas, leituras, procuras e sugestões), o painel calculado no servidor
com a API como fonte da tela, a exportação em PDF e Excel pelo servidor (`desempenho_view` e `contact_export`), os
números só das caixas que a pessoa vê e o número da conversa igual ao da caixa (`display_id`, conferido na conta de
referência).

Ainda falta:

- Leitura automática no servidor (Issue de atualização automática): hoje a leitura entra por carga manual. Ela também
  preenche `chave_de_leitura` e `instrucao_hash` da ficha, que existem desde já e ficam vazias até lá.
- Gravar o que a tela hoje só mostra: colar a instrução do agente de outro sistema e definir o que conta como
  resultado. As gavetas saíram desta entrega e voltam no PR que grava.
- Detalhe paginado no servidor: por ora a lista do período vai inteira até 5 mil procuras, e acima disso só as mais
  recentes, com aviso.
- Entrada própria no menu para quem tem só `desempenho_view` (hoje chega pela página do agente ou pelo endereço).
- Posição final da flag em `feature_flags_ext_2`, confirmada pela Orquestração antes da fila.
