// #3078 — o que a ficha nova da empresa lê e grava no servidor, além da leitura
// da ficha (fonte/fichaFonte.js), pelos endpoints de empresas que o painel já
// tem (Enterprise). Tudo devolve o formato que a tela mostra:
//  - as notas das pessoas da empresa (GET companies/:id/notes, as 20 mais
//    novas, como a aba Notas da ficha antiga), com de quem é cada uma;
//  - as mídias trocadas nas conversas das pessoas (GET companies/:id/media,
//    chave relationships_company_media), as mais novas e o total;
//  - salvar (fonte/gravarEmpresa.js) e apagar a empresa. #3079 — o servidor
//    apaga na hora a empresa pequena (200) e põe na fila a que tem mais pessoas
//    que um lote do Companies::DeleteJob (202). Apagar devolve { naFila }: a
//    tela avisa que a empresa da fila sai da lista em alguns minutos;
//  - procurar quem pôr na empresa (GET companies/:id/contacts/search, só quem
//    ainda não está nela, com a empresa de hoje), pôr (POST) e tirar (DELETE).
// `noServidor`, `comNome` e `lerEmpresa` vêm da fichaFonte: a recusa ganha o
// mesmo nome lá e aqui.
import CompanyAPI from 'dashboard/api/companies';
import { GRAVOU_EM_PARTE } from './gravarPessoa';
import { alterarEmpresa } from './gravarEmpresa';

export const MIDIAS_NA_FICHA = 5;
const ACEITO = 202;
const MS_POR_SEGUNDO = 1000;

const TIPO_DA_MIDIA = { image: 'imagem', audio: 'audio', video: 'video' };

const notaDaEmpresa = nota => ({
  id: nota.id,
  autor: nota.user?.name ?? null,
  quando: nota.created_at,
  texto: nota.content,
  pessoa: nota.contact
    ? { id: nota.contact.id, nome: nota.contact.name }
    : null,
});

const emSegundos = data => Math.floor(Date.parse(data) / MS_POR_SEGUNDO);

const midiaDaEmpresa = midia => ({
  id: midia.id,
  nome: midia.filename,
  tipo: TIPO_DA_MIDIA[midia.file_type] ?? 'documento',
  quando: emSegundos(midia.created_at),
  pessoa: midia.contact?.name ?? '',
});

const pessoaParaPor = contato => ({
  id: contato.id,
  name: contato.name,
  email: contato.email,
  phone_number: contato.phone_number,
  thumbnail: contato.thumbnail,
  empresa: contato.company
    ? { id: contato.company.id, nome: contato.company.name }
    : null,
});

export const empresaNoServidor = ({ noServidor, comNome, lerEmpresa }) => ({
  async notasDaEmpresa(id) {
    const { payload } = await noServidor(() => CompanyAPI.listNotes(id));
    return payload.map(notaDaEmpresa);
  },
  async midiasDaEmpresa(id) {
    const { payload, meta } = await noServidor(() =>
      CompanyAPI.listMedia(id, { per_page: MIDIAS_NA_FICHA, page: 1 })
    );
    return { itens: payload.map(midiaDaEmpresa), total: meta.total };
  },
  // Se a empresa ficou gravada e só a foto (ou um campo que sai) falhou, a
  // falha sobe com a empresa relida em `retomada.empresaNaFicha`.
  async salvarEmpresa(id, pedido) {
    try {
      await alterarEmpresa(id, pedido);
    } catch (falha) {
      if (falha?.name !== GRAVOU_EM_PARTE) throw comNome(falha);
      const empresaNaFicha = await lerEmpresa(id).catch(() => null);
      throw Object.assign(falha, {
        retomada: { ...falha.retomada, empresaNaFicha },
      });
    }
    return lerEmpresa(id);
  },
  async apagarEmpresa(id) {
    try {
      const resposta = await CompanyAPI.delete(id);
      return { naFila: resposta?.status === ACEITO };
    } catch (falha) {
      throw comNome(falha);
    }
  },
  async buscarPessoasParaEmpresa(id, termo) {
    const { payload } = await noServidor(() =>
      CompanyAPI.searchContacts(id, termo)
    );
    return payload.map(pessoaParaPor);
  },
  async porPessoaNaEmpresa(id, pessoaId) {
    await noServidor(() =>
      CompanyAPI.createContact(id, { contact_id: pessoaId })
    );
  },
  async tirarPessoaDaEmpresa(id, pessoaId) {
    await noServidor(() => CompanyAPI.removeContact(id, pessoaId));
  },
});
