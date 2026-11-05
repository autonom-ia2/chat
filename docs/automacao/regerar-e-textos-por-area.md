# Automação livre: textos por área e um comando para regerar (#2569)

Faz parte do épico #2414. As frentes da Automação andam em paralelo (gatilhos, IA como passo, receitas e Guia).
Antes, todas mexiam no mesmo `automacaoLivre.json` e nos mesmos arquivos gerados, e cada merge dava conflito nas
outras. Agora cada frente tem o seu arquivo de texto, e um único comando regera tudo.

## Textos: um arquivo por área, um só namespace

Os textos ficam em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/`, e cada arquivo começa por `AUTOMACAO_LIVRE`:

| Arquivo | Blocos | Frente |
|---|---|---|
| `automacaoLivreGatilhos.json` | `GATILHOS`, `ORIGEM`, `VALOR_DA_MENSAGEM`, `OPERADOR_DA_MENSAGEM` | Gatilhos (F6/F8, #2499) |
| `automacaoLivreIa.json` | `IA` | IA como passo (F7, #2500) |
| `automacaoLivreReceitas.json` | `RECEITAS` | Receitas (F5, #2498) |
| `automacaoLivreEnsaio.json` | `ENSAIO`, `HISTORICO` | Ensaio e histórico (F5) |
| `automacaoLivre.json` | o resto: editor, lista e o que todas usam (`GRUPOS`, `PASSOS`, `CAMPOS`, `FRASES`, `CONFIRA`, `ALTERAR_PAINEL`, `LISTA`…) | comum |

O `index.js` de cada idioma junta os cinco arquivos no mesmo `AUTOMACAO_LIVRE`. Por isso o código continua usando
`AUTOMACAO_LIVRE.<BLOCO>.<CHAVE>` como antes.

Regras:

- **Um bloco mora em um só arquivo.** O index junta os arquivos no primeiro nível de `AUTOMACAO_LIVRE`. Um bloco que
  aparecesse em dois arquivos ficaria só com o último, sem nenhum aviso. O spec
  `app/javascript/dashboard/i18n/specs/automacaoLivrePorArea.spec.js` reprova isso.
- **Bloco novo vai no arquivo da sua frente.** Um bloco que serve a todas vai no `automacaoLivre.json`.
- **Arquivo de área novo** pede os mesmos passos de qualquer catálogo do fork (`docs/i18n/fork-translations.md`):
  - criar o arquivo em en e em pt_BR;
  - registrar em `config/fork_i18n.json` e em `crowdin.yml`;
  - importar no `index.js` dos dois idiomas, com a linha `...<arquivo>.AUTOMACAO_LIVRE,` dentro do bloco
    `AUTOMACAO_LIVRE`;
  - subir de 5 para 6 a contagem no spec acima.
- Os specs Ruby do catálogo (`spec/services/autonomia/automacao/catalogo*_spec.rb`) leem todos os
  `automacaoLivre*.json` do idioma e juntam os blocos no primeiro nível de `AUTOMACAO_LIVRE`, como o index faz.
- O checador dos pacotes (`scripts/i18n-pacotes/checar.mjs`) lê o `index.js` linha a linha. Ele entende
  `...<arquivo>.AUTOMACAO_LIVRE,` só dentro do bloco `AUTOMACAO_LIVRE: {` e reprova essa linha em outro lugar.
- Rode `pnpm i18n:fork:check`.

## Comando único para regerar

```bash
bin/regerar-automacao
```

Ele regera nesta ordem, porque o catálogo de passos lê o formato das ações:

1. `lib/operator_guide/formatos-das-acoes.json`, `parametros-das-leituras.json` e `formatos-das-acoes-cobertura.md`,
   com `rails autonomia:guia:formatos`;
2. `lib/operator_guide/automacao-passos.json`, com `rails autonomia:guia:automacao`;
3. o mapa do Guia (`lib/operator_guide/guia-produto.md` e `app/javascript/dashboard/helper/guideRouteRegistry.js`),
   com `pnpm guia:build`.

Para só conferir, sem escrever nada (falha se algum arquivo está fora de dia):

```bash
bin/regerar-automacao --check
```

Rode o comando depois de mexer em:

- controller, strong params ou validação de um recurso;
- `lib/operator_guide/automacao-*.yml`;
- rota, menu ou `porques.md`.

Envie no mesmo PR todos os arquivos que o comando mudar (`git status`). Ele precisa do Ruby do projeto (`rbenv`), do
`pnpm` e de um banco configurado, como os rakes que chama. A Central (`pnpm central:check`) não é gerada e continua
separada.

## Para quem está com branch aberta

Traga a `main` e passe as suas mudanças em `automacaoLivre.json` para o arquivo da sua área: cada bloco vai para
onde a tabela acima diz. As chaves não mudam, só o arquivo.
