# Como o canal `whatsapp_modelo` entra no `Ai::Redacao::Escrever` (#1354)

Arquivos desta pasta:
- `comum.md`: vai para `prompts/comum.md`;
- `whatsapp_modelo.md`: vai para `prompts/whatsapp_modelo.md`;
- `SCHEMA.json`: o schema estrito.

O `instructions` é `comum.md` + `whatsapp_modelo.md`, nessa ordem. O bloco comum fica no começo para ser o prefixo em
cache entre os canais, com `cache_key_scope: :feature`.

## 1. Entrada que o serviço monta (mensagem `user`, JSON)

```json
{
  "canal": "whatsapp_modelo",
  "proposito": "<proposito do chamador>",
  "pedido": "<frase da pessoa>" ,
  "base": null,
  "tom": { "kit": "<kit da marca ou null>", "escolha": "curto | simpatico | formal | null" },
  "limites": { "max_chars": 350, "categoria_desejada": "servico | divulgacao | null", "sem_midia": true },
  "chaves": {
    "permitidas": [ { "chave": "cliente.primeiro_nome", "rotulo": "Primeiro nome do cliente", "tipo": "texto", "exemplo": "Ana" } ],
    "obrigatorias": ["horario.data_hora"]
  },
  "opcoes": 2
}
```

**`chaves.permitidas`.** O contrato traz só a lista de chaves. O serviço acrescenta rótulo, tipo e exemplo **fictício**
do `TemplateFields::Catalog`. Foi assim que a bateria rodou, e o rótulo é o que permite ao modelo escolher o campo
certo. O exemplo nunca é o valor real nem o que a pessoa digitou.

**`max_chars` por tom.** Para manter o comportamento medido, o chamador de modelos do WhatsApp passa:

| Tom | `max_chars` |
|---|---|
| curto | 200 |
| simpatico | 350 |
| formal | 450 |
| sem escolha | 450 |

O máximo de 1024 é a regra da Meta. O código confere os dois.

## 2. O que a bateria tinha e o contrato não tem (decidir com a sessão Agendamento)

**`texto` não basta para um modelo do WhatsApp.** O corpo vai em `texto`, mas cabeçalho, rodapé, botões e
`nome_sugerido` também fazem parte da opção. Proponho o objeto `whatsapp` dentro de cada opção, presente só no schema
desse canal. Sem ele, "Criar com IA" perde os botões (Confirmar, Remarcar) e o cabeçalho, que estão no desenho da tela
(`../DESENHO.md` §2.2).

**Outras extensões que passaram na bateria e eu manteria no schema do modelo:**

| Campo | Para que serve |
|---|---|
| `sugestoes` | Os chips de objetivo em `precisa_mais_info`, para leigo |
| `problemas_encontrados` | O "O que encontramos" no modo melhorar |
| `o_que_mudou` | A explicação do antes e depois |
| `certeza_categoria` | Telemetria e calibração. O selo continua com a conferência |

O serviço pode expor esses campos ou descartá-los. Tirar algum deles **do schema** muda o que o modelo gera, e aí a
bateria tem de rodar de novo.

**Mapeamentos:**

| Na bateria | No contrato |
|---|---|
| `nao_da_para_ser_servico` | `status: ok`, com a opção em `categoria_prevista: divulgacao` e `motivo_categoria` começando por "Não dá para ser aviso de serviço:" |
| `motivo` de `nao_se_aplica` | `pergunta` |
| `leitura_do_pedido` | Some. O "isto é divulgação" vai em `motivo_categoria` de cada opção |
| Exemplo de cada campo | Sai do catálogo (`chaves.permitidas[].exemplo`). Vai à Meta em `example.body_text` e a pessoa pode trocar |

A tela mostra a faixa laranja ("Promoção é divulgação…") quando todas as opções vêm como `divulgacao` e
`categoria_desejada` era `servico` ou null. Não precisa de campo novo.

**Opções.** O contrato tem padrão 2. A bateria pedia 2 ou 3 no criar e 1 ou 2 no melhorar. O schema usa
`maxItems: 3`, e o código ajusta para o `opcoes` pedido. Recomendo `opcoes: 3` no criar e `2` no melhorar.

## 3. Modo melhorar: como entram os pedidos

`base` é o texto atual: só o corpo, com as chaves `{{…}}`. Cabeçalho, rodapé e botões atuais vão dentro de `base`
quando o canal é `whatsapp_modelo`:

```json
"base": { "texto": "...", "whatsapp": { "cabecalho": null, "rodape": null, "botoes": [] } }
```

Nos outros canais, `base` pode ser só a string.

`pedido` no modo melhorar é **estruturado**. Não é frase solta, para o código não precisar ler linguagem:

```json
"pedido": {
  "melhorias": ["mais_curto", "mais_claro", "manter_como_servico", "corrigir_recusa"],
  "observacao": null,
  "recusa_da_meta": { "motivo": "INVALID_FORMAT", "recomendacao": "<texto da Meta>" }
}
```

| Chip na tela | `melhorias` | Onde está a regra |
|---|---|---|
| Mais curto | `mais_curto` | `comum.md`: ≥ 30% menor, sem campo novo |
| Mais claro | `mais_claro` | `comum.md` |
| Manter como aviso de serviço (mais barato) | `manter_como_servico` | `whatsapp_modelo.md`. A saída honesta é "Não dá para ser aviso de serviço:" |
| Corrigir o que pode causar recusa | `corrigir_recusa` | `whatsapp_modelo.md`. Usa `recusa_da_meta` quando veio da sincronia ou do webhook |

**Detalhes do pedido:**
- `observacao` é texto livre opcional da pessoa e é tratado como dado (`comum.md`).
- `recusa_da_meta` é `null` fora da correção.
- A 2ª tentativa de `manter_como_servico` (`gpt-6.1-sol`, em job) é decisão do chamador. O serviço só precisa aceitar
  `modelo:` como parâmetro, ou expor um modo job. **Não está no contrato:** registrar com a sessão Agendamento.

**Conferência depois da resposta,** além da lista do contrato (chave fora da lista, obrigatória ausente, campo no fim
e tamanho):
- campo no começo;
- campos colados;
- `{{1}}`;
- campos da base mantidos no melhorar;
- nenhum campo novo em `mais_curto`;
- `chaves_usadas` igual às chaves do texto, do cabeçalho e dos botões;
- limites de cabeçalho, rodapé e botões da Meta;
- `nome_sugerido` só com `a-z0-9_`;
- trecho de `problemas_encontrados` presente na base (`include?`).

Todas são de estrutura, sem regex: o parser vai por `index("{{")`. A opção que falha é descartada. Se nenhuma sobra, a
tela mostra "Não conseguimos escrever agora."

## 4. Equivalência com o que passou na bateria

O conteúdo das regras e dos exemplos é o da v3 (`../PROMPT.md`), redistribuído assim:
- as regras gerais de escrita, campos, tom, dado × instrução, melhorar e os 4 exemplos gerais ficaram no comum;
- tipo, Meta, cabeçalho, rodapé, botões, `manter_como_servico`, `corrigir_recusa` e os 5 exemplos de modelo ficaram no
  canal.

**O que mudou de verdade:**
- a ordem dos blocos;
- os nomes do contrato (`status`, `texto`, `categoria_prevista`, `pergunta`);
- o limite de tamanho, que veio de `limites.max_chars` em vez de vir pelo tom;
- a saída `nao_da_para_ser_servico`, que virou `motivo_categoria`.

**Isso é mudança de prompt e de schema: a nota de 29/30 não vale automaticamente.** Rodar a mesma bateria
(`../bateria.jsonl`, adaptando a entrada ao formato acima) assim que o serviço existir. A combinação é rodar com a chave
da conta 16, com teto. Custo esperado: ~US$ 0,02 no luna para os 30 casos, mais o juiz.

Não rodei nada pago nesta etapa.
