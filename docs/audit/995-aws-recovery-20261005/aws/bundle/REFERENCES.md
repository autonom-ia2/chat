# Referências e limites da evidência A5/A6

## WebSocket

[RFC 6455, §§5.5, 5.5.1 e 7.4.1](https://www.rfc-editor.org/rfc/rfc6455)
foi relido em 5 de outubro de 2026. Controles têm limite de 125 bytes. O corpo
de Close, quando presente, começa por um inteiro sem sinal de dois bytes em
ordem de rede e pode continuar com uma razão em UTF-8. A interpretação dessa
razão pertence à aplicação. O código 1003 descreve um tipo de dados que o
destinatário não aceita; sozinho não identifica recusa de autenticação ou uma
camada IAM.

A5/A6 mantêm explícita a invalidade do Close de 175 bytes observado. A leitura
diagnóstica limitada não o aceita como frame de protocolo. A6 apenas projeta
termos de vocabulário fechado em ordem; desconhecidos viram `OTHER` e o
truncamento é explícito. Nenhum motivo bruto da A5 foi preservado ou deduzido.

## Fontes primárias do cliente

- [websocket-client, tag v1.7.0](https://github.com/websocket-client/websocket-client/tree/v1.7.0/websocket): `_abnf.py`, `_core.py`, `_handshake.py` e `_socket.py`.
- [AWS session-manager-plugin, tag 1.2.835.0](https://github.com/aws/session-manager-plugin/tree/1.2.835.0): `VERSION`, `src/sessionmanagerplugin/session/session.go`, `sessionhandler.go` e `src/communicator/websocketchannel.go`.

O índice preservado em `source-evidence/SOURCE_INDEX.json` registra repositório,
ref, blob e SHA-256 efetivamente obtidos. O inventário público separado
`auth-runtime-readonly-20261005T205522Z.json` registra os arquivos/binário
observados na VPS. O conteúdo `VERSION` recuperado da tag do plugin divergia
da versão exibida pelo binário instalado; não se afirma equivalência integral
entre esse binário e o código da tag.

O argumento de endpoint SSM reservado foi configurado conforme a fonte lida.
Isso não constitui uma prova nova de que o binário nunca trocou token por
retry/Resume. O controle próprio é descrito pelo que foi observado: par
original passado ao plugin, listener/PID correlacionados, túnel/banner e
cleanup. O diagnóstico não afirma autenticação SSH nem elegibilidade de corte.

## Evidências da tarefa

Os recibos públicos A5 em `live-a5/` são os originais completos, com seus hashes
no manifesto. Os pareceres da projeção A6 e do promotor têm escopos distintos;
nenhum parecer substitui os gates da execução autorizada. Os logs do Mac foram
recuperados de uma leitura anterior bem-sucedida e ficam em `a6/mac-fixture/`,
separados dos logs do cloud. Nada foi coletado novamente do Mac durante a
preparação deste arquivo.
