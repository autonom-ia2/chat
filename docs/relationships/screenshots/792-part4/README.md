# Parte 4 — Atributos e mídias: telas reais

Capturas do Chrome em uma instância local real do Chat2You, com Rails, PostgreSQL e APIs autenticadas. Somente dados fictícios e anexos de teste. Não são mockups nem telas da AWS; os pixels não foram editados.

A lateral mantém 40rem: 640px no desktop (1620×928) e 390px no celular (390×844). O scroll mostrado é a rolagem real do painel, mantendo título e rodapé fixos.

| Captura | O que avaliar |
|---|---|
| [01 — Atributos do contato](01-atributos-contato-desktop.png) | Seção expansível, campos nativos, data e número zero. |
| [02 — Rascunho não salvo](02-confirmacao-rascunho-desktop.png) | Diálogo nativo antes de descartar alterações. |
| [03 — Atributos da empresa](03-atributos-empresa-desktop.png) | Acesso aos valores da mesma empresa vinculada. |
| [04 — Configurar campos](04-configurar-campos-desktop.png) | Reutilização da Central e seleção de campos da conta. |
| [05 — Mídias do contato](05-midias-contato-desktop.png) | Busca, ações, miniaturas de imagem/PDF e tratamento de áudio. |
| [06 — Busca no acervo](06-busca-acervo-desktop.png) | Arquivo antigo localizado fora da página inicial. |
| [07 — Mídias da empresa](07-midias-empresa-desktop.png) | Arquivos dos contatos vinculados sem alterar a oportunidade. |
| [08 — Atributos no celular](08-atributos-mobile.png) | Organização em uma coluna e ações acessíveis. |
| [09 — Mídias no celular](09-midias-mobile.png) | Lista responsiva, miniaturas e rodapé. |

O [manifesto](manifest.json) contém as doze verificações no navegador, dimensões, hashes das imagens e fontes. Os resultados e limites estão na [auditoria da parte 4](../../../audit/2026-09-30-792-crm-relationships-part-4.md).

Aguardar aprovação de Rodrigo antes da próxima parte. PR #793 em rascunho; sem merge/deploy.
