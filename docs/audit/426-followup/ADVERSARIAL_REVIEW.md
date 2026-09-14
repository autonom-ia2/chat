# Revisão adversarial — PR #427

Base: `5742de5fc`. Código revisado: `f2d19443a1d945983d4e86eb8f8df019e1fdab57` (código funcional igual a `fcc23a1de`). Revisão estática e reproduções locais com dados sintéticos; nenhum acesso à produção ou chamada paga de IA.

## Parecer: requer ajustes antes de seguir

A revisão independente foi recebida e confrontada com o código e reproduções locais. Confirmados os achados abaixo; não há aprovação para merge/deploy.

## Achados do agente independente, reproduzidos pelo principal

### P1 — Negócio encerrado durante a avaliação ainda gera lembrete

- `auto_followup_runner.rb:81-93,170-177`: os motivos de cancelamento são verificados apenas antes da composição. Depois da IA, apenas o horário é reavaliado, usando objetos já carregados.
- Reprodução Rails com banco local exclusivo: iniciar em modo lembrete; durante a resposta simulada do composer, atualizar o mesmo card por outra instância para `won`; retornar a composição positiva anterior. Esperado `stopped`; real `reminded`.
- Impacto comprovado: lembrete emitido para negócio já ganho. Respostas/opt-out durante a chamada passam pela mesma ausência de revalidação, mas não foram reproduzidos separadamente nesta rodada. O caminho de envio compartilha a fragilidade; não houve envio real.
- Classificação: fragilidade preexistente no envio, propagada para o novo caminho de lembrete desta PR. Não foi alegada ocorrência em produção.
- Correção: reler os dados relevantes e revalidar motivos de cancelamento imediatamente antes do efeito; considerar concorrência com os fluxos de cancelamento, não apenas repetir a verificação sobre o objeto antigo.

### P2 — Alteração dos dias durante a avaliação é ignorada

- `auto_followup_runner.rb:89,120-122,614-616`: a verificação posterior à IA reutiliza `@config` e a associação de funil já carregada.
- Reprodução Rails: execução numa segunda-feira; durante o composer, salvar no banco `allowed_days:[2]` (somente terça) usando outra instância; devolver avaliação positiva. Esperado `rescheduled`; real `reminded` na segunda-feira.
- Impacto comprovado: a ação usa agenda que acabou de ser substituída. Mudanças de modo e desligamento também precisam ser contempladas na solução, embora não tenham sido reproduzidas separadamente aqui.
- Correção: reler configurações e resolver novamente permissão de execução/ação após a IA; se o modo mudou, descartar a composição incompatível e reavaliar em segurança.

## Achados reproduzidos pelo agente principal

### P2 — Não é possível desligar o follow-up com agenda inválida ou legado sem restrição de horário

- `CrmAiSettingsPanel.vue:74-95` exige agenda válida mesmo quando `autoFollowup.enabled` está desmarcado. Os campos ficam ocultos ao desligar, mas Salvar IA fica desabilitado e Salvar funil recebe `false`.
- `SettingsUpdater:43-45,57-70` também valida antes de considerar `enabled:false`; um PATCH de desligamento recebe `ActiveRecord::RecordInvalid`.
- Cenário reproduzido: funil sintético com `enabled:true`, `quiet_hours:{start:8,end:8}`. O executor anterior e o atual tratam start >= end como ausência de restrição horária. Ao desmarcar o recurso, a UI bloqueia salvar e a configuração persistida continua ligada.
- Impacto: desativação não funciona com essa agenda, e editar outro campo do funil também pode ser bloqueado. Não foi afirmada a existência dessa configuração em produção.
- Correção recomendada: permitir desligar independentemente dos campos de agenda ocultos; validar estritamente ao habilitar/configurar, preservando a possibilidade de desativação no backend.

### P2 — Horários fracionários são aceitos na UI e truncados no servidor (preexistente)

- `CrmAiSettingsPanel.vue:79-81` não exige horas inteiras; a ação de salvar não executa a validação nativa do input.
- `SettingsUpdater:66,76-77` valida/converte com `to_i`.
- Reproduzido: tela envia `{start:8.5,end:20.5}` e serviço real retorna `{start:8,end:20}`. A configuração real diverge do que o usuário digitou; o início pode ser antecipado em 30 minutos.
- Classificação: comportamento preexistente, ainda presente na área alterada. Não é atribuído como regressão introduzida por esta PR.
- Correção recomendada: rejeitar valores fracionários nos dois lados se a unidade continuar sendo hora inteira; não truncar silenciosamente.

## i18n e QA

As 32 chaves novas/alteradas de frontend têm correspondentes pt_BR e interpolação equivalente. Os dois modos, dias, orientações e histórico estão traduzidos; título do lembrete usa idioma da conta e data do popup usa idioma da interface. QA visual anterior cobriu desktop e 390 px com componente real e API sintética; não é E2E autenticado na AWS. Os novos cenários adversariais acima não estavam cobertos pelos testes aprovados.

Evidências: `review-evidence/results.json` e `review-evidence/settings-reproduction.rb.txt`. Para o segundo arquivo, executar via `bundle exec ruby` na raiz desta worktree; usa os serviços reais e modelo sintético em memória, sem banco.

## Avaliação crítica do parecer recebido

O agente também levantou possível duplicação após falha parcial e ausência de regras adicionais de ownership no prompt. Essas hipóteses NÃO foram publicadas como bugs confirmados: o dispatch real ocorre dentro da transação de `follow_up.with_lock`, que invalida o argumento simples de persistência parcial; o prompt de lembrete já contém instruções de identificação do responsável. Sem reprodução adicional, seria incorreto tratá-las como achados determinísticos.

## Evidência adicional

`review-evidence/runner-results.txt`: dois testes adversariais locais, ambos falhando contra o comportamento esperado, comprovando os dois primeiros achados. `runner-reproduction.txt` contém os exemplos para inclusão temporária no contexto existente `with AI team reminders` de `auto_followup_runner_spec.rb`. Composer simulado, banco e Redis exclusivos, sem mensagens reais ou chamadas pagas. O CI verde anterior não incluía esses exemplos. As falhas são descobertas de revisão, não regressões em testes já existentes.

Nenhuma correção de produto foi feita nesta rodada; apenas relatório e evidências. i18n está corrigido conforme validação anterior. QA autenticado no drawer completo e avaliação com modelo real continuam fora da evidência disponível.

