# Kit de demo: tempo limite na conferência remota e o `tar` do envio (#3031, #3032)

Data: 15/11/2026. Issues: #3031 (tempo limite e máquina forçada) e #3032 (`tar: Write error`). Arquivo: `bin/demo`.

Os dois defeitos pararam a mesma demo no mesmo dia. Vão no mesmo PR porque mexem no mesmo arquivo e a demo
precisa dos dois.

## #3031: `up` parado 30 minutos

**Causa.** `rodar_em` chamava `ssh -o BatchMode=yes` sem limite. O ssh para o outro Mac abria a conexão e ficava
preso na negociação. Mesmo com `DEMO_MAQUINA` apontando este Mac, o `up` pergunta ao outro se a demo já existe lá
e se há demo viva, e ficou esperando.

**Medido** (OpenSSH 10.5, contra um servidor local de mentira): `ConnectTimeout=5` derruba em 5 s a conexão em
que o servidor não manda a saudação, direto ou por `ProxyCommand`. Se o servidor manda a saudação e fica mudo
(negociação presa, o caso do dia), o `ConnectTimeout` não age: o ssh ficou preso até o corte de 25 s por fora.

**Decisão.**

- Conferência curta no outro Mac (`registrada_em`, `vivas_em`, `listar_faltas`) passa por `sondar_em`:
  `/usr/bin/timeout -f -k 5 15 ssh ...`. Estourou, sai com 124 (medido) e a máquina conta como "não respondeu".
- O `-f` é obrigatório. Sem ele o `timeout` cria um grupo de processos; chamado de um script num terminal, o ssh
  sai do primeiro plano e para (SIGTTIN) ao ler do terminal, e máquina saudável viraria "não respondeu". Está no
  manual do `timeout` do macOS. Não reproduzi (o ensaio não tem terminal); a entrada do `registrada_em` também
  passou a vir de `/dev/null`.
- Chamada longa (`pnpm install`, banco, `rsync`, subida do painel) não cabe em 15 s e não ganhou teto: matar o ssh
  no meio deixaria o comando rodando do outro lado. Antes de cada chamada longa a outro Mac, `rodar_em` abre uma
  conexão de teste com o limite curto (`responde`); se ela não responder, avisa e a chamada não parte. Os dois
  `rsync` fazem o mesmo. Custo: uma conexão a mais por chamada.
- Depois de conectado, `ServerAliveInterval=15` e `ServerAliveCountMax=4` derrubam a conexão que parar de
  responder em cerca de 1 minuto. `ServerAlive` não cobre a negociação: quem cobre é a conexão de teste.
- Com `DEMO_MAQUINA`, conferência que falha ou estoura no **outro** Mac vira aviso, e o comando segue
  (`dispensar_muda`). O aviso diz o que ficou sem conferir. A máquina dispensada não é chamada de novo no mesmo
  comando: uma espera de 15 s, não três.
- Não vale para a própria máquina forçada (o `up` para) nem para este Mac (aqui não há rede: falha é defeito).
  Arquivo do kit ausente neste Mac para o comando antes de qualquer conferência, para não passar por silêncio do
  outro Mac.
- Sem `DEMO_MAQUINA` o `up` continua recusando, agora em 15 s, e a mensagem ensina a forçar.
- `maccluster status --json` ganhou 30 s de limite. Não li o código do MacCluster; o limite é por precaução.

**O que se perde e o que fica descoberto.**

- Com o outro Mac mudo e a máquina forçada, o kit não confere a regra de 1 demo viva do lado mudo. O aviso diz
  isso; a Orquestração Deploy, que dá o OK de cada `up`, aceitou ficar com essa conferência (15/11/2026).
- O outro Mac travar no instante entre a conexão de teste e a chamada longa: sem limite, como antes.
- Os outros comandos (`sync`, `seed`, `down` etc.) já seguiam quando uma máquina não responde e a demo está na
  outra (`achar_maquina`). Isso não mudou; só ficou rápido.
- Falha de ssh que não é silêncio (chave de host trocada, autenticação) também conta como "falhou ou passou do
  limite". A mensagem do ssh aparece no terminal.

**Fora deste PR.** Trocar o ssh por `maccluster exec --node`: não medi se ele passa stdin, código de saída e aspas
como o kit precisa. Aspa simples em caminho dentro do comando remoto (`extrair_em` e os outros `'...'`): o slug é
validado e os caminhos são fixos; segue como estava.

## #3032: `tar: Write error` no envio do kit

**Causa.** `tar -cf - . | tar -xf -`: o `tar` que extrai sai ao achar o fim do pacote, sem ler o enchimento do
último bloco. O que envia leva `EPIPE`, sai com erro e, com `pipefail`, o kit falha com tudo já extraído. Só
apareceu com a demo no próprio Mac (#2965); a explicação provável é que por ssh quem lê a entrada é o `sshd`, que
lê tudo. Essa parte não foi medida.

**Decisão.** Quem extrai lê o resto da entrada: `tar -xf - && cat > /dev/null`. Vale para os quatro canos do
`bin/demo`: envio do kit, `sync`, `seed` (os três por `extrair_em`) e `prints` (extração neste Mac).

## Validação (sem demo)

Ensaio em pasta temporária, com `maccluster` de mentira no `PATH` e limite de 2 ou 3 s. O `ssh` de mentira fica
preso (dorme), recusa ou roda o comando aqui. Em três cenários o ssh é o de verdade, contra um servidor local que
manda a saudação e fica mudo: o caso real da negociação presa.

| Cenário | Resultado |
|---|---|
| `main`, sem `DEMO_MAQUINA`, outro Mac preso | fica preso; cortado por fora em 8 s |
| branch, sem `DEMO_MAQUINA`, outro Mac preso | para em 2 s, com a mensagem que ensina a forçar |
| branch, `DEMO_MAQUINA=m4`, `m2` preso | 2 avisos, segue, escolhe `m4`; uma espera só |
| branch, `DEMO_MAQUINA=m2`, `m2` preso | para em 2 s: "a máquina que você forçou não respondeu" |
| branch, `DEMO_MAQUINA=m4`, `m2` recusando a conexão | avisa e segue |
| branch, outro Mac respondendo | caminho normal, sem aviso |
| `maquinas` com `DEMO_MAQUINA=m4` e `m2` preso | lista o `m2` como não conferido; "nenhuma nas máquinas que responderam" |
| outro comando (`achar_maquina`), outro Mac preso, demo não achada | para em 2 s: "não consegui falar com: m2" |
| chamada longa com o outro Mac preso | a conexão de teste barra em 2 s; o comando não roda |
| envio do kit ao outro Mac (ssh de mentira roda aqui) | 10 arquivos de 10: a conexão de teste não consome o `tar` |
| `LIMITE_S=1` no ambiente de quem chama | chamada longa de 3 s termina: a variável de fora não vira limite |
| ssh de verdade preso na negociação, sem `DEMO_MAQUINA`, limite 3 s | para em 3 s |
| ssh de verdade preso na negociação, `DEMO_MAQUINA=m4` | avisa e segue, 4 s |
| ssh de verdade preso na negociação, chamada longa | barrada em 3 s |
| `tar` fora do kit, sem dreno, 5 rodadas | 5 falhas (`tar: Write error`, saídas `1 0`) |
| `tar` fora do kit, com dreno, 5 rodadas | 5 passam (`0 0`) |
| `enviar_kit` neste Mac, `main` | "tar: Write error", "não levei o kit ao m4" |
| `enviar_kit` neste Mac, branch | passa; 10 arquivos de 10 |
| cano dos `prints` (extração local), 5 rodadas | 5 passam |
| `bash -n bin/demo`, `shellcheck -x bin/demo` | sem erro, sem aviso |

`/usr/bin/timeout` é usado no Mac que chama o kit. Existe no M4 (usado no ensaio) e no M2 (conferido por `ls`).
Se faltar, o kit para logo no início.

## Revisão independente

Agente revisor, só leitura, sobre a primeira versão. Achados aplicados: `timeout` sem `-f` (alto); chamada longa
abrindo conexão nova sem proteção (alto: virou a conexão de teste); falha local passando por máquina muda (médio);
`maccluster status` sem limite (médio); textos que prometiam mais do que o código (médio); variável `LIMITE_S`
herdada do ambiente e mensagem errada quando a falha é neste Mac (baixos). Não aplicados, com o motivo acima:
tolerância do `achar_maquina`, aspa simples em caminho, distinguir 124 de 255, teto fixo nas chamadas longas.

## Não verificado

- Nenhuma demo subiu com esta mudança, e nenhuma conexão ssh entre os dois Macs foi feita no ensaio.
- O `timeout -f` chamado de um terminal de verdade.
- `ServerAlive` em chamada longa.
- `sync`, `seed` e `prints` de verdade com a demo no próprio Mac: só o cano do `tar` foi ensaiado.
- Os testes do repositório rodam só na CI do PR.
