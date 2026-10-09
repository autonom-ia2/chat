# B1 — checagem limitada do frontend e leitor público

Alvo: fingerprint `04baa47e5200089e89a17e322769890cc9263aab44f1870bd762c4b35f298738`, inventário de 53 arquivos em `/tmp/chat2you-agentes-b1-review-check-files.json`. Checagem das correções já apontadas na revisão normal; não é uma nova revisão geral. Autor das correções conferidas: r9_produto no filtro e r9_tecnica no Jbuilder; root não escreveu esses trechos de produto.

## B1-UI-01 — fechado na inspeção

`hasAgentFilter` usa a presença do ID ativo, independente de o catálogo já ter carregado. Todos os agentes só fica selecionado sem ID. ID ausente do catálogo gera uma opção selecionada com AGENT_BY_ID localizada; quando o catálogo contém o mesmo ID, usa o nome real sem duplicar o fallback. Ambos os caminhos mantêm o evento agent_id e a limpeza existente. Templates/DropdownMenu tratam o rótulo como texto; não foi criado endpoint, permissão ou transformação do ID.

O caso novo reproduziu RED no snapshot9 e passou com os demais casos no snapshot10 (14 casos do filtro; conjunto frontend de 43 testes). Depois houve somente ajuste manual de quebra de linha no componente e no mock de tradução da spec; prova do snapshot final, ESLint/build/catálogos e bateria completa ainda pendentes. Não presumo resultado dessas etapas.

## B1-TEC-01 — fechado na inspeção do leitor

`_agent.json.jbuilder` agora inclui somente a chave pública faltante handoff_target_type no slice existente. Campos internos de instrução/scaffold e config não entram por esse ajuste. O spec de exposição exige a chave/valor, e passou no conjunto de 180 exemplos snapshot10. O valor adicional draft_retention_hours é número do parser compartilhado e não expõe ENV bruto, credencial ou configuração operacional; a checagem do domínio de retenção fica na lente técnica independente.

## Resultado

Sem residual concreto nos dois achados conferidos. Isso fecha somente a inspeção estática limitada e a prova já executada identificada acima. A conclusão B1 depende das duas lentes técnicas, dos checks finais e não constitui aceite de telas reais ou release. Sem execução de produto, banco, produção, merge, fila ou deploy neste parecer.
