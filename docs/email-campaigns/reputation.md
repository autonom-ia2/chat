# Reputação e admissão de campanhas — #765

A proteção global do SES determina a admissão de novos envios. Taxas, volume e gerações de feedback locais servem para diagnóstico e alertas, sem bloquear a conta. Supressão de destinatários continua independente e obrigatória.

## Diagnóstico local

`Metrics` mantém a coorte de sete dias de aceites SES confirmados (`sent_at`), separada de DirectInbox, outro tenant, claims ambíguos e envios futuros. A classificação de bounces e reclamações não mudou: prevenção do provedor não vira reclamação nova; hard bounce, spam e descadastro continuam registrados e suprimidos pelo registro individual.

`Evaluator` coleta fora dos locks. Publica apenas observações cuja geração e versão de feedback continuam atuais; se uma observação foi superada, solicita nova avaliação sem impedir envios. O nível antigo `paused` vira diagnóstico `high_risk`. Percentuais locais não são apresentados como taxa oficial AWS.

Snapshots, auditorias append-only, flags `email_campaigns_paused`, `blocked` e exceções antigas permanecem intactos para histórico/rollback. Não são autoridade de admissão nem têm orçamento consumido. O endpoint de exceção local foi retirado do produto: mesmo SuperAdmin recebe negativa, sem criar nova exceção.

## Proteção global

`ProviderMonitor` consulta SES GetAccount e as métricas globais CloudWatch `AWS/SES`, sem dimensão de tenant/domínio, `Reputation.BounceRate` e `Reputation.ComplaintRate`. Usa GetMetricData para buscar o ponto oficial válido mais recente em até 62 dias e não soma taxas. A consulta atual do SES/CloudWatch precisa estar recente (`checked_at`, no máximo 900 segundos); a publicação esparsa de uma taxa não bloqueia sozinha a conta. `observed_at` preserva a data real da taxa. Resposta incompleta, ausência de taxa ou erro de leitura permanece desconhecido; não inventa zero. A documentação AWS distingue essas métricas oficiais da contagem local: [monitoramento](https://docs.aws.amazon.com/ses/latest/dg/monitor-sending-activity.html) e [alarmes de reputação](https://docs.aws.amazon.com/ses/latest/dg/reputationdashboard-cloudwatch-alarm.html).

Bloqueia novos claims se SES desabilita envio, entra em PROBATION/SHUTDOWN ou atinge os limites preventivos globais: bounces ≥5% ou reclamações ≥0,1%. Limites menores permanecem configuráveis; não se aumenta o teto. Uma resposta nociva atrasada ainda adiciona proteção e invalida qualquer recuperação em curso, sem substituir telemetria mais recente.

Recuperação automática exige envio habilitado, status HEALTHY, ambas as taxas abaixo de 80% dos limiares de pausa e duas consultas atuais bem-sucedidas cobrindo pelo menos 300 segundos. A taxa publicada pode permanecer a mesma entre as consultas. Falha, dados ausentes ou evidência nociva zeram a janela de recuperação. Pausa manual por configuração ou operador continua manual. A liberação gera auditoria `provider_recovered`.

O gate não faz chamadas externas. Usa o estado persistido sob a mesma ordem de locks da reserva final. Uma chamada já autorizada pode terminar; nenhum novo destinatário é reservado após a pausa. Supressão, recusa de contato, higiene e importação ativa são verificadas antes da reserva. DirectInbox não passa pelo gate SES, mantendo seus controles individuais.

A recuperação libera a admissão global. Campanhas já pausadas continuam exigindo **Retomar**, evitando iniciar automaticamente um envio que o usuário decidiu interromper. Histórico local antigo também não causa retomada automática.

## Ativação e rollback

Rodrigo autorizou merge/deploy e o ajuste das duas AWS em 30/09/2026. A preparação usa o papel EC2 da aplicação, com `ses:GetAccount` e `cloudwatch:GetMetricData`, preservando as operações SES necessárias. Hub2You usa us-east-1; Autonom.ia usa sa-east-1. As duas chaves estáticas inválidas específicas de campanhas da Autonom.ia foram retiradas do parâmetro SecureString; a versão anterior permanece no histórico criptografado. As demais configurações foram preservadas. Antes de implantar a troca de política:

1. Confirmar a conta/região SES correta, acesso somente de leitura a GetAccount/CloudWatch e agendamento do monitor existente.
2. Habilitar `EMAIL_REPUTATION_PROVIDER_MONITOR=true`, configurar `EMAIL_REPUTATION_AWS_ACCOUNT_ID` e manter `EMAIL_REPUTATION_PROVIDER_UNKNOWN_ACTION=block`. Confirmar observação global fresca. Sem isso, não há sinal verde para substituir a proteção local em produção.
3. Revisar campanhas que permanecem pausadas. Não limpar flags/histórico e não disparar mensagens para provar o gate.
4. Implantar web e workers com a mesma versão, verificando importações, status e erros. A migração TypeSafe é aditiva e deve preceder o código novo.
5. Em falha, retornar web/workers à imagem anterior; manter tabelas/colunas aditivas e os históricos. Não apagar credenciais nem reverter esquema enquanto houver jobs da versão nova. Manter o gate global ativo; acionar bloqueio manual global se necessário e autorizado.

A ativação do TypeSafe exige configuração separada com criptografia funcional, chave no cofre e teste de conexão autorizado. Nenhum endereço real, envio de campanha ou chamada paga foi usado na validação local desta entrega.
