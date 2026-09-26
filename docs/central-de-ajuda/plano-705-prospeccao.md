# Plano da #705 · Central de Ajuda e Guia da Prospecção (E7)

Épico #676. A Central e o Guia da Prospecção são escritos uma vez só, depois da E8, a partir do que está no ar em `55e91226e4`. O levantamento que sustenta este plano conferiu cada ponto no código, não só nas notas das etapas.

## Decisões do Rodrigo (26/09/2026)

- Os artigos de uso passam de `admin` para `ambos`, porque atendentes com função personalizada usam a Prospecção.
- Entrega em duas partes:
  - textos da Central e do Guia no **lote 4**, junto com a recusa (#713 e #737);
  - vídeos no **lote seguinte**.
- Os defeitos de produto achados no levantamento viram issues à parte (#743 a #747). Não mexem no texto até serem resolvidos.
- Vídeo do 16.05 (desenhar a área): só com chave real do Google Maps, que é paga. Decisão pendente. Sem ela, o artigo sai sem vídeo.

## O que a tela faz de verdade (e as notas diziam diferente)

- **Repetir** chama o Google de novo. O resultado guardado só vale para uma busca nova idêntica, feita pelo **Buscar**.
- Só o **polígono** recorta a área. Círculo, retângulo, raio e área visível vão ao Google só como preferência (#746).
- **Expandir raio automaticamente** vem ligado: uma tentativa com o dobro do raio, teto de 10 km, e só fica se trouxer mais.
- Os estados da pesquisa se chamam **Aguardando capacidade** e **Falha técnica**.
- Não existe **Criar contato** individual, só **Criar contatos** em lote. As Listas não têm botão de exportar.

## Parte 1 · Textos (lote 4)

### Artigos do capítulo 16

| id | Título | Me leve até lá | Situação |
|---|---|---|---|
| 16.01 | Montar e rodar uma busca de leads | busca | reescrever |
| 16.02 | Ler e trabalhar os resultados da busca | busca | reescrever |
| 16.03 | Listas de leads e público de campanha | listas | reescrever |
| 16.04 | Configurações da Prospecção | configurações | reescrever (admin) |
| 16.05 | Desenhar a área da busca no mapa | busca | novo |
| 16.06 | Filtros avançados e jogadas | busca | novo |
| 16.07 | Repetir, editar e excluir uma busca do histórico | busca | novo |
| 16.08 | Pesquisa de empresa e decisor | busca | novo |
| 16.09 | Enviar leads ao CRM e usar um sócio como contato | busca | novo |
| 16.10 | Colocar leads da busca numa campanha | busca | novo |
| 16.11 | Descartar leads, desfazer e criar contatos em lote | busca | novo |
| 16.12 | Exportar os leads em CSV ou Excel | busca | novo |
| 16.13 | Jogadas salvas: editar e excluir | configurações | novo (admin) |
| 16.14 | Quem vê o quê na Prospecção | funções personalizadas | novo (admin) |

O tour guiado vira um parágrafo no 16.01 (**Refazer tour**).

### Guia (`lib/operator_guide/porques.md`)

São 13 blocos:
- reescritos: `buscar_leads`, `listas_de_leads` e `configurar_prospeccao`;
- novos: `desenhar_area_da_busca`, `filtros_e_jogadas_da_busca`, `historico_de_buscas`, `trabalhar_resultados_da_busca`, `pesquisa_empresa_e_decisor`, `enviar_leads_ao_crm`, `leads_na_campanha`, `descartar_e_criar_contatos`, `exportar_leads` e `jogadas_salvas`.

Depois: `pnpm guia:build`.

### Recusa (#713 e #737), quando a Job no Chat mandar os nomes finais das telas

- **16.03 e 16.10:** recusa gravada no contato e conferida antes de cada envio ativo.
- **Painel do contato (capítulo 09):** o selo "Não quer receber mensagens ativas", com data, origem e o botão de marcar e desfazer.
- **Campanhas (capítulo 13):** envio único, API oficial e e-mail com o descadastro; na API, quem recusou aparece como cancelado.
- **Follow-ups automáticos do CRM (capítulo 10):** também respeitam a recusa.
- Até lá, o texto fala só do que existe hoje: descartar, e contato bloqueado.

### Outros ajustes

- `mapa-de-artigos.json` e `cobertura.json`: entradas do 16.01 ao 16.14.
- **01.01:** trocar a evidência do menu da Prospecção.
- **04.06:** citar **Ver buscas de todos**.

### Prova

- `pnpm central:check` e `pnpm guia:check` em dia, e specs da Central verdes.
- Cada evidência conferida abrindo o arquivo e a linha.
- Revisão independente antes do squash no lote 4.

## Parte 2 · Vídeos (lote seguinte)

- **Regravar:** 16.01, 16.02, 16.03 e 16.04. O 16.02 ainda clica em **Criar card**, que não existe mais.
- **Gravar:** 16.06 a 16.13. O 16.05 depende da chave do Maps; o 16.14 é opcional.
- **Regras de toda gravação:** conta de teste local (conta 9), com dados semeados. Nenhuma cena clica em **Buscar**, **Repetir**, **Enriquecer**, **Pesquisar** ou **Verificar novamente**, porque eles chamam Google, BigDataCorp ou IA pagos. A pesquisa fica desligada na conta de gravação, e o tour é marcado como visto no preparo.

## Fora deste plano

- Correção dos defeitos #743 a #747.
- Troca da detecção de "parar" nos follow-ups por decisão do modelo (#742).
