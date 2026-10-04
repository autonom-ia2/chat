# #960 — fechamento da composição e prova de transporte

## Transporte executado, não apenas preparado

O executor humano terminou às 20:44 UTC de 04/10/2026 com transporte aprovado nas duas stacks: TLS/autenticação Redis, leitura do epoch e HTTPS Webshare com egress esperado. Ambos os recibos registram aplicação preservada, nenhuma escrita Redis e nenhuma chamada Meta. Estado local sem comandos pendentes. A confirmação AWS somente leitura das 21:36 UTC verificou os mesmos recibos Success/exit 0; Hub ainda era CURRENT, mas Autonom.ia já tinha outro CURRENT. Não atribuir o teste da instância anterior à nova. O futuro deploy precisa instalar/testar o auxiliar na sua própria green antes do corte.

## Integração de código e testes

A revisão Nexo/Argos cobriu a composição do HEAD `f5b64ed75f` com a main representada por `3eedd520b4`. Preservados CI agregado/fila, fuso automático, cabeçalho do Guia, boot paralelo, renovação de credenciais, drenagem e rollback em falha/cancelamento. A proteção final aceita apenas respostas SSM conhecidas ao decidir aposentar green; status desconhecido não autoriza terminar a instância. O target group já pode ter sido retirado: não confundir proteção da instância com rollback de todas as etapas.

Bateria completa: **35 testes offline, zero falhas, zero skips**, 642,558 s. Todos os comandos de infraestrutura eram fakes. Inclui 27 testes anteriores e 8 novos; limiar do executor dos cenários passou de 15 para 30 s, continuando a encerrar o grupo e propagar timeout, sem relaxar os limites funcionais de polling/drenagem.

O scheduler recusou execução local no M4 com pressão térmica Heavy. Foi usado snapshot nativo verificado nos dois Macs e job no M2, sem desativar a proteção térmica. Job: `m2-7a24d5fc6b4c49dda5e9cd168625cbdc`, estado `succeeded`, returncode 0, uma tentativa, nenhum processo ainda ativo. Snapshot e arquivos de trabalho tinham os mesmos hashes de código testado/revisado:

- Hub workflow: `7bd284d8267d6717e66aac9dca0f486cd906bb4ee6957dd538a4d3e4efd8c7a1`.
- Aut workflow: `0efeb3dbcb80f08ac0b214bf49e27181c6fda7676a019a600076d92b5477d57a`.
- Suíte: `4b5721fd186ea7b44e1f24064082d7106440ff64d173f1fe7b99d9bc6d1d52ec`.

## Preparação para ativação

Íris confirmou que duas configurações/perfis dedicados independentes no M4 atendem às duas stacks sem novo multiplexador ou mudança de protocolo. Preservar perfil Hub; não copiar cookies para o perfil Aut. Labels, logs e destino de publisher são separados. Gestor e waiter usam a mesma configuração de cada stack. Essa configuração ainda precisa ser materializada e ativada após o deploy autorizado; perfil novo pode exigir login humano.

A ordem documental foi corrigida: candidato/review/CI → aprovação e deploy → cinco metadados em cada banco → bootstrap → gestor/renovação → homologação por stack. Não há exigência de salvar dados numa tela ainda não publicada. A main posterior `f1cd8f3e38` contém #979 (Autonom.ia t3.medium); preservar essa alteração na composição final antes de pedir aprovação.

Recibos e pareceres: `tmp/resume-release-2125-20261004/`. Resultado anterior do transporte: `tmp/reuse-auth-20261004/relatorios-transporte/resultado.json`. CI deve validar o SHA publicado final; nenhuma aprovação é herdada de outro commit. Nenhum merge na main, deploy, alteração Redis, nova autenticação ou convite executado nesta revisão. Exclusão real entre stacks, sessão, OAuth/webhook e mensagens seguem como gates de ativação, não como testes já aprovados.
