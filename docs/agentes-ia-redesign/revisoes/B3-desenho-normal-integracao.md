# B3/BE05 — revisão normal de integração

Alvo: design/B3.md, SHA-256 `38fe7b237b74d73d048f7091d14af29395ae66e2abaa47e1dd5c2e8cdac826ee`. Revisão independente da autoria, pelo root, antes de código. Código atual aberto: Builder#ensure_agent, #adjust_mode?, #build_attributes, Agent#apply_builder_config!, BuildThread#append_user_message_with_agent_lock!, controller e serializer. Não é teste executado, aceite visual ou revisão de código implementado.

Resultado: dois P1 concretos impedem implementar o desenho atual.

## B3-DES-01 — continuar a criação não equivale a ajustar um agente fechado

O GET proposto grava resume em toda thread e o desenho usa esse modo para restringir a saída ao conjunto D22. F1 chama esse mesmo leitor em E1/E2, onde o rascunho já existe, mas ainda não tem instrução e precisa receber nome, voz e apresentação no primeiro fechamento. Builder#ensure_agent já cria “Novo agente” antes de concluir; marcar toda leitura como ajuste impede completar a identidade da criação. O caso RED de “criação sem agente” não cobre o rascunho já vinculado seguido de sair/Continuar.

Há um mecanismo atual que o desenho não aproveitou: Builder#adjust_mode? decide pelo agente já ter instrução. O desenho deve separar continuar a criação inacabada de ajustar um agente fechado, provar E1/E2 com id já vinculado e preservar o primeiro fechamento completo. Evitar três novos modos se o predicado existente e o writer sob lock resolvem os caminhos reais. Não permitir schema completo no ajuste legado como exceção: BE05 diz que voz só é gravada na criação e D22 protege qualquer retomada.

## B3-DES-02 — a recusa manual precisa sobreviver à fila e ao lock do writer

O desenho exige a recusa em fetch_thread antes do append/modelo, mas coloca a filtragem somente em Builder/adjust_mode? antes de apply_builder_config!. Agent#apply_builder_config! trava e relê o agente, recusa instrução mantida e sessão stale, mas não recusa modo manual. Uma pessoa pode mudar para manual depois de enfileirar a geração guiada; a guarda anterior já passou e o job pode sobrescrever a instrução manual.

A decisão D22 e PRD §7.2 exigem guarda no ponto de escrita. Acrescentar ao desenho o check do modo manual dentro do Agent.with_lock, antes de alterar atributos, e uma prova de geração enfileirada → troca manual → conclusão recusada sem sobrescrita. Manter a guarda antes de IA para requests já manuais; são portas/tempos independentes comprovados, não duplicação especulativa.

## Conferências sem achado adicional

- Conta/kept/system_key, manage-only e ausência sem novo código de erro estão coerentes.
- id DESC alinha reader e writer; RED da divergência BE01 já observado no snapshot17.
- Envelope reutilizado mantém instruction/scaffold/config/tokens ocultos; mensagens do dono exigem manage.
- WhatsApp continua central; BE05 não toca canais nem conexão.
- Reset de force_close idempotente precisa conservar a ordem Agent → Thread já adotada pelo B1 ao integrar o reader; não acrescentar append/job/novo token ao GET.
- Demais contratos B3 permanecem explicitamente fora desta subfatia; não há afirmação de B3 completo.

Próximo bloco: autoria corrige estas duas causas no desenho e acrescenta os casos ausentes. Depois uma checagem limitada do resultado; residual exige parar/causa antes de única final, e erro final exige retornar ao Rodrigo. Nada de código BE05 antes de desenho fechado e RED.
