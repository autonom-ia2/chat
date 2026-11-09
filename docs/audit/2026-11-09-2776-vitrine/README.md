# Vitrine de ferramentas prontas — protótipo (#2776)

Protótipo em tela real, atrás da flag `agente_vitrine_ferramentas`, para o Rodrigo aprovar **antes de qualquer
backend**. Branch `proto/2776-vitrine-ferramentas`. Não é PR para merge.

O que é de verdade e o que é de mentira:

- **De verdade:** as telas (componentes Vue do painel), o menu, a rota, a página do agente, o Construtor, a gaveta de
  ferramentas e os textos em en e pt_BR.
- **Fictício:** o que foi incluído em cada agente fica no navegador (`useVitrine.js`, adaptador falso). O resultado do
  "Experimente" sai de `catalogo.js`. Nos clipes, as respostas do Construtor e do "Testar" são simuladas na rede pelo
  `video/gravar.cjs`, porque a demo não tem chave de IA. Nomes, empresas, CNPJ, CPF, valores e datas são inventados.

## Pessoas e conta da demo

- Conta com o pacote **seguros/corretora**, com destaque "Mais usadas por quem trabalha com seguro". Sem pacote, o
  destaque vira "Mais escolhidas".
- **Paula**: agente comum com a chave "Ferramentas dos agentes" (função Sistemas). Não é administradora.
- **John**: administrador. É quem cria os agentes nos clipes.
- Agentes: Ana (atendimento) e Bruno (primeiro contato). A Lia (cotação) fica fora da vitrine.

## Jornadas

As notas dizem o que muda em relação a hoje. Prints em `prints/1440`, `prints/390`, `prints/j6-cartao` e
`prints/j6-construtor`.

### J1 — da vitrine até a Ana (Paula)

| Etapa | O que a pessoa vê | O que muda em relação a hoje |
|---|---|---|
| 01 vitrine | Menu "No automático › Ferramentas prontas"; busca "O que você quer que o agente consiga fazer?"; filtros por assunto; destaque do ramo | Hoje não existe catálogo: a única saída é cadastrar link, método e chave à mão |
| 02 busca "carro" | Um cartão, "Valor do carro" | Busca sem acento e sem regex, por trecho do nome e do que faz |
| 03 detalhe | O que faz, conversa de exemplo, "Experimente", agente, frase "Quando usar" pronta | A pessoa vê o resultado antes de incluir e não lê JSON, link nem método |
| 04 agente + frase | Escolhe a Ana em cartões (sem `<select>`), ajusta a frase se quiser | Quem decide quando usar é o agente, pelo sentido; a frase só orienta |
| 05 pronto | "Ana já consegue dizer quanto vale um carro" e "Ver ferramentas de Ana" | Hoje, depois de salvar, ainda falta testar e ligar à mão |
| 06 ferramentas da Ana | Lista "Prontas" com a ferramenta já ligada | As prontas ficam separadas das feitas à mão |
| 07–09 (J4) | Desligar, "Tirar Valor do carro?" e lista vazia | Tirar pede confirmação com o nome da ferramenta |

### J2 — pela página da Ana (Paula)

Ferramentas vazias → "Escolher ferramenta pronta" → vitrine com "Escolhendo para Ana" → CEP → "Ensinar para Ana" →
cartão "Ana já sabe". **Muda:** hoje "Adicionar ferramenta" abre o formulário técnico. Agora ele abre a vitrine, e o
formulário fica em "Criar a minha (avançado)".

### J3 — Experimente

CEP 01001000 → "Deu certo. É isto que o agente recebe: Rua Praça da Sé, Bairro Sé, Cidade São Paulo – SP".
**Muda:** o teste mostra linhas legíveis, não a resposta crua do sistema.

### J5 — nada encontrado

Uma frase ("Nada com 'passagem de avião' por aqui ainda.") e um botão ("Ver todas"). Embaixo fica "Criar a minha
(avançado)", que leva às ferramentas do primeiro agente.

### J6 — o agente nasce com as ferramentas (John)

- **Construtor** (`prints/j6-construtor/<clipe>/`): a pessoa conta o que o agente faz → no Confira aparece
  "{nome} já vem com estas ferramentas", com o ícone e uma linha de cada, além de "Tirar" e "Ver mais ferramentas" →
  o Testar responde usando a ferramenta.
  - **Muda:** hoje o agente nasce sem ferramenta e a pessoa precisa saber que elas existem.
  - Quem escolhe é o modelo do Construtor, pelo sentido do que foi contado. Ele devolve os ids em
    `ferramentas_sugeridas` do agente, e lista vazia quer dizer "nenhuma combina". Sem lista de palavras e sem regex.
  - Só entra sozinha ferramenta da vitrine, que não pede nada da pessoa. Ferramenta que exigiria chave da pessoa
    (cadastro manual) nunca entra sozinha: no máximo é sugerida.
- **Agente que já existe** (`prints/j6-cartao/`): cartão discreto "Ana pode ganhar: CPF válido. Incluir?", que
  inclui com um toque. "Agora não" some com aquela sugestão. **Muda:** hoje nada avisa que o agente pode consultar
  mais. No protótipo, a sugestão é a próxima do ramo que o agente ainda não tem; no produto, quem escolhe é o modelo,
  pelas instruções do agente.

## Vídeo (clipes sem narração, 1440×900)

`video/0-vitrine.mp4` (vitrine, Experimente, incluir pela vitrine, cartão "pode ganhar") e um clipe por agente de
seguro criado do zero:

| Clipe | Agente | Ferramentas | Teste |
|---|---|---|---|
| 1-garantia | Gael | Dados da empresa, Compras do governo, Feriados e dias úteis | licitação em Uberlândia |
| 2-auto | Ana | Valor do carro, Endereço pelo CEP, CPF válido | "quanto vale meu Onix 2020?" |
| 3-residencial | Rita | Endereço pelo CEP, Quanto choveu, Dólar, juros e inflação | água entrou em casa |
| 4-carga | Caio | Transportadoras, Código de mercadoria, Dados da empresa | 200 notebooks para Curitiba |
| 5-vida-e-saude | Lívia | Hospitais e clínicas, Exames e procedimentos, Nome de doenças | ressonância de joelho |
| 6-solar | Sol | Placas solares instaladas, Endereço pelo CEP | placas em Petrolina |

O roteiro está em `video/agentes.json`. Para regravar, use `video/gravar.cjs`; o cabeçalho do arquivo explica.

## Revisão de fatos dos cartões (nenhum cartão promete mais que a fonte)

Os 25 cartões foram conferidos um a um. Corrigidos nesta rodada:

- **CPF:** "CPF válido": confere os dígitos e a região de emissão. Não consulta a Receita nem a situação.
- **IBGE:** só população e estado, sem renda.
- **CNES:** hospitais de uma cidade, não "perto de um endereço".
- **ANS:** operadora ativa e número de registro, sem número de clientes.
- **Feriados:** só nacionais.
- **ANTT:** registro ativo, sem tamanho de frota.
- **CNPJ:** "ativa na Receita", em vez de "está tudo certo".
- **Domínio:** "está registrado?", em vez de "é meu?".

As falas dos clipes seguem a mesma regra.

## Decisões abertas (para o Rodrigo)

1. **Posição da flag:** `agente_vitrine_ferramentas` está na posição 37 de `feature_flags_ext_2`, PROVISÓRIA. A
   definitiva vem da Orquestração quando virar PR.
2. **Busca:** por trecho de texto, sem acento. Busca por sentido ("quero saber se vai chover") pediria o modelo.
   Proposta: começar por trecho e medir as buscas sem resultado.
3. **"Criar a minha (avançado)" na vitrine:** leva às ferramentas do primeiro agente. Alternativa: perguntar o agente
   antes.
4. **Grupos:** nove assuntos, com nomes leigos. "Achar clientes" (licitações, transportadoras, placas solares,
   aviões) é o grupo mais discutível.
5. **Cartão "pode ganhar":** uma sugestão por vez, e "Agora não" vale para sempre naquele agente. Alternativa:
   voltar depois de 30 dias.
6. **Guia/porquês:** não atualizados, por ser protótipo. Entram no PR da tela de verdade (a trava do Guia cobra).

## Como foi gerado

O painel rodou local no M4, direto na worktree, com banco `chatwoot_kitdemo_2776_vitrine`, Redis próprio e
`node_modules` por clone do pnpm. O M2 estava sem memória, e a Orquestração liberou o M4 com teto de 3 GB.

- Seed: `seed_demo.rb`.
- Prints: `script/demo/prints.cjs` com `jornadas-1440.json`, `jornadas-390.json` e `jornada-j6-john.json`.
- Clipes: `video/gravar.cjs`, convertidos para .mp4 (H.264) com ffmpeg.

Validação do código: eslint 0, prettier ok, `i18n:fork:check` ok e vitest de agentes + menu com 87 arquivos e
1660 testes, 0 falhas.
