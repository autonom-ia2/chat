# Parte 3 — Screenshots reais para aprovação

Capturas da aplicação local, com Rails, APIs e PostgreSQL reais e dados sintéticos. Não são imagens conceituais nem produção AWS. Não houve edição dos pixels.

A largura da lateral do card foi igualada à de **Editar funil**: 40rem, medidos em 640px no desktop e notebook. No celular, respeita o viewport de 390px.

| Arquivo | O que conferir |
|---|---|
| [01 — Relacionamento](01-relacionamento-desktop.png) | Contato e empresa canônicos; hierarquia, identificação e ações. |
| [02 — Editar contato](02-editar-contato-desktop.png) | Campos reais e Salvar contato no rodapé fixo, separado da oportunidade. |
| [03 — Editar funil](03-editar-funil-desktop.png) | Comparação da borda/largura com a lateral do card. |
| [04 — Sem relacionamento](04-sem-relacionamento-desktop.png) | Estado vazio com vínculo ou criação posterior. |
| [05 — Criar contato](05-criar-contato-desktop.png) | Formulário ligado à API de criar pessoa no mesmo card. |
| [06 — Texto legado](06-vinculo-legado-desktop.png) | Informação textual não apresentada como associação empresarial confirmada. |
| [07 — Celular](07-relacionamento-mobile.png) | Nome e ações sem quebra indevida; navegação e rolagem da lateral. |
| [08 — Notebook](08-relacionamento-notebook.png) | Mesma largura de 640px em 1366×768. |
| [09 — Edição no celular](09-editar-contato-mobile.png) | Botão Salvar contato visível no rodapé sem depender da rolagem. |

Desktop: 1620×928. Notebook: 1366×768. Celular: 390×844. `manifest-initial.json` contém a última execução das medições/capturas; o nome do arquivo foi mantido pelo script. `acceptance.json` registra os sete fluxos reais de interação. `screenshots.json` registra os hashes dos PNGs.

Atributos personalizados, mídias, edição empresarial inline e Nova oportunidade completa não estão concluídos nesta parte. A próxima etapa exige aprovação de Rodrigo; nenhum merge/deploy foi autorizado.

Detalhes de testes, comparação visual, avisos e limitações na [auditoria](../../../audit/2026-09-30-792-crm-relationships-part-3.md).
