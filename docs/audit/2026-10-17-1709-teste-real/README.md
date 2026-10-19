# #1709: teste real em aparelho (demo M2, 17/10/2026)

Nada de produção. Motor e demo ficam só no M2.

- **Motor:** container `waha-c2y-teste1709`, imagem `autonomia-waha-c2y-rich:2026.9.2-c2y-rich-5`, GOWS, amd64 emulado.
  - Porta `127.0.0.1:3712`.
  - Redis próprio: `waha-c2y-teste1709-redis`, sem porta publicada. O app chatwoot do WAHA usa fila.
  - Rede `waha-teste1709`.
  - Volume `waha-c2y-teste1709-sessions`. É volume do Docker e não fica na pasta da demo: o colima do M2 não monta `/Users/Shared`, e um bind ali criaria uma pasta vazia dentro da VM.
- **Chave descartável:** `/Users/Shared/maccluster-demo-1709-int/teste-real/waha-api-key.env` (600). O Rails da demo recebe a mesma chave e `WAHA_RICH_NATIVE_ENGINES` por `rails-extra.env` (600), lido pelo `reiniciar.sh`.
- **Sessão A** `5511941010656` (empresa): caixa 8 "WAHA Teste Real", Channel::Api 6, na conta 1.
  - O webhook é `http://127.0.0.1:3712/webhooks/chatwoot/5511941010656/<app_id>`, e o `engine_for` cai no motor 3712.
  - O app chatwoot aponta para `http://host.lima.internal:3709`, com `c2yViewOnceNotice: true`.
  - O owner é o user 1 (`account_token_owner_user_id`).
- **Sessão B** `5511926791242` (cliente): sem app chatwoot.
- **Ids:** em `teste-real/ids.json` (600).

## Comandos (no M4)

```sh
# QR de cada sessão (inicia a sessão se estiver parada; renova a cada 20 s até WORKING)
docs/audit/2026-10-17-1709-teste-real/gerar-qr.sh 0656
docs/audit/2026-10-17-1709-teste-real/gerar-qr.sh 1242
# status / número pareado
maccluster exec --node m2 -- /Users/Shared/maccluster-demo-1709-int/teste-real/motor.sh 5511941010656 me
maccluster exec --node m2 -- /Users/Shared/maccluster-demo-1709-int/teste-real/motor.sh 5511926791242 me
```

## Desligar e apagar (no fim do teste)

```sh
M=/Users/Shared/maccluster-demo-1709-int/teste-real/motor.sh
maccluster exec --node m2 -- $M 5511941010656 logout   # desvincula o aparelho extra (a sessão do wa-hub não é tocada)
maccluster exec --node m2 -- $M 5511926791242 logout
maccluster exec --node m2 -- bash -c '. ~/opt/c2y-docker/env.sh; docker rm -f waha-c2y-teste1709 waha-c2y-teste1709-redis; docker volume rm waha-c2y-teste1709-sessions; docker network rm waha-teste1709'
# Rails da demo de volta ao normal: tirar o rails-extra.env e reiniciar
maccluster exec --node m2 -- bash -c 'rm /Users/Shared/maccluster-demo-1709-int/teste-real/rails-extra.env /Users/Shared/maccluster-demo-1709-int/teste-real/waha-api-key.env; bash /Users/Shared/maccluster-demo-1709-int/reiniciar.sh'
```

Confira também no celular, em Aparelhos conectados: "c2y teste 1709" não pode estar mais lá. A caixa 8 e as conversas dela ficam no banco da demo. Elas saem quando a demo for apagada, ou pela tela de caixas, com a demo no ar.
