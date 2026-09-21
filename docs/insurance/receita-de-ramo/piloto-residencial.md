# Piloto de residencial: registro de campo

O que a aplicação da [RECEITA](RECEITA.md) a residencial mostrou, fase por fase. Cada rodada traz o que se
esperava e o que aconteceu. Nomes e CPFs dos cenários são fictícios, gerados com o algoritmo de dígito
verificador; as cotações rodaram na conta de **teste** do portal (5 seguradoras), nunca na de uma corretora.

## Fase 1, rodada 1 — 21/09/2026

Pelo caminho do produto: `AggerAdapter.startQuote` na versão da `main` do adapter (`3cbd864`), com a entrada
montada como `Insurance::QuoteInput#de_ramo` monta: `segurado` com CPF, nome, CEP e número, e `configuracoes` com
os quinze campos de origem `cliente` do schema de residencial.

### Conferência gratuita (`quote/validate`), antes de qualquer cotação

- **Complemento vazio é recusado como dado faltando.** O schema marca `imovelComplemento` como obrigatório, e casa
  não tem complemento. Em produção, o agente pergunta, o cliente diz que não tem, o vazio é recusado, e o agente
  pergunta de novo. Para seguir a rodada os cenários usaram "Casa", que o produto não mandaria.
- **CPF com dígito verificador errado passa pela conferência** e só é recusado no portal (cenário S7).
- **Os quatro códigos de residencial não têm lista de valores** (`imovelUso`, `imovelTipoResidencia`,
  `imovelConstrucao`, `imovelObjetoSegurado`). Nem o conhecimento colhido do portal os descreve; o adapter manda 1.

### Cotações reais

| Cenário | Esperado | Aconteceu | Com preço |
|---|---|---|---|
| S1: simples, como o produto manda hoje | recusa por endereço | as 5 recusaram: "A cidade deve ser informada corretamente". O portal gravou o endereço vazio | 0 de 5 |
| S2: simples, com o endereço da consulta de CEP do portal | cota | cotou | 2 de 5 (R$ 242,28 e R$ 312,73, total) |
| S3: complexo, inquilino, sete dispositivos de segurança, apartamento com complemento | cota | cotou; os campos de sim e não foram gravados como enviados | 2 de 5 (R$ 244,17 e R$ 410,91) |
| S4: cidade de CEP único, sem rua | recusa por logradouro | as 5 recusaram: "Logradouro deve ser informado corretamente" | 0 de 5 |
| S5: CEP inexistente | falha tratável | as 5 recusaram: "A cidade deve ser informada corretamente" (a consulta de CEP não roda nesse caminho, então o erro 502 do portal nem aparece) | 0 de 5 |
| S7: CPF inválido | recusa | o portal devolveu HTTP 400 "CPF/CNPJ inválido" no envio, e o adapter o tratou como **erro de protocolo**, que o chat2you trata como falha técnica | pedido recusado |
| S8: patrimônio histórico | recusa de risco | a Ezze cotou com o **mesmo preço** do S2; as outras, instabilidade ou verba | 1 de 5 |

### O que a rodada prova

1. **Pelo caminho do produto, residencial não cota hoje.** S1 é exatamente o que a Lia mandaria, e as cinco
   seguradoras recusaram por endereço. A tabela de 07/09 provava o corpo, não o produto.
2. **Com o endereço da consulta de CEP do portal, cota.** S2 é a mesma entrada com os quatro campos de endereço, e
   o portal os gravou. O logradouro no formato do portal ("Avenida Paulista - de 612 A 1510 - Lado Par") foi aceito.
3. **Cidade de CEP único exige perguntar a rua** (S4).
4. **Os campos de sim e não atravessam**: inquilino, alarme monitorado e patrimônio histórico foram gravados como
   enviados (leitura de volta).

### O que ela mostrou e ainda não explica

- **Mapfre recusou os três cenários com endereço** com "O tipo de verba selecionado não está disponível para este
  cenário nesta seguradora". É o padrão de cobertura que o adapter manda, não o cliente. Uma seguradora perdida em
  toda cotação.
- **"Instabilidade" da seguradora e "a cidade deve ser informada" chegam como `declined`**, o mesmo status de uma
  recusa de risco. São três coisas diferentes: seguradora fora agora, dado nosso errado, e risco recusado. O
  cliente não pode ouvir as três do mesmo jeito.
- **A linha de endereço impressa repete o número**: "Avenida Anchieta, 200, 200 Apto 42". A consulta de CEP do
  portal às vezes devolve o número dentro do logradouro. Aparece na proposta.
- **Três cotações com preço levaram cerca de 7 minutos** no laço desta rodada. O laço é do script, não o do
  produto; o fechamento pelas duas leituras iguais só foi medido em auto. A medir na fase 6.

### Consequência para a fase 2 (no adapter, antes do chat2you)

1. Derivar o endereço do imóvel pela consulta de CEP do portal no caminho dos outros ramos, como auto faz.
2. CEP sem rua: pedir a rua ao cliente pela conferência gratuita, não deixar o portal recusar.
3. CEP inexistente: tratar o erro do portal como "confirme o CEP", não como falha técnica.
4. Complemento vazio aceito.
5. CPF e CNPJ com dígito verificador conferidos na conferência gratuita.
6. Descobrir e publicar os valores dos quatro códigos de residencial, com descrição que ensina a extrair da
   conversa.
7. Investigar a recusa da Mapfre pelo tipo de verba.
8. Separar instabilidade da seguradora, dado nosso errado e recusa de risco.
