# Avaliação independente — estado após preparo operacional #910 / PR #913

03/10/2026. Base do onboarding: `042e473685a3135953af983f35acf337a943fbcb`.
Este registro acompanha também a correção mínima do fixture identificada abaixo.
O último CI completo avaliado é o do commit base; o CI do novo commit é obrigatório.
Este registro distingue código, testes sintéticos, transporte real e operação.
Não declara merge/deploy ou homologação Meta. A jornada de @placementseg na conta
18 do Hub2You foi reservada ao Rodrigo.

## Achados e bloqueios por gravidade

| Gravidade | Referência | Estado e consequência |
|---|---|---|
| P1 operacional | `scripts/instagram_testers/session-observer.mjs:51`; `app/services/instagram/testers/configuration.rb:29` | App pai, Business e nome do App foram identificados na captura fornecida pelo Rodrigo; administrador/doc_id foram fornecidos diretamente por ele. Todos os vínculos foram preparados no overlay v3 e no supervisor inativo. Ainda não há prova de operação/renovação. A janela de inicialização não descobre esses dados. O gestor e o onboarding falham fechados; não há prova de sessão publicada/renovada. |
| P1 operacional | `app/services/instagram/testers/coordination_redis.rb:6` | A URL explícita de coordenação ainda não foi entregue. Os caches atuais das stacks são distintos. Um piloto somente Hub2You pode usar coordenação local configurada; ativação simultânea de App compartilhado exige coordenador comum. |
| Gate CI | `spec/services/whatsapp/incoming_message_service_spec.rb:170` | CI geral: 21/22 checks aprovados. Shard 0/8 falhou nas mesmas 12 expectativas na primeira execução e na única repetição solicitada, ambas com 2.311 exemplos. WhatsApp isolado passou 43/43. As mesmas 12 falhas WhatsApp reapareceram no teste local com a lista CI exata sem client_spec e response_parser_spec Instagram. A reprodução causal `legacy_interleaving` → WhatsApp deu 46 exemplos/12 falhas antes e 46/0 após a limpeza explícita de contatos do fixture. `spec/requests/relationships/legacy_interleaving_spec.rb:17` corrige apenas o cleanup, pois Account usa destroy_async para contatos. Revisão independente aprovou a restrição à conta fictícia. Nenhum gate foi ignorado; o CI do novo commit ainda precisa aprovar. |
| P2 operacional | `scripts/instagram_testers/runtime/com.autonomia.instagram-tester-manager.plist:6` | Runtime e configuração privada do supervisor preparados, porém não carregados. Publicação SSH/SSM, renovação real e entrega de alerta ainda não foram homologadas. Templates ou logs estáticos não provam serviço/alerta em operação. |
| P2 operacional | `.github/workflows/deploy-hub2you-blue-green.yml:281`; `.github/workflows/deploy-autonomia-blue-green.yml:272` | Novo host green pode receber outro IP de origem. A autorização Webshare dos hosts atuais não autoriza automaticamente o green; validar antes de ativar. Auto-Replace por indisponibilidade acima de 15 minutos permanece ligado no fornecedor. |

Os achados P1 anteriores de deadline/processos do transporte, EPIPE, usuário
privilegiado preexistente, ponteiro blue-green e overlay amplo foram corrigidos e
revisados independentemente. O overlay aceita exatamente 13 chaves backend e
rejeita duplicatas, SESSION_JSON, usuário/senha de proxy e configuração do gestor.
Não foi identificado novo bloqueador concreto no código blue-green revisado.

## Critérios atendidos

- Jornada busca → seleção → convite → aceite → Instagram Login implementada no
  código. OAuth/reautorização legados preservados nos testes delimitados; flag OFF
  conserva o CTA legado e não chama a API nova nos cenários de componentes.
- Sessão cifrada/versionada, CAS, identidade/App/Business/proxy vinculados, TTL,
  invalidação e tokens tester vinculados ao namespace implementados e testados
  com fixtures. Refresh OAuth não renova cookies administrativos.
- Quatro checks focais Instagram aprovados no commit avaliado. Node: 47 testes;
  Vitest: 48; Python: 25. Galeria: 56 casos e 60 capturas de componentes reais
  com APIs sintéticas, desktop/mobile e claro/escuro. Capturas não são produção.
- Ruby anterior: 316 exemplos Instagram; regressão delimitada adicional: 330
  exemplos no mesmo processo, zero falhas. Esse resultado não inclui WhatsApp.
  WhatsApp isolado: 43 exemplos, zero falhas, job
  `m4-0d86ec2f958441d88407931f2769cad3`. Comparação do snapshot com o worktree:
  4.449 caminhos Ruby/Rake/Gemfile, zero divergências. Uma execução local sem
  Instagram terminou com 2.003 exemplos e uma falha Enterprise; ela selecionou
  arquivos diferentes do CI e não incluiu o spec WhatsApp afetado. Portanto, não
  prova ausência de contaminação. A lista exata do shard foi extraída do artefato
  CI: 198 arquivos de comando, incluindo `client_spec.rb`, `response_parser_spec.rb`
  e `whatsapp/incoming_message_service_spec.rb`. Comparação correta concluída no
  job `m4-4891bed531b84532aba3d586188ca222`: 2.276 exemplos, 22 falhas, duas
  pendências. Doze falhas WhatsApp persistiram sem os dois specs Instagram; nove
  adicionais derivam de libvips.42 ausente no M4 e uma é Enterprise. Isso não é
  aprovação do CI nem prova de regressão funcional WhatsApp.
- Webshare Static Residential e adicional autorizado de US$ 5/mês confirmados.
  Origens das duas stacks e gestor autorizadas, autorização anterior preservada.
  GET público pelo proxy passou nas três origens e nos dois containers HTTParty;
  isso comprova transporte, sem usar sessão autenticada Meta.
- SecureString overlay v3 e chave pública String v1 preparados, ambos OFF;
  namespaces distintos; Hub2You allowlist 18, Autonom.ia vazia. Dois ARNs de leitura
  adicionados nas roles EC2, demais statements preservados. Leitura real de
  Type/Version pelos hosts passou: comandos SSM
  `f6d28136-2e2c-484f-bb6f-c10b4393e0a3` e
  `ad430131-96be-43f5-aad9-675311b2b640`. Nenhum valor foi exibido.
- Env base, OAuth e chaves de criptografia preservados. Runtime privado Playwright
  1.59.1 e Chrome instalado; diretórios 700, configuração/chave privada 600;
  FileVault ativo. Nenhum perfil pessoal foi copiado ou cookie/senha/HAR inspecionado.

## Plano mínimo e veredito

1. Usar os vínculos Meta fornecidos pelo Rodrigo sem enviar cookies, senhas,
   tokens ou HAR ao chat. Operador conclui login/2FA legítimos no
   perfil dedicado e fecha a janela. Não repetir a chamada anteriormente bloqueada
   usando outra ferramenta, host ou proxy.
2. Entregar coordenação TLS explícita para o piloto Hub2You/18, mantendo Autonom.ia
   OFF. Coordenador comum e isolamento OAuth legado são gates para ativação conjunta:
   IDs OAuth atuais têm fingerprints iguais; relação com o App pai e segredo não
   foram comprovados. Não compartilhar credenciais de caches entre stacks.
3. Fechar o gate CI do commit final sem ignorar checks. Deploy controlado começa OFF;
   confirmar SHA/saúde e autorização do IP green, instalar/inicializar publisher e
   supervisor, comprovar sessão atualizada sem redeploy e alerta, então habilitar
   somente a conta aprovada. Rodrigo executa a jornada real.
4. Rollback de código usa o ponto blue-green anterior de cada stack, imagem
   `0abffb3ee75b4c7102b927f2d36c553a1e0db25c`. Desativação usa flag/allowlist e parada
   do gestor; preserva caixas, conversas, tokens e marcadores de convite incerto.
   Nunca restaurar sessão invalidada como rollback.

**Veredito atual: não pronto para merge/deploy como fluxo operacional concluído.**
Código e transporte avançaram; configuração, sessão e gate geral permanecem
pendentes. Ausência de homologação ou bloqueio de ferramenta não comprova falha
técnica do produto. N8n e funcionalidades SMS permanecem fora do escopo.

## Prova causal e correção do gate CI

A comparação do shard CI sem os dois specs Instagram foi seguida pela reprodução
mínima com ordem definida: `legacy_interleaving_spec.rb` e
`whatsapp/incoming_message_service_spec.rb`, 46 exemplos. Antes: 12 falhas WhatsApp
(`/tmp/instagram-910-legacy-wa-before.log`). Depois da única linha
`account.contacts.destroy_all` no cleanup do fixture: zero falhas
(`/tmp/instagram-910-legacy-wa-after.log`). A conta do fixture usa gravações reais
fora de transação; seu destroy_async não era executado durante os testes.
Revisão de segurança confirmou a limpeza restrita a account_id e o padrão já
existente em widget_interleaving. Não houve alteração funcional WhatsApp ou SMS.

O screenshot fornecido pelo Rodrigo identifica App pai, Business e nome do App.
Esses três vínculos e administrador/doc_id fornecidos diretamente pelo Rodrigo
foram adicionados aos overlays SecureString v3 e ao supervisor
privado preparado, mantendo automação OFF. A ferramenta desta conversa não expõe
o navegador interno do Codex: isso limita a inspeção, sem comprovar falha Meta ou
do produto. Os vínculos estão completos; coordenação e renovação real permanecem gates.

Reprodução mínima: antes, job `m4-a2bfb6423fdc42e29febeedd9a3ecc02`, banco
com um contato órfão (account inexistente). Depois, job
`m4-aed24127afbc472da67f49ad00ea3682`, 46 exemplos/zero falhas. Serviços de teste
encerrados pelo subagente, nenhuma alteração de banco ou código de produção.
