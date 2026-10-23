import { computed, reactive, ref } from 'vue';
import ContactAPI from 'dashboard/api/contacts';
import { reportarSemDados } from 'dashboard/helper/sentryPrivacy';

// #1423 — editar a pessoa do card sem sair da gaveta (RL-05). Grava só o que
// mudou: o servidor junta os atributos extras, e o resto do contato fica como
// está. Campos nativos (nome, e-mail, telefone), cidade e país em
// additional_attributes, endereço e cargo em custom_attributes.
const CAMPOS = [
  'name',
  'email',
  'phoneNumber',
  'jobTitle',
  'city',
  'address',
  'country',
];

// Campo do servidor (`attributes` do 422) -> campo do formulário.
const CAMPO_DO_SERVIDOR = {
  name: 'name',
  email: 'email',
  phone_number: 'phoneNumber',
};

// Os atributos são JSON livre: um atributo personalizado da conta com a chave
// `address` ou `job_title` pode guardar número ou sim/não. O formulário edita
// texto, então tudo entra como texto.
const comoTexto = valor =>
  valor === null || valor === undefined ? '' : String(valor);

const doContato = contato => {
  const extras = contato?.additional_attributes || {};
  const proprios = contato?.custom_attributes || {};
  return {
    name: comoTexto(contato?.name),
    email: comoTexto(contato?.email),
    phoneNumber: comoTexto(contato?.phone_number),
    jobTitle: comoTexto(proprios.job_title),
    city: comoTexto(extras.city),
    address: comoTexto(proprios.address),
    country: comoTexto(extras.country),
  };
};

// O que dizer quando a gravação falha. Erro da API vira o motivo que ela
// devolve (o 422 traz `message` e `attributes`); erro sem resposta é rede;
// qualquer outro é defeito da tela: vai ao Sentry, sem o que a pessoa digitou.
export const motivoDoErro = (erro, texto) => {
  if (erro?.isAxiosError && erro.response) {
    const { status, data } = erro.response;
    // Um proxy na frente pode devolver HTML: só o formato do Rails conta.
    const campos = (Array.isArray(data?.attributes) ? data.attributes : [])
      .map(campo => CAMPO_DO_SERVIDOR[campo])
      .filter(Boolean);
    if (typeof data?.message === 'string' && data.message)
      return {
        texto: texto('SAVE_ERROR_MOTIVO', { motivo: data.message }),
        campos,
      };
    return { texto: texto('SAVE_ERROR_SERVIDOR', { status }), campos };
  }
  if (erro?.isAxiosError)
    return { texto: texto('SAVE_ERROR_REDE'), campos: [] };
  reportarSemDados(erro, { tela: 'crm_card_contato' });
  return { texto: texto('SAVE_ERROR_TELA'), campos: [] };
};

export const payloadDoContato = (form, inicial) => {
  const mudou = pares =>
    Object.fromEntries(
      pares
        .filter(([, campo]) => form[campo].trim() !== inicial[campo].trim())
        .map(([chave, campo]) => [chave, form[campo].trim()])
    );
  const proprios = mudou([
    ['address', 'address'],
    ['job_title', 'jobTitle'],
  ]);
  const extras = mudou([
    ['city', 'city'],
    ['country', 'country'],
  ]);
  return {
    ...mudou([
      ['name', 'name'],
      ['email', 'email'],
      ['phone_number', 'phoneNumber'],
    ]),
    ...(Object.keys(extras).length ? { additional_attributes: extras } : {}),
    ...(Object.keys(proprios).length ? { custom_attributes: proprios } : {}),
  };
};

export const useCardContato = () => {
  const form = reactive(doContato(null));
  const foto = ref(JSON.stringify(doContato(null)));
  const contatoId = ref(null);
  const editando = ref(false);
  const salvando = ref(false);
  const erro = ref('');
  const camposComErro = ref([]);
  const sujo = computed(() =>
    CAMPOS.some(campo => form[campo] !== JSON.parse(foto.value)[campo])
  );
  const carregar = contato => {
    contatoId.value = contato?.id || null;
    Object.assign(form, doContato(contato));
    foto.value = JSON.stringify({ ...form });
  };
  const comecar = contato => {
    carregar(contato);
    editando.value = true;
    erro.value = '';
    camposComErro.value = [];
  };
  const desfazer = () => {
    Object.assign(form, JSON.parse(foto.value));
    editando.value = false;
    erro.value = '';
    camposComErro.value = [];
  };
  // Devolve true quando gravou (ou não havia o que gravar). `texto(chave,
  // valores)` traduz as mensagens de erro (CRM_CARD.PESSOA).
  const salvar = async texto => {
    if (salvando.value || !form.name.trim()) return false;
    salvando.value = true;
    erro.value = '';
    camposComErro.value = [];
    try {
      if (contatoId.value && sujo.value)
        await ContactAPI.update(
          contatoId.value,
          payloadDoContato(form, JSON.parse(foto.value))
        );
      foto.value = JSON.stringify({ ...form });
      editando.value = false;
      return true;
    } catch (falha) {
      const motivo = motivoDoErro(falha, texto);
      erro.value = motivo.texto;
      camposComErro.value = motivo.campos;
      return false;
    } finally {
      salvando.value = false;
    }
  };
  return {
    form,
    editando,
    salvando,
    erro,
    camposComErro,
    sujo,
    carregar,
    comecar,
    desfazer,
    salvar,
  };
};
