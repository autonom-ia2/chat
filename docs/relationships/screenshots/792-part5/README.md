# Parte 5 — Telas reais da empresa dentro do card

Capturas do Chat2You em execução local, com Rails, PostgreSQL e APIs reais. Cadastros fictícios. Sem edição dos pixels, sem imagens geradas e sem publicação na AWS.

A lateral permanece com 640px em desktop e notebook, a mesma largura de Editar funil. No celular usa os 390px disponíveis. Os botões de confirmação ficam no rodapé fixo.

| Arquivo | Estado para aprovação |
|---|---|
| [01 — Empresa no card](01-empresa-acoes-desktop.png) | Ações Editar, Trocar, Abrir e Desvincular. |
| [02 — Editar empresa](02-editar-empresa-desktop.png) | Nome, domínio e descrição; confirmação separada da oportunidade. |
| [03 — Domínio duplicado](03-dominio-repetido-desktop.png) | Erro real da API, sem perder preenchimento nem salvar parcialmente. |
| [04 — Trocar vínculo](04-trocar-vinculo-desktop.png) | Empresas homônimas distintas pelo domínio; seleção antes de confirmar. |
| [05 — Desvincular](05-desvincular-confirmacao-desktop.png) | Confirmação explícita sem excluir cadastro ou arquivos. |
| [06 — Sem empresa](06-sem-empresa-desktop.png) | Vincular uma empresa existente sem sair do card. |
| [07 — Editar no celular](07-editar-empresa-mobile.png) | Formulário responsivo e ação fixa no rodapé. |
| [08 — Editar no notebook](08-editar-empresa-notebook.png) | Mesma largura em 1366×768. |

Desktop: 1620×928. Celular: 390×844. O screenshot pode mostrar a posição de rolagem necessária para visualizar o formulário; não é recorte ou montagem.

`manifest.json` registra as 11 verificações desta parte, viewports, medidas, hashes das imagens e fontes. `previous-flows.json` registra 12 verificações de atributos/mídias da parte 4 reexecutadas no código atual. O 422 de domínio duplicado é intencional; o 404 local de limites Enterprise permanece identificado.

A empresa nova e o cadastro completo de Nova oportunidade ainda não fazem parte desta entrega. Aguardar aprovação de Rodrigo antes da parte seguinte. PR #793 em rascunho, sem merge/deploy.

[Auditoria, comandos e limites](../../../audit/2026-09-30-792-crm-relationships-part-5.md).
