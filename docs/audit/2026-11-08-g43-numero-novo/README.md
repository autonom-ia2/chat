# G43 (#2700): a mensagem vai ao número novo do contato

Painel local (`bin/demo`, demo `g43-numero`), conta 1, main `c0b0f99d2b` + G43.

O seed (`seed.rb`, só para a demo) cria uma caixa de SMS, o contato Bruno Lima com a conversa no número antigo, e uma
automação com o passo "mensagem" no gatilho da conversa resolvida. O telefone do Bruno muda antes de a automação rodar,
e o passo roda pelo código real.

- `historico.png` / `historico-390.png`: em "O que aconteceu", o passo diz "Mandou ao número novo do contato, em outra
  conversa da mesma caixa". O "Ver a mensagem" abre a conversa do número novo, onde a mensagem está.

Jornada: `jornadas.json` (`bin/demo prints <slug> docs/audit/2026-11-08-g43-numero-novo/jornadas.json`).
