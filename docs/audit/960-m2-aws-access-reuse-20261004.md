# #960 — reuso dos acessos AWS existentes a partir do M2

Rodrigo pediu resolver sem novo login: STS confirmou os perfis existentes `hub2you`
e `financial` no M4, nas contas esperadas. O login novo criado para o M2 era desnecessário.
Conexão SSH confiável M2→M4 comprovada, sem ForwardAgent e sem copiar credenciais.
O teste `--access-check` executado pelo M2 confirmou novamente ambas as identidades.
Foram consultados os CURRENTs, ALBs, targets healthy, SSM Online e os quatro parâmetros
por conta, sem recuperar seus valores. Essas leituras não comprovam transporte ou Meta.

Substituído o launcher público em `/Users/rodrigovictor/Downloads/finalizar_transporte_instagram_m2.py`
após conferir hash original e ausência de execução concorrente. Agora chama pelo SSH do M2
o runner do M4, usando os perfis existentes. Não cria perfis, faz login ou exporta chaves.
O M4 precisa permanecer ligado e alcançável. Relatório público retorna ao M2 somente após sucesso.

Gauss revisou o executor e corrigiu uma cópia: espera limitada por unit/listeners antes do smoke;
qualquer pending bloqueia novos comandos até reconciliação, sem reenvio automático.
Argos revisou launcher, runner e diff final e aprovou abertura em Terminal humano.
TTY e confirmação `PREPARAR TRANSPORTE` preservados; o coordenador não preencheu a confirmação.
Tentativa pelo terminal não interativo foi recusada antes de operações remotas, conforme o gate.
Terminal nativo do M2 foi aberto com o novo launcher. Não há confirmação de instalação nesta rodada.

Validação: 10 testes isolados do launcher aprovados no ambiente de análise; 15 testes sintéticos
da espera/pendência aprovados por Gauss e repetidos pelo coordenador no M4. Nenhum AWS/Redis real
nesses testes. Provas reais desta rodada foram somente identidade, metadados e a conexão SSH.
Não houve merge, deploy, alteração de Redis, nova publicação de parâmetros ou rotação de segredos.
Fontes e pareceres: `tmp/reuse-auth-20261004/`. Código operacional local ainda sem commit/CI novo.
