# Novo segmento: passo a passo

Como pôr um tipo novo de conta (por exemplo, `seguros/<tipo>`) para falar a língua do negócio, do vocabulário até a
conta de verdade. Saiu das duas fases feitas até aqui: a corretora (#1802) e a saúde e benefícios (#2083). A mecânica
das camadas está no [README](README.md); aqui fica a ordem do trabalho e o que deu errado no caminho.

## 1. Vocabulário antes do código

1. Abrir o épico do tipo, com o critério de pronto.
2. Juntar as fontes:
   - conversas reais de uma conta piloto, só leitura e com autorização do Rodrigo;
   - pesquisa de mercado;
   - a regra do regulador do ramo.

   O relatório das conversas fica **fora do repositório**: o repo é público, e nenhum nome, número ou trecho de
   cliente entra em doc, PR ou commit.
3. Levar ao Rodrigo uma tabela "conceito → termo", com as palavras proibidas, e esperar a aprovação. Exemplo:
   [`funis-saude.md`](funis-saude.md).
4. Decidir a palavra para o que **não** é do negócio e que o painel chama pelo mesmo nome. Na saúde, "plano" é o plano
   de saúde, então a assinatura da plataforma virou "assinatura".

## 2. Registrar o tipo

Os três lugares entram juntos, senão a spec `spec/config/pacotes_segmentos_spec.rb` reprova:

- `Autonomia::Agents::Nicho::PERFIS`;
- `pacotes.segmentos` em `config/fork_i18n.json`;
- os textos do super admin em `config/locales/autonomia_agents_niche.*.yml`.

A conta passa a usar o tipo quando o super admin escolhe nicho e perfil (`accounts.internal_attributes`, chaves
`autonomia_agents_nicho` e `autonomia_agents_perfil`).

## 3. Lotes

Um PR por lote, todos com `Refs #<épico>`.

1. **Painel e funis.** Chaves do painel em `app/javascript/dashboard/i18n/pacotes/<camada>/{pt_BR,en}.json`. Modelos
   de funil por camada (`camadas` do modelo) e, quando o tipo muda o comportamento de uma etapa, a entrada dele em
   `app/javascript/dashboard/routes/dashboard/crm/components/funil/variantes.json` (um arquivo só, lido pelo painel
   e pelo servidor). Critérios das etapas em `config/pacotes/<camada>/*.yml`.
2. **Guia, Central, agentes e servidor.**
   - Guia: `lib/operator_guide/pacotes/<camada>/porques.md`.
   - Central: `lib/central_de_ajuda_pacotes/<camada>/<cap>/<id>-<slug>.md`.
   - Agentes: `config/agentes_por_pacote/<camada>/agentes.md`, com a versão nova em `versoes.yml`.
   - Servidor: o yml de `config/pacotes/<camada>`.
3. **Inventário contra o perfil irmão**, explicado abaixo.
4. **Conferir no ar** numa conta de teste e depois no piloto (seção 6).

## 4. Inventário contra o perfil irmão

O tipo novo herda da camada de cima tudo o que não troca. O risco está no que o **perfil irmão** troca e o novo não:
a conta nova vê o texto genérico da base onde o irmão já fala a língua do ramo. Foram 108 chaves na saúde.

1. Compor o texto que cada conta vê (base ← camada de cima ← perfil) e comparar os dois perfis nas cinco
   superfícies: painel, servidor, Guia, Central e agentes.
2. Classificar cada chave que só o irmão troca:
   - **A:** igual ao irmão;
   - **B:** texto próprio;
   - **C:** fica a base, com o motivo.

   Levar a lista ao Rodrigo antes do PR. Exemplo: [`proposta-108-chaves-saude.md`](proposta-108-chaves-saude.md).
3. Procurar palavra proibida composta, por palavra inteira, e ler cada achado no trecho antes de chamar de real.
   "Perdeu a conexão" não é desfecho de venda.

## 5. Checagens de todo PR de segmento

```sh
pnpm i18n:fork:check   # chaves, idiomas, parâmetros e a trava de ganho/perda
pnpm guia:build        # regera o guia-produto.md de cada camada
pnpm guia:check
pnpm central:check
bundle exec rspec spec/config/pacotes_segmentos_spec.rb spec/config/pacotes_rotulos_no_guia_e_central_spec.rb
```

A trava `spec/config/pacotes_rotulos_no_guia_e_central_spec.rb` pega o Guia ou a Central do perfil citando o nome
antigo de um botão que o pacote renomeou:

- rótulo de uma palavra só conta em negrito;
- rótulo de duas ou mais palavras conta também em texto comum;
- coincidência entra na lista de exceções, com o motivo;
- exceção que deixa de acontecer também falha.

Tipo novo entra na lista `perfis` da spec.

## 6. Conferir no ar

1. Conferir o perfil da conta no banco, só leitura (psql via SSM, nunca `rails runner`).
2. Olhar sem clicar em ação: o painel (Configurações, exemplos da busca da Central), a Central pela própria busca e o
   bundle do painel publicado (`/vite/.vite/manifest.json` → arquivo do pacote).
3. O Guia não tem página pública. A Central base vai ao portal público "plataforma" (`Publicador`), mas as
   variantes por camada não vão: a Central da camada só se confere pela tela da conta.
4. Conta de cliente real é só leitura: nada de enviar, mover, atribuir ou editar.

## 7. Tropeços já vistos

- **Seção da Central é trocada inteira.** A variante copia a seção da camada de cima. Se a base mudar depois, a
  variante não acompanha: mudança no texto geral de um trecho sobreposto precisa ser repetida na camada.
- **O Guia do pacote troca `titulo`, `intent`, `onde_fica`, `perfil`, `pre_requisitos`, `passos` e `gotchas`.** Rota e gate
  saem do roteador. No `guia-produto.md` gerado, o `titulo` vira o cabeçalho do fluxo, e não um campo.
- **Trocar o título de um modelo pronto de WhatsApp** (`MODELOS_WHATSAPP.OBJETIVOS.*.TITULO`) muda o nome sugerido
  do modelo e o fixture `spec/fixtures/whatsapp_templates/prontos.json`. Regere o fixture com
  `pnpm test prontos -- -u` e leia o diff.
- **Título trocado na variante da Central** vale no artigo, mas os links "Veja também" dos outros artigos mostram o
  título da base, que vem do mapa geral.
- **Nome de botão citado em texto comum** passa pelo olho. Foi o que a primeira trava, só de negrito, deixou passar.
- **Perguntas do Guia (`intent`)** também decidem para onde o Guia leva. "Qual plano eu contratei?" levaria quem fala
  do plano de saúde para a tela da assinatura.
- **Rodar a CI de novo logo depois de um hotfix na main** pode usar a base antiga: o GitHub demora a recalcular o
  merge ref do PR. Confira no log do checkout ("Merge <head> into <base>") antes de concluir.
