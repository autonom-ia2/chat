import { addDays, format, fromUnixTime } from 'date-fns';
import { FILTER_OPS } from 'dashboard/components-next/filter/operators';
import { CONVERSATION_ATTRIBUTES } from 'dashboard/components-next/filter/helper/filterHelper';

export const CONVERSATION_CREATED_METRIC = 'conversations_count';
const DATE_FORMAT = 'yyyy-MM-dd';

const DIMENSION_ATTRIBUTES = {
  inbox: CONVERSATION_ATTRIBUTES.INBOX_ID,
  agent: CONVERSATION_ATTRIBUTES.ASSIGNEE_ID,
  team: CONVERSATION_ATTRIBUTES.TEAM_ID,
};

// #3151: o filtro "Criada em" conta o dia no fuso da conta; o dia do intervalo
// sai no mesmo fuso. Sem fuso, o do navegador.
const dayIn = (timestamp, timezone) => {
  const date = fromUnixTime(timestamp);
  if (!timezone) return format(date, DATE_FORMAT);

  return new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
};
const shiftDay = (day, days) =>
  format(addDays(new Date(`${day}T12:00:00`), days), DATE_FORMAT);

// The Created-at filter compares dates strictly, so bound by the surrounding days.
const dayBefore = (timestamp, timezone) =>
  shiftDay(dayIn(timestamp, timezone), -1);
const dayAfter = (timestamp, timezone) =>
  shiftDay(dayIn(timestamp - 1, timezone), 1);

const condition = (attributeKey, filterOperator, values) => ({
  attribute_key: attributeKey,
  filter_operator: filterOperator,
  values,
  query_operator: 'and',
});

export const canLinkDrilldownToConversations = ({ metric, groupBy }) =>
  metric === CONVERSATION_CREATED_METRIC && groupBy !== 'hour';

export const buildDrilldownConversationFilters = ({
  bucket,
  type,
  id,
  labelTitle,
  timezone,
}) => {
  const filters = [
    condition(
      CONVERSATION_ATTRIBUTES.CREATED_AT,
      FILTER_OPS.IS_GREATER_THAN,
      dayBefore(bucket.since, timezone)
    ),
    condition(
      CONVERSATION_ATTRIBUTES.CREATED_AT,
      FILTER_OPS.IS_LESS_THAN,
      dayAfter(bucket.until, timezone)
    ),
  ];

  if (type === 'label') {
    filters.push(
      condition(CONVERSATION_ATTRIBUTES.LABELS, FILTER_OPS.EQUAL_TO, [
        { id: labelTitle },
      ])
    );
  } else if (DIMENSION_ATTRIBUTES[type]) {
    filters.push(
      condition(DIMENSION_ATTRIBUTES[type], FILTER_OPS.EQUAL_TO, { id })
    );
  }

  return filters;
};
