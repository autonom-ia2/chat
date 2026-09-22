# Kit do escritor — Central de Ajuda "Plataforma"

Todo artigo da Central de Ajuda segue este kit. Ele vale para quem escreve (pessoa ou
agente) e para quem revisa. O exemplo-ouro é o capítulo 02 (Configurações pessoais),
escrito à mão e aprovado pelo Rodrigo antes de qualquer outro.

## 1. Para quem e para quê

- **Quem lê:** o cliente da plataforma — administrador ou atendente de uma corretora,
  imobiliária, clínica. Ele está **dentro do painel**, com a tela aberta ao lado.
  Não é técnico e está com pressa.
- **Quem mais lê:** o **Guia da Plataforma**, a IA que responde dúvidas dentro do painel.
  Ele busca na Central quando precisa. Escreva de um jeito que uma busca pela
  dúvida da pessoa encontre o artigo certo (ver seção 7).
- **O que o artigo precisa fazer:** a pessoa entende **o que é**, **por que importa**,
  **faz** a tarefa e **não cai** nas armadilhas conhecidas.

## 2. Onde o artigo mora

Um arquivo por artigo, em `lib/central_de_ajuda/<capítulo>/<id>-<slug>.md`, com o
id e o capítulo do `docs/central-de-ajuda/mapa-de-artigos.json`. O id **nunca muda**,
mesmo que o título mude.

Cabeçalho obrigatório:

```yaml
---
id: "02.03"
titulo: "Definir se você está disponível para receber conversas"
capitulo: "02"
publico: ambos            # admin | atendente | ambos
prioridade: P1            # P1 | P2 | P3
me_leve_ate_la:           # omita se o artigo não tem uma tela
  rota: profile_settings_index
  destaque: null          # só um valor que existe como `highlight` no guia-produto.md
assuntos: ["01.2-definir-disponibilidade", "01.3-marcar-offline-automaticamente"]
conferido_em: "2026-09-22"
evidencias:               # arquivo:linha de CADA fato do texto, conferido no código de hoje
  - app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue:206
---
```

## 3. A estrutura, sempre igual

Seções nesta ordem, com estes títulos exatos:

1. `## O que é` — 1 a 3 frases, em português de gente, sem nome técnico.
2. `## Por que importa` — o que muda na vida da pessoa. É aqui que o artigo ensina de
   verdade. Nunca pule.
3. `## Como faz` — primeiro o caminho em uma linha
   (`**Sua foto no rodapé do menu → Configurações do Perfil**`), depois os passos
   numerados, um clique por passo. Os prints entram aqui, no passo a que se referem.
4. `## O que dá errado` — lista de armadilhas reais. Cada item começa pelo **sintoma**,
   do jeito que a pessoa descreveria, e depois diz a causa e a saída.
   Ex.: "**A conversa não chega para você.** Seu status está Offline…"
5. `## Veja também` — 2 ou 3 artigos, pelo id: `- [02.07] Criar a sua assinatura`.

O botão **Me leve até lá** não vai no texto: ele sai do cabeçalho (`me_leve_ate_la`) e a
tela de leitura o desenha. Nunca escreva "clique aqui" nem cole endereço de tela.

Tamanho: 150 a 600 palavras. Se passou disso, o artigo é dois.

## 4. Tom

- Frase curta. Uma ideia por frase. Voz ativa. "Você", nunca "o usuário".
- Português do Brasil, com acento. Sem inglês quando existe palavra em português.
- Explique a consequência, não só o clique: "Offline tira você do rodízio" ensina;
  "clique em Offline" não ensina.
- Nomes de botão e de menu **exatamente como aparecem na tela**, em negrito. A fonte é
  o arquivo de tradução `app/javascript/dashboard/i18n/locale/pt_BR/*.json`; na dúvida,
  confira lá, não invente.
- Nada de marca: diga "a plataforma". Não escreva Chat2You, Hub2You, Autonom.ia nem
  Chatwoot — o mesmo texto é publicado para marcas diferentes.
- Sem emoji, sem exclamação de propaganda, sem "simples e fácil".

## 5. Vocabulário que confunde (use sempre assim)

| Na tela | Significa | Escreva |
|---|---|---|
| Agentes (em Configurações) | as pessoas do time | "as pessoas do time (em **Configurações → Agentes**)" |
| Agentes (no menu principal) | as IAs que atendem | "os agentes de IA" |
| Caixa de Entrada (1º item do menu) | a central de avisos para você | "sua **Caixa de Entrada** de avisos" |
| Caixas de entrada (em Configurações) | os canais: WhatsApp, e-mail, site | "a caixa de entrada do canal" |
| Robôs | robôs por webhook, antigos | "Robôs (integração por webhook)" |
| Guia da Plataforma | o assistente que responde dúvidas no painel | "o Guia" |

## 6. Regra de verdade (o revisor reprova se quebrar)

- **Todo fato é conferido no código de hoje.** O estudo de 08/09 e o `porques.md` são
  ponto de partida, não prova. Para cada fato do texto, abra o arquivo, confirme, e
  registre `arquivo:linha` em `evidencias`.
- Não confirmou? **Não escreva.** Nada de "a verificar" no texto publicado. Se o fato é
  importante e só se confirma olhando a tela, escreva no fim do arquivo, fora do texto:
  `<!-- CONFIRMAR NA TELA: ... -->` — o revisor ou o Rodrigo resolve.
- Permissão: diga quem consegue fazer (administrador, atendente, função personalizada
  com a chave X) com base no gate da rota ou da policy, nunca por suposição.
- Não prometa o que não existe, não descreva telas do Captain nem o editor da Central de
  Ajuda (ambos fora da Central).
- Nunca use dado de cliente real em exemplo. Nomes de exemplo: Maria, João, "Corretora
  Exemplo", caixa "WhatsApp Comercial".

## 7. Escrito também para o Guia achar

- Título como **tarefa**, com as palavras que a pessoa usaria para perguntar:
  "Por que as conversas não chegam para mim" é melhor que "Rodízio".
- A **primeira frase de "O que é"** responde a pergunta sozinha.
- Em "O que dá errado", o sintoma com as palavras do usuário ("não aparece",
  "sumiu", "não chega", "deu erro") — é o que ele vai digitar.

## 8. Prints

Quem escreve **não tira print**: descreve. No passo em que o print ajuda, escreva:

```
![PRINT 02.03-a: Menu da foto aberto, com o seletor de Disponibilidade em destaque](prints/02.03-a.png)
```

e, no fim do arquivo, a especificação para o roteiro de captura:

```
<!-- PRINT 02.03-a
rota: profile_settings_index (ou o caminho de cliques)
estado: menu da foto aberto; status Online
destaque: seletor de Disponibilidade
recorte: só a área do menu
-->
```

Regras: no máximo 2 prints por artigo, só onde o botão **Me leve até lá** não basta
(formulário com muitos campos, tela com abas, antes e depois). Os prints são tirados
na conta de teste local, com dados fictícios, recortando a área de conteúdo — sem logo,
sem cor de marca.

## 9. Checklist do revisor

- [ ] Cabeçalho completo; id e capítulo batem com o mapa.
- [ ] As cinco seções, na ordem, com os títulos exatos.
- [ ] "Por que importa" diz consequência, não repete "O que é".
- [ ] Cada fato tem evidência `arquivo:linha` que **ainda confere** no código de hoje.
- [ ] Nomes de botão e menu iguais aos do `pt_BR`.
- [ ] Nenhuma marca, nenhum dado real, nenhum "a verificar" no texto.
- [ ] `me_leve_ate_la.rota` existe no `guideRouteRegistry.js`; destaque existe ou é null.
- [ ] Prints: no máximo 2, cada um com especificação.
- [ ] 150 a 600 palavras.
- [ ] Um leigo, lendo só este artigo, consegue fazer a tarefa.
