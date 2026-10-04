# #960 — parâmetros publicados e pré-condições dos transportes

## Publicação humana confirmada — 04/10/2026

Rodrigo executou pessoalmente `publish-coordination-parameters.py --apply` no M4.
A saída informou oito `created`: quatro para `hub2you` e quatro para `financial`.
O utilitário confere nome, tipo e valor no readback antes de imprimir cada criação.
Nesta rodada, o coordenador não repetiu o publisher nem leu os valores secretos.

Inventário AWS entre 17:14 e 17:15 UTC confirmou os oito parâmetros, versão 1,
com `ssh-key`/`redis-env` SecureString e `ca`/`known-hosts` String.
STS correspondeu às duas contas previstas. Listener, target group e ponteiro CURRENT
corresponderam à mesma instância em cada stack; targets healthy e SSM Online.

## Pré-condições nos hosts — sem alteração de configuração

Diagnóstico por SSM confirmou web/worker ativos e arquivos base regulares root.
Ferramentas necessárias presentes, Python compatível, gateway Docker IPv4 privado;
portas 16380/16381 livres. Diretório `/opt/chatwoot/igcoord` e unit auxiliar ausentes.
Nenhum Redis, ambiente de aplicação, chave, serviço ou configuração foi alterado.
Recibos sanitizados: `tmp/post-parameters-20261004/parameter-and-current-inventory.json`
e `host-preconditions-results.json`. Isso não comprova consumo/descriptografia pelos hosts.

Gauss revisou o transporte; Argos confirmou escopo auxiliar sem reiniciar aplicação;
Nexo revisou a reconciliação Git pendente. Todos concluíram suas revisões locais.
A preparação automática do payload de instalação foi bloqueada pela ferramenta;
os dois arquivos `*-install_aux.py` não foram criados. Não houve tentativa alternativa.
Próxima etapa: instalação pessoal do transporte em uma stack por vez, seguida de prova
TLS/epoch/proxy sem Rails, escritas Redis ou Meta. Merge/deploy continuam não executados.
