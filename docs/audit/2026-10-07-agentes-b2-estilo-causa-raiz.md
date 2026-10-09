# B2 — causa e recibo do refino estrutural de estilo

**Data:** 2026-10-07  
**Escopo autorizado:** somente `Crm::Ai::InteractiveJob`, `Autonomia::Agents::TestDigest`,
`Autonomia::Agents::TestResultRecorder`, o módulo `TestDigestComponents`, o callsite de
`public_payload` e specs diretamente afetadas. Nenhum contrato ou comportamento pode mudar.

## Evidência anterior às alterações

O lint Ruby 23 foi executado no snapshot oficial pelo job
`m2-fe6f0614241d4f99b172d448e5caab0a`. O relatório é
`/tmp/chat2you-agentes-lint23.json`, SHA-256
`f49efd6a375c67e27917650318a1db8b0481db9152779979d60a7960ac5e7898`.

As 23 ofensas reais sob esta ownership foram:

- `app/jobs/crm/ai/interactive_job.rb`: `perform` ABC 29.85/26, complexidade ciclomática 9/7 e tamanho 22/19;
- `app/services/autonomia/agents/test_digest.rb`: classe 188/175;
- `app/services/autonomia/agents/test_result_recorder.rb`: `public_payload` ABC 26.02/26, tamanho 21/19 e 6 parâmetros/5.

## Causa

Os serviços novos concentraram no método de entrada responsabilidades de domínio que já têm fronteiras naturais:

- o job misturava leitura/claim, autorização, contexto corrente, execução, stale e finalização;
- o digest mantinha no objeto principal a normalização/canonicalização de materiais, ferramentas e configuração operacional, embora já existisse o módulo de componentes;
- o recorder recebia três digests paralelos e montava, lia e resolvia o payload público no mesmo método.

A correção é estrutural: extrair essas responsabilidades para métodos/módulo de domínio e agrupar os três digests atuais em `current_digests`. Não haverá supressão de cop, alteração de limite, nova coerção ou mudança de guarda.

## Plano mínimo

1. decompor o fluxo do `InteractiveJob` em leitura/claim, autorização/contexto, execução, stale e finalização;
2. mover serialização canônica e normalização de dados do digest para `TestDigestComponents`;
3. agrupar somente os digests já existentes na assinatura de `public_payload`, ajustando o controller e specs;
4. preservar exatamente os payloads, os estados, os guards, a ordem de chamadas e os argumentos persistidos;
5. fazer apenas checagens estáticas de diff/estrutura ao final; o lint e os testes serão executados pelo coordenador em snapshot posterior.

Nenhum teste, build, banco, serviço, rede, produção, commit ou push será executado neste bloco.

## Causa registrada antes do refino final

O lint24 residual informado pelo coordenador contém 11 ofensas. Esta etapa trata somente duas
ocorrências de nomenclatura/fixture sob a ownership B2: o helper de `InteractiveJob` que aplica o
contexto corrente tem nome de mutação genérico (`set_current_context`) e a spec do Playground guarda
o identificador de sessão em variável de instância (`@started_session_id`). Ambos dificultam a leitura
do fluxo e não são necessários para o contrato. O refino autorizado será renomear o helper para
`apply_request_context` e encapsular o valor da sessão em `server_session_context`, preservando
exatamente as atribuições e leituras. As outras nove ofensas permanecem fora desta ownership e não
serão declaradas resolvidas aqui.
