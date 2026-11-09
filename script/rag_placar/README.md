# Régua do RAG (#1431)

Mede o quanto o agente acha e responde certo em cada formato de material. Roda só no banco local de teste
(`chatwoot_test_1431`), nunca em produção. O que ela mede e a linha de base estão em
`docs/audit/2026-10-31-rag-v2-f0/linha-de-base-formatos.md`; o desenho da F1, em
`docs/audit/2026-11-08-rag-v2-f1/desenho-f1.md`.

## Peças

| arquivo | o que faz |
|---|---|
| `ambiente.sh` | `schema` cria o banco próprio e carrega o schema; `runner` e `rake` rodam no ambiente da régua |
| `ingerir.rb` | cria conta e agente novos e ingere um material pela pipeline real; imprime o id do agente |
| `rodar.sh` | grava a chave só no banco local, ingere cada base, roda o placar e apaga a chave no fim |
| `baixar_reais.sh` | baixa os documentos reais e públicos para fora do repo |
| `bases/` | as bases sintéticas: empresas fictícias, sem nenhum dado real |

Perguntas e gabaritos: `docs/audit/2026-10-31-rag-v2-f0/gabaritos/`.

## Uma rodada

```bash
script/rag_placar/ambiente.sh schema
```

```bash
TETO_USD=0.30 RESPOSTA=1 SAIDA=$TMPDIR/rag_placar/saida script/rag_placar/rodar.sh \
  json:script/rag_placar/bases/json.json:docs/audit/2026-10-31-rag-v2-f0/gabaritos/json.yml
```

- **Com e sem a mudança.** `RAG_FLAGS=rag_corte_por_estrutura` liga as flags na conta da rodada; sem ela, a rodada
  mede o caminho de hoje. As duas rodadas no mesmo código comparam a mudança contra a main.
- **Segmento.** `RAG_SEGMENTO=seguros/corretora` faz o agente nascer com a marca de base desse segmento, como numa
  conta de seguros em produção, e a resposta recebe o bloco do segmento. Sem ela, o agente fica sem base.
- **IA paga.** A ingestão (classificador e embedding) e, com `RESPOSTA=1`, a resposta e o juiz usam a chave da
  OpenAI. Só rode com teto aprovado. `TETO_USD` vale para cada base da rodada.
- **Uma rodada por vez.** Duas em paralelo disputam a mesma chave no mesmo banco.
- **`SAIDA` fora de qualquer repositório.** O detalhe por pergunta carrega o texto do material.
- **Banco sujo.** Cada rodada deixa contas, trechos e anexos no banco. Antes da suíte de specs, rode `schema` de novo:
  há specs que contam anexos.
- **Foto.** As fotos vão separadas por vírgula (`foto:bases/foto-1.jpg,bases/foto-2.jpg:...`) e viram materiais do
  mesmo agente.
