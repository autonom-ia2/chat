import { computed, reactive, ref } from 'vue';
import ContactAPI from 'dashboard/api/contacts';

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

const doContato = contato => {
  const extras = contato?.additional_attributes || {};
  const proprios = contato?.custom_attributes || {};
  return {
    name: contato?.name || '',
    email: contato?.email || '',
    phoneNumber: contato?.phone_number || '',
    jobTitle: proprios.job_title || '',
    city: extras.city || '',
    address: proprios.address || '',
    country: extras.country || '',
  };
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
  };
  const desfazer = () => {
    Object.assign(form, JSON.parse(foto.value));
    editando.value = false;
    erro.value = '';
  };
  // Devolve true quando gravou (ou não havia o que gravar).
  const salvar = async mensagemDeErro => {
    if (salvando.value || !form.name.trim()) return false;
    salvando.value = true;
    erro.value = '';
    try {
      if (contatoId.value && sujo.value)
        await ContactAPI.update(
          contatoId.value,
          payloadDoContato(form, JSON.parse(foto.value))
        );
      foto.value = JSON.stringify({ ...form });
      editando.value = false;
      return true;
    } catch {
      erro.value = mensagemDeErro;
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
    sujo,
    carregar,
    comecar,
    desfazer,
    salvar,
  };
};
