# Jornada do Instagram Tester — #910

Checklist operacional do fluxo construído no PR #913. A primeira parte é a jornada que uma pessoa deve executar na homologação. A segunda registra somente a evidência local obtida com componentes reais e dados sintéticos; ela não marca a Meta como homologada.

## Jornada humana para homologação controlada

Alvo real indicado por Rodrigo: **@placementseg, conta 18 do chat.hub2you.ai**. A UI publicada ainda mostra o OAuth legado; a jornada tester abaixo permanece não homologada.

Execute com uma conta de teste autorizada e com o nome do app configurado no ambiente de homologação. Marque cada item somente depois de observar o resultado no produto.

1. [ ] Em **Configurações → Caixas de entrada → Adicionar uma caixa**, escolha **Instagram**.
2. [ ] Digite `@usuario` e selecione **Buscar perfil**.
3. [ ] Confira o nome e o `@usuário` retornados; selecione o perfil correto.
4. [ ] Se o perfil estiver **ausente**, envie o convite uma vez. Se estiver **pendente** ou **aceito**, não envie outro convite.
5. [ ] No computador, abra o Instagram Web já autenticado na conta selecionada.
6. [ ] Acesse **Apps e sites → Convites do testador**, localize o nome exato do app mostrado na plataforma e selecione **Aceitar**.
7. [ ] Volte à plataforma (Autonom.ia ou Hub2You) e escolha **Já aceitei — verificar**.
8. [ ] Quando o status estiver aceito, avance em **Continuar com Instagram** e conclua o login/consentimento usando o mesmo perfil selecionado.
9. [ ] Na etapa de agentes, atribua a equipe ou os agentes que devem atender a caixa.
10. [ ] Finalize a configuração, abra a caixa criada e envie uma DM de teste; confirme que a conversa chega e pode ser respondida.
11. [ ] Para uma caixa Instagram existente, execute a reautorização pelo caminho legado e confirme que a conexão continua apontando para o mesmo canal, sem passar pelo seletor de tester.

Se um passo falhar, registre o estado mostrado, a conta de teste e o ambiente sem copiar cookies, senhas, tokens ou HAR. O aceite e o OAuth dependem da conta Meta e não são demonstrados por uma execução local simulada.

## Evidência local segura desta rodada

- [x] Wizard real: escolha de canal → Instagram.
- [x] Tela real inicial: campo vazio e foco por teclado.
- [x] Busca real com API interna sintética: carregando, resultados e resultado vazio.
- [x] Seleção explícita de perfil: ausente, convite pendente, aceito e erro de status.
- [x] Erro de configuração/sessão sem exibir marcador upstream.
- [x] Flag desligada: shell real preserva o CTA OAuth legado e não chama `/testers`.
- [x] Atribuição de agentes no componente real.
- [x] Finalização no componente real do wizard.
- [x] Tela existente de reautorização do Instagram preservada.
- [x] Desktop/mobile, claro/escuro, com Chromium isolado e rede externa bloqueada.

O harness monta componentes reais de produção (`InboxChannels`, `ChannelList`, `ChannelFactory`, `Instagram`, `TesterOnboarding`, `AddAgents`, `FinishSetup` e `Reauthorize`). A execução cobriu 56 casos e gerou 60 capturas: 52 casos com a flag ligada (56 imagens, pois quatro estados de agentes têm uma imagem antes e outra depois da seleção) e quatro casos com a flag desligada (uma imagem por combinação). A [galeria atual](assets/instagram-testers-910/index.html) contém somente essas 60 imagens, com manifesto SHA-256. As quatro capturas anteriores foram preservadas como arquivadas, fora do índice de aprovação.

O harness simula somente as respostas internas da API de configuração, busca, status, convite e autorização. As telas usam os componentes reais do wizard, mas não montam a navegação global/sidebar completa do dashboard. Os nomes e perfis são sintéticos. Não foram lidos cookies, credenciais, HAR ou banco, nem feitas chamadas autenticadas à Meta, OAuth real, produção ou proxy Webshare.

Para reproduzir com dependências e Chromium já existentes:

```sh
PLAYWRIGHT_MODULE_PATH=/caminho/para/playwright \
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/caminho/para/chromium \
node tests/qa/instagram-testers/wizard.mjs
```

O resultado reconstruível fica em `tmp/instagram-910/visual/wizard/results.json`. A execução final desta rodada registrou `status: PASS`, 56/56 casos, 60 capturas e hashes de fonte iguais antes/depois e ao checkout atual. Isso valida contrato e apresentação local; não substitui convite real, callback Meta, sessão administrativa, OAuth ou infraestrutura de saída.

## Pendências reais antes de homologação e deploy

- [ ] Confirmar em ambiente controlado que a busca real retorna o perfil correto e que convite/status refletem a conta Meta esperada.
- [ ] Aceitar o convite na tela oficial do Instagram e concluir o OAuth com o perfil selecionado.
- [ ] Reautorizar uma caixa existente e comprovar que o token/canal são atualizados sem regressão.
- [ ] Validar a renovação automática da sessão administrativa, inclusive cookies; o refresh do token OAuth não renova esses cookies.
- [ ] Validar o proxy Webshare **Static Residential Direct**, a saída fixa, autorização por IP de origem (sem usuário/senha no proxy), falhas e alertas. Conferir `AutoReplace` e `AutoRefresh` no console autorizado: o fluxo não deve rotacionar IPs nem trocar o endpoint silenciosamente.
- [ ] Executar a jornada no ambiente de homologação do produto e registrar rollback antes de qualquer produção.
