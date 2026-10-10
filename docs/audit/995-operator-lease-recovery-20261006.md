# #995 — recuperação da janela administrativa e da autorização temporária

## Incidente observado

O operador chegou à página autenticada de funções do aplicativo Autonom.ia. As tentativas terminaram como `failed` antes do vencimento registrado. Isso não comprova erro de login nem publicação da sessão. Referências: comentários 6025896548 e 6026287674 da issue #995.

A leitura desta retomada, em 06/10/2026 às 23:25 UTC, retornou bootstrap completo, mas sem versão de sessão. O `operator_read` seguinte retornou manager e request ausentes. Os tempos foram 21.947 ms e 19.634 ms. Não foi escrita sessão, heartbeat ou pedido por essas leituras.
O runtime VPS observado continua em `0d28f1a52485ec4d81569bf98930dd9f791ecde8`; os produtores das duas instalações estavam ativos. Nenhum marcador de janela humana estava presente na leitura de 23:23 UTC.

## Defeitos identificados no código

O waiter anterior encerrava o filho quando uma renovação falhava e a consulta posterior não retornava `succeeded`, inclusive quando confirmava o mesmo pedido `running` com autorização ainda válida. O backend pode ter aplicado a renovação antes de a resposta de transporte se perder.
A supervisão também era recriada entre navegador e manager, reiniciando a espera antes da próxima renovação. O prazo local era o teto de uma hora, não o vencimento mais recente confirmado pelo backend.
Esses mecanismos são compatíveis com os incidentes; os logs genéricos antigos não permitem atribuir retrospectivamente cada falha a uma chamada específica.

## Correção

Uma supervisão por pedido acompanha claim, bootstrap, navegador e manager. Resposta incerta exige leitura do mesmo pedido; somente `running` com vencimento confirmado futuro ou `succeeded` real permitem prosseguir. Expiração, revogação e troca de pedido cancelam a atividade. Nenhum timeout acrescenta prazo e nenhuma publicação é repetida para resolver resposta perdida.
A espera entre renovações considera a margem disponível para transporte e reconciliação. O sucesso confirmado encerra a atividade supervisionada sem criar um segundo ciclo de publicação. A drenagem do filho deve terminar antes de retornar ao wrapper.

## Limites operacionais desta rodada

O diagnóstico que abriria o perfil preservado não foi executado: a ferramenta recusou a parada controlada do gestor Autonom.ia pelas configurações de segurança, antes de fornecer execução ou PID. Não foi usado outro caminho para essa mutação. Portanto, a correção local não comprova captura natural, publicação, renovação Meta ou ativação do assistido.
O conector SSH separado também apresentou divergência no seu known_hosts. Sua configuração não foi modificada. A chave apresentada corresponde ao pin já existente no terminal administrativo que respondeu com StrictHostKeyChecking=yes; não foi desativada a verificação de identidade.
Não repetir login, apagar perfil/cookies, escrever estado fictício ou aumentar prazos para obter aceite. O ajuste temporário de CPU e a persistência de boot continuam com seus próprios critérios na #995.

## Validação local

O autor executou 49 testes dos contratos de controle/lease. O coordenador repetiu uma bateria ampliada de 286 testes de waiter, controle, manager, observer, publicador, concorrência, broker Unix e entrypoints: 286 aprovados; zero falhas, cancelamentos ou testes ignorados. ESLint dos três arquivos alterados, sintaxe Node e diff check também passaram.
A primeira execução ampliada falhou por dependência `ws` ausente no novo worktree; após `npm ci` com o lock do runtime, scripts e download de navegador desativados, a mesma bateria passou. O resultado anterior foi preservado, sem atribuir essa falha de preparação ao código de produção.
Os três pareceres independentes iniciais sustentaram os problemas de desenho. O código final recebeu revisão do coordenador e os testes acima; as chamadas para uma nova revisão independente do patch final foram recusadas pela ferramenta e não serão apresentadas como revisão concluída.
Os testes usam transporte/relógio/filhos simulados ou subprocessos locais isolados. Eles não comprovam estabilidade de AWS/Meta ou recuperação da sessão real. A #995 permanece aberta até aplicação autorizada e aceite operacional.
