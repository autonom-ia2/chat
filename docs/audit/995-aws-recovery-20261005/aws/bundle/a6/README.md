# A6 — ordem de termos de vocabulário fechado

Candidata local sobre A5, sem nova coleta. A5 leu integralmente o fechamento de
175 bytes, mas sua projeção deixou o motivo como desconhecido. O texto daquele
motivo não foi armazenado e não pode ser reconstruído por este pacote.

O delta acrescenta apenas `ordered_reason_terms` à projeção pública do helper.
A função pura recebe no máximo 510 bytes UTF-8 da razão já limitada por A5 e
emite uma sequência de até 64 enums, com estado e marcador de truncamento.

| Regra | Resultado |
| --- | --- |
| Vocabulário fechado | Campos, verbos, comparações, conectivos e negações de uma lista literal no fonte |
| ID conhecido | `OWN_SESSION` ou `FOREIGN_SESSION` somente depois de comparação exata, antes de normalizar letras |
| Literais com nomes dos marcadores | O texto recebido `OWN_SESSION` ou `FOREIGN_SESSION` vira `OTHER`; esses nomes não são chaves do vocabulário |
| Prefixos/sufixos de IDs | Permanecem desconhecidos; não há busca por substring ou recuperação de sufixo |
| Negação | `NOT`, `NO`, `WITHOUT` e contrações ASCII/curvas têm enums explícitos; `UNLESS`, `EXCEPT`, `ONLY` e `IF` conservam conectivos |
| Operadores | Somente chunks inteiros `=`, `==`, `===`, `!=`, `<>`, `!==`, `<`, `>`, `<=`, `>=`; igualdade e desigualdade têm enums distintos |
| Desconhecido | `OTHER`, com marcadores consecutivos colapsados; nunca fragmento bruto, ID literal, token, URL ou hash |
| URL ou span opaco | Vira `OTHER` antes de procurar vocabulário ou IDs em seu conteúdo; operadores embutidos não são extraídos |
| Limite | Ao exceder 64 termos, `truncated=true`; uma negação depois do limite não pode ser considerada ausente |

Termos preservam a ordem dos átomos observados; pontuação não reconhecida pode
aparecer como `OTHER`. Palavras Unicode desconhecidas não fornecem um sufixo
ASCII permitido. A representação contém lacunas deliberadas, não é o texto
integral da razão e não valida sozinha uma cláusula ou relação causal.

Exemplo **sintético**, sem relação com o texto A5 perdido:

```text
session id [ID estrangeiro] does not equal session id [ID próprio]
→ SESSION ID FOREIGN_SESSION DOES NOT EQUAL SESSION ID OWN_SESSION
```

O frame continua inválido e o mesmo `control_frame_invalid` é mantido. A função
de captura A5, seus caps, prazo e tentativa única permanecem byte a byte iguais.
Collector, wrapper, serviço, parser, requisição enviada e cleanup também são
idênticos. O único outro arquivo operacional alterado é o preflight, que muda
um pin do helper. Não há nova rede, parser de protocolo, aceite de frame, ACK,
retry, alteração IAM ou classificador. Todos os campos de classificação e de
elegibilidade de cutover continuam falsos.

`python3 test_reason_terms.py` roda oito fixtures puros focais: ordem e troca dos
IDs, negações/conectivos/contrações, operadores distintos sem extrair query,
placeholders verdadeiros versus texto literal e IDs parciais, privacidade e
spans opacos, Unicode, limite de termos com negação tardia, limite em bytes e
comparação da projeção anterior sem o campo novo. O baseline A5 incluído é
somente fonte de teste; nenhuma chave, payload real ou sessão é usado.

A primeira execução encontrou um erro no fixture: `session ` repetido 64 vezes
mais `not` já ultrapassava o limite de bytes. O caso foi corrigido para `id `
repetido 64 vezes, conservando os limites do código. Log e recibo iniciais foram
preservados. A revisão independente também apontou que `==`/`!=` e `UNLESS`
precisavam de representação distinta; os enums e fixtures focais foram
acrescentados antes do congelamento. Os oito casos finais passaram no cloud;
os arquivos `auth-a6-fixture-cloud-*` preservam essa execução, e os nomes sem
`cloud` serão produzidos pelo Mac com os mesmos bytes.

`PREPARED.json` fixa fontes, diffs, testes e a igualdade da captura e dos quatro
módulos preservados. A candidata ainda exige revisão e liberação coordenada
antes de promoção ou coleta. Qualquer execução futura precisará de C0 novo com
o hash A6 do helper e CURRENT compatível; não se reutiliza o C0 A5 com um mapa de
fontes diferente. Nenhum recibo anterior ou gate de consumidor é alterado.
