# Continuidade operacional da #995 — candidato de 06/10/2026

Este diretório é uma cópia operacional isolada do executor de produtores, não uma nova release da aplicação.
Os originais em runtime/producers e todos os recibos históricos permanecem preservados.

## Delta revisado

Somente duas constantes de producers.py mudaram: CUTOVER seleciona release/cutover-mac-statewords e o pin correspondente é 4157f1b1844e65b4bbe7282fa44ae3f6f71c00e93f7d48a20ecfe4eaea98b1d9.
SHA256 do wrapper: f4b3cd6ec785e23524ef60081a12a66d5e378d0a1fe1c6fcb4fa2130c7459bf6.
SHA256 de producers-remote.py, byte-idêntico ao original: 3d5dbc3d295ed4e9f179e07b36789c7ca70bf0284776b8199ad037828711524f.
O leitor corrigido apenas reconhece enabled/disabled, além de true/false, na saída real de launchctl.

## B0 preservado

b0_collect.py e b0_check.py não foram alterados. O coletor continua com o transporte histórico fe0 e invoca somente aws/current_gate; não usa mac_status.
A justificativa transitiva permanece em https/b0/v2/cutover-argv-impact-review.md.
O B0 deve ser coletado depois do journal ready real e antes dos produtores, sob https/b0, com seu próprio contexto e hashes.
Nenhuma amostra preparation, observação anterior ou diagnóstico AWS é promovido a B0.

## Validação e gates

14 testes do leitor e 20 testes do consumidor passaram localmente. Os testes são simulados, não homologação Meta.
Argos-cutover e Gauss-consumidores revisaram o fluxo; Sentinela-pins aprovou o delta estático final. Onze pareceres foram preservados em finalize-20261006/reviews.
Antes de um journal sucessor Hub, conferir quiescência dos comandos da v4, Version+Value da pública antiga e drenagem com o rastreamento original da v4. Preservar seus bytes e nunca executar seu rollback para reativar o Mac.
Revalidar CURRENT e a release efetiva após o deploy #1058; obter nova prova própria se o alvo mudar ou a prova vencer. Não editar a fase de um recibo para avançar.

Start e verify são executados separadamente, uma stack por vez, com journal ready e B0 reais. Não repetir uma fase com resultado incerto; reconciliar a intenção e o recibo existentes.
O rollback do candidato é a contenção stop dos produtores da própria stack, preservando sessões, perfis, Redis e resultados. Reversão da chave segue o journal específico e não reativa os Macs automaticamente.
Não habilitar boot nem automação global antes do aceite de login Meta, publicação e renovações naturais. A VPS é o runtime permanente; os Macs são apenas terminais administrativos e legado a desligar uma vez.

## Recibos desta rodada — ainda sem aceite final

Em 06/10 às 15:23 UTC, manager_stopped com o rastreamento original da tentativa Hub v4 confirmou loaded=false, disabled=true, lock ausente e processos rastreados drenados. O journal permaneceu byte-idêntico. Autonomia ainda estava carregada no M4.
Às 15:35 UTC, quatro comandos SSM anteriores foram relidos com instância, plugin, completed e run_token correspondentes; todos conclusivos. A pública antiga permaneceu na versão 1, com valor e versão idênticos ao baseline. A v4 não foi promovida nem reescrita.
A prova própria Hub de transporte passou às 15:24:48 UTC, com limpeza conclusiva às 15:24:56 UTC. Seu escopo é identidade de serviço, canal SSM e banner SSH; não prova autenticação Meta nem isolamento universal. A amostra não pode ser reutilizada depois de mudança de CURRENT ou vencimento.
Uma tentativa de prepare posterior foi recusada por deploy_is_active ao entrar a #1058, antes de troca de chave. Seu journal parcial foi preservado. Os deploys em andamento exigem nova leitura de CURRENT/SHA e prova própria correspondente antes do próximo corte.
O acesso normal à VPS respondeu, e verify-pair retornou instagram_vps_env_pair_ok. Gateways Hub e Autonomia retornaram 401 nas rotas corretas sem sessão. Managers e publishers estavam inativos na leitura de 15:22 UTC; essa leitura não representa estado futuro.

O patch adjacente documenta somente o delta local revisado; não deve ser executado da pasta de auditoria. As fontes completas e os recibos privados permanecem na raiz operacional da #995. Não copiar chaves, perfis, ENV ou tokens para o repositório.
Novos resultados de execução devem ser acrescentados com seus horários reais. Esta documentação não fecha a #995, não liga assistido, não habilita boot e não comprova login ou renovação.
