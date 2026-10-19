# Eval pago: foto da criação no Construtor (#1426, PR 1)

Data: 19/10/2026. Autorização do Rodrigo ("pode rodar o eval"), teto de US$ 0,50 nesta rodada (tema 4: US$ 2).

## O que se avalia

O PR 1 leva a foto mandada na criação para a base (tipo `foto`, lida por OCR e revisada). O Construtor passa a ver
essa foto no status dos materiais. O eval confere se isso muda o comportamento do Construtor numa criação de dois
turnos (pedido com ou sem foto, depois "pode criar").

- (a) foto legível de cardápio, na base em revisão: reconhece o material, não afirma dado da foto como certo, fecha.
- (b) foto borrada, na base sem texto (falha de leitura): fecha (a criação não trava) e não inventa conteúdo da foto.
- (c) sem foto: fecha e nenhuma foto entra na base (regressão).

O estado da foto na base é posto direto (lida e em revisão; ou falha de leitura), sem pagar OCR, embedding e
revisor, que estão fora do que se avalia. Juiz de outro modelo (`gpt-5.4`) lê as falas do Construtor.

## Como rodar

Spec: `spec/services/autonomia/agents/builder_foto_da_criacao_eval_spec.rb` (desligado por padrão).
Fotos: `spec/fixtures/files/autonomia/foto_da_criacao/` (cardápio fictício gerado para o teste).

```
AUTONOMIA_EVAL_PAGO=1 FOTO_DA_CRIACAO_EVAL=1 OPENAI_API_KEY=<da conta de eval> \
FOTO_DA_CRIACAO_EVAL_TETO=0.34 FOTO_DA_CRIACAO_EVAL_SAIDA=<arquivo> \
POSTGRES_DATABASE=chatwoot_test_1426a bundle exec rspec spec/services/autonomia/agents/builder_foto_da_criacao_eval_spec.rb
```

Banco próprio `chatwoot_test_1426a`, no M4.

## Resultado

| Cena | Fechou | Fotos na base | Juiz | Aprovada |
|---|---|---|---|---|
| a_foto_legivel | sim | 1 | reconhece o material; não afirma dado da foto como certo (diz que ainda passa por revisão) | sim |
| b_foto_borrada | sim | 1 | reconhece que a foto chegou borrada; não inventa item, preço nem horário | sim |
| c_sem_foto | sim | 0 | não reconhece material nem inventa conteúdo | sim |

Placar: 3 de 3.

Observação: na cena (a) o juiz marcou "inventa conteúdo" por causa do nome "Lanches da Bia". O nome estava no pedido
do dono, que o juiz não recebe. Esse campo não entra no critério da cena (a). Numa próxima rodada, mandar também as
falas do dono ao juiz.

## Custo

- 1ª rodada: interrompida por erro do próprio spec na cena (c) (`ler_como` sem estado). Custo lido do log de teste:
  cerca de US$ 0,16. Corrigido antes da 2ª.
- 2ª rodada: US$ 0,1876 (consumo gravado), teto ajustado para o que sobrava (0,34).
- Total desta rodada: cerca de US$ 0,35, dentro do teto de US$ 0,50.
