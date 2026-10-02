# #792 — Parte 8: oportunidade pela ficha do contato

Oito screenshots da aplicação **compilada** em ambiente local, com APIs Rails/PostgreSQL reais e dados sintéticos. Não são imagens geradas, mockups nem prova de publicação na AWS. O servidor de hot reload foi desligado; o painel carregou o bundle registrado em `compiled-assets.json`.

| Captura | Estado |
|---|---|
| [01-ficha-contato-nova-oportunidade.png](01-ficha-contato-nova-oportunidade.png) | Ação Nova oportunidade junto das ações nativas da ficha. |
| [02-contato-selecionado-no-crm.png](02-contato-selecionado-no-crm.png) | CRM aberto com contato/empresa confirmados, título comercial vazio e Voltar ao contato. |
| [03-retorno-protegido-ao-contato.png](03-retorno-protegido-ao-contato.png) | Confirmação antes de descartar dados comerciais e retornar à ficha. |
| [04-oportunidade-criada-com-mesmo-contato.png](04-oportunidade-criada-com-mesmo-contato.png) | Oportunidade realmente gravada com o mesmo contato, sem duplicação de pessoa/empresa. |
| [05-contato-indisponivel-sem-cadastro-silencioso.png](05-contato-indisponivel-sem-cadastro-silencioso.png) | Contato propositalmente inexistente: erro, nova tentativa e cancelamento, sem criação silenciosa. |
| [06-ficha-contato-celular.png](06-ficha-contato-celular.png) | Ação contextual responsiva na ficha do contato. |
| [07-oportunidade-contextual-celular.png](07-oportunidade-contextual-celular.png) | Formulário contextual no celular, com ação de criação fixa no rodapé. |
| [08-oportunidade-contextual-notebook.png](08-oportunidade-contextual-notebook.png) | Notebook com lateral de 640px, igual a Editar funil. |

A nova ação abre outra aba e informa isso por ícone, título e descrição acessível. A ficha original, incluindo preenchimentos não salvos, permanece intacta; o CRM lê o cadastro confirmado no servidor. O usuário pode escolher outro contato ou continuar sem vínculo deliberadamente, pelos controles já existentes.

## Evidências e limites

`manifest.json`: 14 checks da parte 8, oito capturas, hashes das fontes/PNGs, viewports, respostas de erro esperadas e console. `compiled-assets.json`: identificação e SHA-256 do bundle realmente carregado. `persistence.json`: exatamente uma oportunidade nova e nenhuma alteração de pessoa/empresa, com comparação integral de timestamps em UTC/seis casas. As contagens de contatos, empresas, mensagens e conversas ficaram iguais.

`previous-flow.json`: 14 checks de regressão do cadastro composto da parte 7 no mesmo código compilado, com conferência separada no banco; a perda deliberada da resposta depois de uma gravação é registrada. `backend-summary.json`: 482 exemplos, zero falhas e quatro suspensos históricos separados dos 478 aprovados.

O teste de perfil somente leitura usa autenticação e API reais: a ação não aparece e uma criação enviada diretamente é recusada. URLs inválidas não geram oportunidade avulsa automaticamente. O Chrome foi testado em desktop 1620×1000, notebook 1366×768 e celular 390×844. A lateral mede 640px nos dois primeiros e ocupa os 390px disponíveis no celular.

O console conserva os 404 dos limites Enterprise do ambiente local, o contato inexistente e erros esperados de validação/autorização. As capturas finais não contêm erro de framework e os roteiros finais não registraram exceção JavaScript não tratada. Os logs detalham as tentativas anteriores e a correção da importação circular do botão Voltar; esses resultados não foram apagados para apresentar um histórico artificialmente limpo.

Scripts/logs temporários em `.codex/792/part8-*`; credenciais e snapshots detalhados não são publicados. [Auditoria completa e comandos](../../../audit/2026-09-30-792-crm-relationships-part-8.md).

Aguardar aprovação visual de Rodrigo antes do próximo incremento. Sem merge/deploy.
