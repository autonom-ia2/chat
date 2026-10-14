# Agendamento: link curto `/a/<nome>` e prévia do link no WhatsApp (#1282)

## Contexto

O link da página era `…/book/<uuid>` (62 caracteres) e a página não entregava prévia: o WhatsApp mostrava só o domínio. Decisão do Rodrigo (11/10/2026): link curto próprio, sem encurtador de terceiros, e prévia bonita.

## Decisões

- **Nome curto por página, único na instalação.** Coluna `short_name` em `crm_agent_booking_profiles` com índice único. O modelo grava em minúsculas, e o formato é conferido caractere a caractere (`Crm::BookingV2::ShortName`), sem expressão regular. Migration `20261016100000`, aditiva, com índice concorrente.
- **A casca resolve o nome; a API pública não muda.** `/a/<nome>` troca o nome pelo slug opaco e o entrega à página em `<meta name="booking-slug">`. A API pública v2 continua recebendo só o slug, com as mesmas regras e limites.
- **Pessoa no link: apelido gravado.** `/a/<nome>/<pessoa>` usa o primeiro nome sem acento, com número quando repete na página, gravado em `metadata` do link individual. O identificador que o link já tinha é um UUID de 36 caracteres, e o id interno da pessoa exporia um número da base. O apelido não muda quando a pessoa troca de nome.
- **Prévia só com dado da página.** `Crm::BookingV2::LinkPreview` monta título, descrição e imagem a partir da página. No link do cliente (`/b/<código>`) a prévia é a da página dona do convite: nome, telefone e e-mail do cliente não entram.
- **Prévia neutra** (nome da instalação, sem descrição, imagem fixa) quando a página não pode ser marcada: inexistente, antiga, pausada, conta sem a flag, responsável que saiu.
- **Imagem desenhada com libvips, sem gem nova.** `ruby-vips` já vinha com `image_processing`, e a imagem de produção já instala `vips`. Formas saem de máscaras calculadas (o carregador de SVG fica bloqueado em produção por `VIPS_BLOCK_UNTRUSTED`). O texto usa a fonte Inter (licença OFL), que vai no repositório em `lib/assets/fonts/inter`, porque a imagem Alpine não traz fonte.
- **Imagem guardada e versionada.** Fica anexada à página ou ao link da pessoa (ActiveStorage). A versão é a impressão digital do que aparece no desenho e vai no endereço (`/book/<slug>/preview/<versão>.png`): cache de um ano, e a marca nova gera endereço novo. Versão que não é a atual só redireciona.
- **Nunca 500 na imagem.** Sem página, com libvips ausente ou com erro no desenho, responde `public/booking-preview.png`.

## Riscos aceitos, para o Rodrigo decidir se quer mudar

- **Página pausada responde pelo nome curto.** Como em `/book/<uuid>`, quem abre o link de uma página pausada vê o aviso de pausa. A diferença é que o nome curto é adivinhável: dá para descobrir que um nome tem página pausada e ler o título dela. A alternativa é tratar pausada como inexistente no link curto, e o cliente com o link antigo vê "não encontrada".
- **"Este nome está livre?" fala da instalação inteira.** Quem gerencia páginas em qualquer conta consegue saber se um nome já tem dono. É inerente a nome global; os tetos por IP (30/min) e por conta (120/min) limitam a varredura.
- **Minúsculas garantidas pelo modelo, não pelo banco.** Gravação por SQL cru poderia pôr maiúscula. Um `CHECK` no banco seria uma segunda mudança de esquema; não foi incluído.

## Validação local

- RSpec focado (rotas `/a`, prévia, imagem, nome curto, API do painel, limites, policies, modelos): ver o relatório da entrega.
- Vitest de `settings/booking`, `public_booking_v2` e do cliente da API.
- RuboCop, ESLint, Prettier e o gate de proteção: sem bloqueio.
- `autonomia:guia:formatos:check`, `guide-map/check`, `check-fork-i18n` e `central-de-ajuda/conferir`: em dia.
- As imagens dos três desenhos foram geradas e olhadas, nas seis cores da página e com título longo.
- A libvips não existe na máquina de desenvolvimento: os exemplos que desenham rodaram com uma libvips 8.16 compilada só para a validação. No CI (`libvips42`) e em produção (`vips` do Alpine) ela já existe.
- Não foi conferido em navegador nem no WhatsApp real: o campo do assistente e a prévia no aparelho ficam para a conferência depois do deploy.

## Revisão independente

Revisor `caveman:cavecrew-reviewer`. Corrigidos: slug do endereço-base de página "um link por pessoa" indo para a casca; link antigo de página que voltou a ter um responsável só; versão inventada no endereço da imagem gerando leitura do arquivo; imagem neutra podendo ficar em cache no endereço de página com imagem própria; falha de desenho repetida a cada pedido; trava solta por quem não era dono; dois anexos em corrida; índice inválido pulado na migration; erro de unicidade rotulado sem conferir o índice; teto de pixels da imagem de origem; conferência de nome sem teto por conta.
