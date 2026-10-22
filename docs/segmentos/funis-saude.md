# Funis e CRM da saúde (#2083, lote 1)

Camada `seguros/saude_beneficios`: corretor de planos de saúde, odonto e benefícios. Vocabulário aprovado pelo Rodrigo em 22/10/2026, com base na leitura das conversas de uma conta piloto, numa pesquisa de mercado (32 produtos) e na ANS.

## Vocabulário

| Conceito | Termo |
|---|---|
| quem vende | corretor |
| pessoa | cliente (a etapa diferencia); "lead" só como origem |
| pessoas do plano | vidas (para contar); titular e dependentes (para listar) |
| fornecedor | operadora ("assessoria" é o intermediário do corretor) |
| pagamento | boleto ("valor mensal" no campo de valor) |
| fim da venda | **Implantado**; botão "Marcar como implantado" |
| fim sem venda | **Não fechou**, igual a todo o pacote de seguros (#1550, trava `scripts/i18n-pacotes/cobertura.mjs`) |
| nunca na saúde | segurado, apólice, sinistro, "fechou o plano" |

## Funis prontos

- **Venda de plano** é o próprio modelo `VENDAS`, com nome, etapas e critérios da saúde:
  Novo · Cotação · Proposta · Na operadora · Implantado. Uma recusa da operadora não conta como perda. O card fica em "Na operadora" até a proposta voltar, e a pendência é só uma marca.
  - Critérios: `crm.stage_criteria.vendas.e1..e5` em `config/pacotes/seguros/saude_beneficios/{pt_BR,en}.yml`.
- **Carteira** (`CARTEIRA`, Atender, `camadas: ['seguros/saude_beneficios']`): Boas-vindas · Em uso · Aniversário do contrato · Renovado. Desfechos "Renovado" / "Cancelado".
  - "Aniversário do contrato" é andamento, não espera do cliente, então não pausa o prazo.
  - Critérios: `crm.stage_criteria.carteira.e1..e4` no catálogo base.
  - Aparece primeiro no Atender, como os modelos da corretora.
- O funil que a conta já tem não muda.
- `MODELOS_DA_CORRETORA` virou `MODELOS_DE_CAMADA`: todo modelo com camada usa o nome próprio do desfecho.

## Textos do painel

Os textos do CRM (`CRM_*`) na camada da saúde foram escritos por agentes, um por área, e conferidos por um revisor por área. Cada chave foi decidida como "própria" ou "herda" (herda a camada seguros e, depois, a base). O resto do painel, o Guia, a Central e os agentes vêm nos próximos lotes do #2083.
