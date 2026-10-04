# Busca da Central de Ajuda: a régua

Por que existe: a busca da Central precisa achar o artigo certo a partir do que uma pessoa leiga escreve
("como conecto meu zap", "conversa travou"), não do título do artigo. Esta pasta guarda as frases de teste
e a resposta esperada de cada uma, para medir o acerto de novo sempre que a busca, os artigos ou o modelo
mudarem — sem depender de pasta temporária de ninguém (#977).

## O que foi medido em 04/10/2026

| | Acerta o 1º |
|---|---|
| Busca por palavras (a de hoje, instantânea) | 48% |
| Melhor resposta pelo Jev (TypeSafe), variante B | 94% no conjunto de ajuste, 96% no de validação |

- Jev: ~0,53 s por busca e ~20,7 mil tokens de entrada (a lista de artigos inteira vai em cada pergunta).
  A US$ 0,042 por milhão, sai ~US$ 0,0009 por busca.
- Os erros que sobraram vieram com certeza abaixo de 0,35. Por isso a tela só destaca a "Melhor resposta"
  com certeza de 0,35 para cima; abaixo disso a escolha vai para o topo da lista comum, sem destaque.
- A busca por palavras continua: é instantânea e é a reserva quando o Jev não responde.

## Como rodar

Precisa da Central publicada na instalação (`bundle exec rails central_de_ajuda:publicar`) e de uma conta
com administrador. O número é o id da conta; os artigos que a conta não vê ficam fora da conta.

```sh
# Só a busca por palavras. De graça.
bundle exec rails "central_de_ajuda:avaliar_busca[1]"

# Com a Melhor resposta. PAGO: antes de começar, mostra quantos casos e o custo estimado.
AVALIAR_COM_JEV=1 bundle exec rails "central_de_ajuda:avaliar_busca[1]"
```

Sai uma linha por conjunto (ajuste e validação) — acerto no 1º, nos 3 primeiros (com o Jev, a lista que a
tela mostra: a Melhor resposta no topo e as palavras depois), vazios, certeza média dos erros — e a lista
dos erros. Com o Jev, a rodada desliga o cache só dentro dela, para medir o modelo e não uma resposta
guardada. Fica fora do CI porque custa dinheiro.

## Como acrescentar casos

Em `casos.json`, um objeto por frase: `q` é o que a pessoa escreveria, `ok` são os ids dos artigos que
respondem (o primeiro que servir conta como acerto), `conjunto` é `ajuste` ou `validacao`.

- Escreva como a pessoa leiga escreveria: gíria, erro de digitação, o problema em vez do nome da tela.
  Não copie o título do artigo — aí qualquer busca acerta e a régua não mede nada.
- Ao mexer na busca (instrução do Jev, texto mandado de cada artigo, pesos das palavras), ajuste olhando
  só o conjunto `ajuste`. O `validacao` é a prova: se ele cai enquanto o ajuste sobe, a mudança decorou
  as frases em vez de melhorar a busca.
- Caso novo entra primeiro na validação. Promova para o ajuste só depois de ter usado o resultado dele
  para decidir alguma coisa.
