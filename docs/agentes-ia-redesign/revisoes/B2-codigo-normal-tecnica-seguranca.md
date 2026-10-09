# Revisão normal B2 — técnica e segurança

Data: 2026-10-07

Alvo congelado: snapshot `/Users/Shared/maccluster-workspaces/chat2you/20261007-180541-532a5b7b-fb59e79917-20069aba/src`, fingerprint informado `fb59e799170f2c57a42bf498a0beaebba382305b0f75df50a4fb2b351af0ef27`.

Esta revisão foi somente leitura sobre o snapshot. Não executei testes, build, banco ou produção. O foco foi o gate da conta, as projeções/listagens, BE-28, callbacks, canais, copilot e os escritores de material, respeitando as fatias atribuídas e sem reabrir os contratos do StateStore/Recorder/Digest.

## Resultado

**NÃO APROVADO.** Há um bloqueio de contrato e privacidade no fluxo de respostas marcadas como erradas (BE-28). O restante da lente não produziu outro achado concreto neste ciclo.

## B2-TEC-01 — P2 — nota privada do agente entra e aparece como “resposta errada”

**Causa.** A fronteira de entrada só testa `sender_type == 'AgentBot'` e a marca `autonomia_agent_id`; não exige mensagem pública. A fronteira de leitura de BE-28 repete o filtro amplo por `sender_type` e conversa, sem excluir `messages.private`.

**Prova no alvo.**

- `app/controllers/api/v1/accounts/autonomia/agents/message_reports_controller.rb:37-42` aceita a mensagem quando o marcador está presente, mas não testa `@message.private?`.
- `app/services/autonomia/agents/tools/nota_interna.rb:24-35` cria exatamente uma mensagem `private: true`, `sender_type: 'AgentBot'` e com `autonomia_agent_id`; portanto o caminho aceito não é apenas teórico.
- `app/services/autonomia/agents/analytics.rb:232-239` seleciona reports por conta, janela, `sender_type: 'AgentBot'` e conversa atendida, sem predicado `private: false`.
- `app/controllers/api/v1/accounts/autonomia/agents/analytics_controller.rb:53-59` serializa `report.message.content` diretamente no payload da gaveta.
- `app/javascript/dashboard/components-next/message/Message.vue:162-168,425-431` identifica a mensagem pelo marcador e habilita `reportAgent` sem excluir `props.private`.

**Contrato afetado.** O PRD separa CA-CONVERSA-02, “Marcar resposta como errada”, de CA-CONVERSA-03, que define a nota de passagem como **privada** (`docs/agentes-ia-redesign/PRD.md:1134-1138`). O desenho B2 promete que cada linha da gaveta é uma marcação de resposta e serializa seu texto (`docs/agentes-ia-redesign/design/B2.md:551-557`). Assim, uma nota interna pode ser marcada, contada e exibida como se fosse uma resposta enviada ao cliente.

**Efeito.** Um atendente consegue abrir o menu de uma nota privada marcada pelo agente e criar um report; a métrica `wrong_replies` e a gaveta podem então exibir o texto interno. Mesmo que a conversa seja visível ao membro, isso viola a separação de produto entre feedback sobre resposta pública e material privado de operação e deixa reports antigos contaminarem a leitura caso apenas a entrada seja corrigida.

**Correção mínima.** Fechar o contrato nos três pontos independentes:

1. rejeitar no endpoint de criação qualquer mensagem privada (e exigir a forma pública já prevista para uma resposta do agente);
2. filtrar `private: false` na relação de `Analytics#wrong_reply_reports`, para que registros preexistentes não entrem no total nem no payload;
3. desabilitar `reportAgent` no componente quando `props.private` for verdadeiro.

Adicionar specs para: POST de mensagem privada marcada retornando 422; relatório privado preexistente não contado nem serializado; e menu sem a ação em nota privada. Não alterar o contrato de nota privada de passagem.

## Conclusão

O achado acima precisa ser corrigido e validado antes de considerar a implementação B2 pronta para a próxima etapa. Não há aprovação técnica/segurança desta rodada enquanto mensagens privadas puderem atravessar o contrato de BE-28.
