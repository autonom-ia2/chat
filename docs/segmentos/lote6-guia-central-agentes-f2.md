# F2 corretora · Lote 6: Guia, Central de Ajuda e agentes

autonom-ia2/chat#1802, 19/10/2026. Vem depois dos lotes 1 (#1843), 2 (#1853), 3 (#1860), 4 e 5, que mexem no mesmo arquivo do pacote. O formato (opção "a": cada camada guarda só a diferença do texto geral) foi aprovado pelo Rodrigo em 19/10.

Até aqui o painel falava a língua da conta, mas o Guia e a Central de Ajuda ainda diziam "Ganhou" e "Marcar como ganho". Este lote leva o vocabulário dos pacotes ao Guia, à Central e ao comportamento dos agentes. A conta geral não muda: mesmo arquivo, mesma versão e mesmo artigo, byte a byte.

## O que entra

### Guia da Plataforma por pacote

- Cada camada tem `lib/operator_guide/pacotes/<camada>/porques.md`, com os fluxos do `porques.md` geral, pelo mesmo cabeçalho, e só os campos de texto que mudam: `titulo`, `intent`, `onde_fica`, `perfil` e `pre_requisitos` (desde o lote 4 do #2083), `passos` e `gotchas`. Rota, gate, `nav_target` e `cobre` vêm sempre do geral; o build recusa fluxo desconhecido e campo proibido.
- O `pnpm guia:build` gera `lib/operator_guide/pacotes/<camada>/guia-produto.md` compondo as camadas (geral ← seguros ← tipo). O `pnpm guia:check` reprova arquivo de pacote fora de dia e arquivo gerado sem `porques.md`.
- Hoje: `seguros` (11 fluxos), `seguros/corretora` (10) e `seguros/saude_beneficios` (8).
- O Seed escolhe a base pela conta (`Autonomia::Guide::Seed.kb_path_for`, `Autonomia::Guide::BaseDoPacote`): a camada mais específica que tiver arquivo. Sem arquivo, ou com o interruptor desligado, fica a base geral. O `kb_version` é o da base escolhida, então a conta geral não é re-semeada e a conta de pacote é re-semeada uma vez quando o interruptor liga ou o texto do pacote muda.
- O aquecimento do Guia no deploy (`WarmUpJob`) usa `Seed.versao_da_instalacao`, que só soma os arquivos de pacote com o interruptor ligado.
- O modo aprendiz (`guia-aprendiz.yml`) também adiciona `lib/operator_guide/pacotes` no PR que abre.

### Instrução do Guia por pacote (6.B)

- Três camadas têm `lib/operator_guide/pacotes/<camada>/guia-instrucao.md`, escrito à mão: `seguros` (seguradora e insurtech), `seguros/corretora` e `seguros/saude_beneficios`. Cada uma é uma seção "Vocabulário desta conta", curta, que diz ao Guia como chamar as coisas na resposta ao operador.
- A conta recebe a instrução geral + `"\n\n"` + o arquivo da camada mais específica que existir (`Seed.instrucao_para`, `BaseDoPacote.instrucao_com`, mesmo critério da base). Não somam: a corretora lê só a dela, que não herda o "nunca diga corretora" da camada `seguros`.
- Conta geral, ou interruptor desligado: instrução e `kb_version` iguais aos de antes, byte a byte (o `seed_spec` confere). A conta com camada é re-semeada uma vez quando o interruptor liga ou o arquivo muda; `versao_da_instalacao` soma também esses arquivos.
- O `guia:build` e o `guia:check` não leem nem geram `guia-instrucao.md`.
- O painel liga a sugestão `AUTONOMIA_GUIDE.SUGGESTIONS.REPORTS`: "Quantos seguros fechei este mês?" na camada `seguros` (vale para corretora, seguradora e insurtech) e "Quantos planos fechei este mês?" na saúde.
- Eval pago: `spec/services/autonomia/guide/vocabulario_eval_spec.rb`; relatório em `docs/audit/2026-10-21-1802-eval-guia-vocabulario/`.

### Central de Ajuda por pacote

- Cada camada tem `lib/central_de_ajuda_pacotes/<camada>/<capítulo>/<id>-<slug>.md`, com o cabeçalho (`id` e, se mudar, `titulo`) e só as seções `## ` que trocam. As outras vêm do artigo geral.
- A troca é feita na leitura, pela conta (`Autonomia::CentralDeAjuda::Leitura`, `VarianteDoPacote`, `ArtigoDoPacote`). Nada é gravado no portal: o endereço público `/hc/plataforma`, a versão do Publicador e as contas sem pacote ficam como antes.
- A variante fica sem vídeo: o vídeo do artigo geral mostra os botões do texto geral.
- Variante com defeito de formato (seção que não existe no geral, `id` diferente, cabeçalho inválido) não derruba a Central: a conta lê o artigo geral e o erro vai ao log. O spec da variante monta todas as variantes do repositório e barra o defeito antes do deploy.
- Hoje: `seguros` (11 artigos), `seguros/corretora` (17) e `seguros/saude_beneficios` (10).

### Agentes: bloco de segmento por tipo

- `Autonomia::Segmentos::Bloco.for_segmento(segmento)` devolve o texto de `config/agentes_por_pacote/seguros/<tipo>/agentes.md` (corretora, seguradora, insurtech, saúde e benefícios). O texto é só orientação e vocabulário do ramo, sem frase pronta, e fala de passar para a equipe o que não souber.
- Só vale com o interruptor ligado e com a Fase 2 dos agentes. Não entra no Guia nem na Lia (Cotação).
- O bloco chega ao agente pela marca gravada nele (`config['base'] = {segmento, versao, texto}`, autonom-ia2/chat#2014, que entra antes deste lote), não pela conta a cada mensagem. O prompt usa o texto gravado no agente: uma edição em `agentes.md` só chega a um agente que já existe pelo botão (decisão do Rodrigo, 20/10: "Só pelo botão"). `Bloco.segmento(account)` é a camada; `Bloco.for_segmento` devolve o texto e `Bloco.versao` os 12 primeiros caracteres do SHA-256 dele. Agente novo nasce com a marca. Só recebe bloco o agente com texto gravado: quem nasceu antes deste lote tem texto nil e fica sem bloco, como o agente que já existia (contas 1, 16 e 18) e não tem marca, até o botão "Atualizar com a nova base", que sai na F3. Trocar o tipo da conta no super admin não muda agente nenhum. Cada `agentes.md` cabe em `Bloco::TEXTO_DA_BASE_MAX` (8 KB; o spec do bloco confere).
- Na stack hub2you, em 21/10 (leitura da Agentes IA): a conta 18 é corretora e a 43 é saúde e benefícios; as contas 1 e 16 estão sem segmento e não recebem pacote nem bloco até alguém marcar o tipo no super admin (a 16 é insurtech).
- Fica fora de `config/pacotes`, porque lá cada camada só aceita `en.yml` e `pt_BR.yml` (`i18n:fork:check`).
- Eval pago (com OK do Rodrigo): com o bloco, 36 de 36; sem o bloco, 32 de 36. Custo US$ 0,46. Relatório em `docs/audit/2026-10-19-1802-eval-segmento/`.

### Textos do painel (pacote da corretora)

- **Ferramentas do agente:** o exemplo é "Consulta de apólice" (`api.suacorretora.com.br/apolices/busca`), com o quando de apólice e parcela e o termo "placa do carro ou CPF". A lista vazia e a ajuda do nome falam de apólice, não de estoque. O exemplo saiu do código para o i18n (`RASCUNHO_EXEMPLO`), e a conta geral continua com "Busca no estoque".
- **Central:** dica da busca, família "Vender seguros e medir" e assuntos "CRM: vendas e renovações" e "Seu plano e faturas".
- **Memória do Guia:** "Sobre a corretora" e exemplos de corretora.

## Regras do texto

- Os rótulos do Guia e da Central são exatamente os do painel da camada: "Fechou o seguro", "Marcar: fechou o seguro", "Não fechou", "Seguro ativo", "Nova cotação", "Novo card", "Qual seguro", "Cards que terminaram", "Viraram card no CRM". Na saúde: "Fechou o plano", "Planos fechados", "Plano ativo".
- A camada `seguros` vale para seguradora, insurtech e saúde: nada de "corretora" nem "corretor" nela.
- "corretor", nunca vendedor nem produtor; "cliente" só para quem já comprou.

## O que ficou de fora, e por quê

- **Instrução do Guia por pacote (6.B):** saiu em PR próprio, com eval pago (ver "Instrução do Guia por pacote (6.B)" acima).
- **Central em inglês por pacote:** a Central em inglês é etapa própria do épico.
- **Vídeo próprio da corretora:** a variante fica sem vídeo até haver gravação com os botões da corretora.
- **Texto geral neutro (lote 0):** à parte.
- **Não se mexe:** a Lia (Cotação), o portal público e os artigos que não mudam de vocabulário.

## Manutenção

A camada troca o campo inteiro (Guia) ou a seção inteira (Central). Uma mudança no texto geral de um fluxo ou seção que a camada sobrepõe não chega às contas de seguros: repita a mudança na camada e rode `pnpm guia:build`, `pnpm guia:check` e `pnpm central:check`.

## Validação

- Specs do Guia, da Central, dos segmentos e dos requests da conta: sem falha.
- `guia:check`, `central:check` e `i18n:fork:check` em dia.
- Painel do M2: corretora contra conta geral (21/21 e reteste 10/10) e saúde e seguradora com perfil temporário na conta de teste (7/7, conta restaurada).
- Revisão: revisor do código, Agentes IA, Agendamento, Campanhas e Multifunnel.
