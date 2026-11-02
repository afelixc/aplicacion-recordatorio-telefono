/**
 * Recordame en la barra de Gmail.
 *
 * Lee la lista que el teléfono guarda en Drive (Recordame-gmail.json) y
 * anota lo que hacés acá (crear, cambiar, tildar, borrar) en
 * Recordame-gmail-cambios.json. El teléfono levanta esos cambios al abrir
 * Recordame, o solo cada 15 minutos más o menos.
 *
 * Cada archivo tiene un solo escritor: la lista la escribe el teléfono y los
 * cambios los escribe este complemento.
 */

var LOGO =
  'https://raw.githubusercontent.com/afelixc/aplicacion-recordatorio-telefono/main/gmail-addon/logo.png';
var MAIN_FORMAT = 'recordame-gmail';
var CHANGES_FORMAT = 'recordame-gmail-cambios';
var TABS = [
  ['vencidos', 'Vencidos'],
  ['hoy', 'Hoy'],
  ['proximos', 'Próximos'],
  ['hechos', 'Hechos'],
];
var REPEATS = [
  ['none', 'No se repite'],
  ['daily', 'Todos los días'],
  ['weekly', 'Todas las semanas (ese día)'],
  ['monthly', 'Todos los meses (ese día)'],
  ['yearly', 'Todos los años (esa fecha)'],
];
var DAYS = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
var RED = '#B3261E';

// ---------------------------------------------------------------------------
// Pantallas
// ---------------------------------------------------------------------------

/** Al tocar la campanita de Recordame en la barra de la derecha. */
function onHome(e) {
  return homeCard_('hoy', '');
}

function homeCard_(tab, query) {
  var state;
  try {
    state = load_();
  } catch (err) {
    return messageCard_(
      'No pude leer los archivos de Drive',
      'Probá de nuevo en un ratito. Detalle: ' + err,
    );
  }
  if (!state) {
    return messageCard_(
      'Todavía no encuentro tus recordatorios',
      'En el teléfono: Configuración → Gmail en la compu → "Elegir dónde se ' +
        'guarda en Drive". Tienen que ser del Drive de esta cuenta, o de una ' +
        'carpeta compartida con esta cuenta como "Editor". Después tocá ⟳.',
    );
  }

  var now = nowLocal_();
  var groups = group_(state.items, now);
  var card = CardService.newCardBuilder().setHeader(
    CardService.newCardHeader()
      .setTitle('Recordame')
      .setSubtitle(
        'Actualizado del teléfono: ' + whenText_(state.updated, now),
      )
      .setImageUrl(LOGO)
      .setImageStyle(CardService.ImageStyle.CIRCLE),
  );

  var top = CardService.newCardSection();
  top.addWidget(
    CardService.newTextInput()
      .setFieldName('q')
      .setTitle('Buscar')
      .setValue(query || '')
      .setOnChangeAction(action_('onSearch', { tab: tab })),
  );
  var tabs = CardService.newButtonSet();
  TABS.forEach(function (t) {
    var b = CardService.newTextButton()
      .setText(t[1] + ' (' + filter_(groups[t[0]], query).length + ')')
      .setOnClickAction(action_('onTab', { tab: t[0], q: query || '' }));
    if (t[0] === tab) b.setTextButtonStyle(CardService.TextButtonStyle.FILLED);
    tabs.addButton(b);
  });
  top.addWidget(tabs);
  card.addSection(top);

  var list = filter_(groups[tab] || [], query);
  var section = CardService.newCardSection();
  if (!list.length) {
    section.addWidget(
      CardService.newTextParagraph().setText(
        query ? 'No hay ninguno con "' + escape_(query) + '".' : emptyText_(tab),
      ),
    );
  }
  list.slice(0, 80).forEach(function (it) {
    section.addWidget(itemWidget_(it, tab, query, now));
  });
  if (list.length > 80) {
    section.addWidget(
      CardService.newTextParagraph().setText(
        'Y ' + (list.length - 80) + ' más. Usá el buscador.',
      ),
    );
  }
  card.addSection(section);

  card.setFixedFooter(
    CardService.newFixedFooter()
      .setPrimaryButton(
        CardService.newTextButton()
          .setText('+ Nuevo')
          .setOnClickAction(action_('onNew', { tab: tab, q: query || '' })),
      )
      .setSecondaryButton(
        CardService.newTextButton()
          .setText('⟳ Actualizar')
          .setOnClickAction(action_('onTab', { tab: tab, q: query || '' })),
      ),
  );
  return card.build();
}

function itemWidget_(it, tab, query, now) {
  var late = !it.hecho && tab === 'vencidos';
  var when = it.hecho
    ? 'Hecho ' + (it.hechoEl ? whenText_(it.hechoEl, now) : '')
    : whenText_(it.proxima, now);
  var bottom = [];
  if (it.repite) bottom.push('🔁 ' + it.repite);
  if (it.enCamino) bottom.push('⏳ en camino al teléfono');
  var w = CardService.newDecoratedText()
    .setTopLabel(when)
    .setText(
      late
        ? '<font color="' + RED + '">' + escape_(it.titulo) + '</font>'
        : it.hecho
          ? '<font color="#5D6578">' + escape_(it.titulo) + '</font>'
          : escape_(it.titulo),
    )
    .setWrapText(true)
    .setSwitchControl(
      CardService.newSwitch()
        .setControlType(CardService.SwitchControlType.CHECK_BOX)
        .setFieldName('hecho_' + it.key)
        .setValue('1')
        .setSelected(!!it.hecho)
        .setOnChangeAction(
          action_('onToggle', {
            rec: it.key,
            hecho: it.hecho ? '1' : '',
            tab: tab,
            q: query || '',
          }),
        ),
    )
    .setOnClickAction(action_('onEdit', { rec: it.key, tab: tab, q: query || '' }));
  if (bottom.length) w.setBottomLabel(bottom.join(' · '));
  return w;
}

/** Formulario para crear (sin [it]) o cambiar uno. */
function formCard_(it, tab, query) {
  var now = nowLocal_();
  var fecha = it ? it.fecha : now.slice(0, 10);
  var hora = it ? it.hora : nextHour_(now);
  var ymd = fecha.split('-').map(Number);
  var hm = hora.split(':').map(Number);

  var section = CardService.newCardSection()
    .addWidget(
      CardService.newTextInput()
        .setFieldName('titulo')
        .setTitle('Qué hay que recordar')
        .setMultiline(true)
        .setValue(it ? it.titulo : ''),
    )
    .addWidget(
      CardService.newDatePicker()
        .setFieldName('fecha')
        .setTitle('Fecha')
        .setValueInMsSinceEpoch(Date.UTC(ymd[0], ymd[1] - 1, ymd[2])),
    )
    .addWidget(
      CardService.newTimePicker()
        .setFieldName('hora')
        .setTitle('Hora')
        .setHours(hm[0])
        .setMinutes(hm[1] || 0),
    );

  var repeat = CardService.newSelectionInput()
    .setType(CardService.SelectionInputType.DROPDOWN)
    .setFieldName('repetir')
    .setTitle('Repetir');
  var current = it ? it.repetir || 'none' : 'none';
  var keepAsIs =
    it &&
    (current === 'dates' ||
      (current === 'weekly' && /,| y /.test(it.repite || '')));
  if (keepAsIs) repeat.addItem('Como está: ' + it.repite, 'igual', true);
  REPEATS.forEach(function (r) {
    repeat.addItem(r[1], r[0], !keepAsIs && r[0] === current);
  });
  section.addWidget(repeat);

  var params = { rec: it ? it.key : '', tab: tab, q: query || '' };
  var card = CardService.newCardBuilder()
    .setHeader(
      CardService.newCardHeader()
        .setTitle(it ? 'Cambiar recordatorio' : 'Nuevo recordatorio')
        .setImageUrl(LOGO)
        .setImageStyle(CardService.ImageStyle.CIRCLE),
    )
    .addSection(section);

  if (it) {
    var more = CardService.newCardSection();
    if (it.repite && !it.hecho) {
      more.addWidget(
        CardService.newTextParagraph().setText(
          'Se repite. "Marcar como hecho" lo termina: no se repite más.',
        ),
      );
    }
    more.addWidget(
      CardService.newButtonSet()
        .addButton(
          CardService.newTextButton()
            .setText(it.hecho ? '↩ Volver a pendiente' : '✓ Marcar como hecho')
            .setOnClickAction(
              action_('onToggle', {
                rec: it.key,
                hecho: it.hecho ? '1' : '',
                tab: tab,
                q: query || '',
              }),
            ),
        )
        .addButton(
          CardService.newTextButton()
            .setText('🗑 Borrar')
            .setOnClickAction(action_('onAskDelete', params)),
        ),
    );
    card.addSection(more);
  }

  card.setFixedFooter(
    CardService.newFixedFooter()
      .setPrimaryButton(
        CardService.newTextButton()
          .setText('Guardar')
          .setOnClickAction(action_('onSave', params)),
      )
      .setSecondaryButton(
        CardService.newTextButton()
          .setText('Cancelar')
          .setOnClickAction(action_('onBack', {})),
      ),
  );
  return card.build();
}

function messageCard_(title, text) {
  return CardService.newCardBuilder()
    .setHeader(
      CardService.newCardHeader()
        .setTitle('Recordame')
        .setImageUrl(LOGO)
        .setImageStyle(CardService.ImageStyle.CIRCLE),
    )
    .addSection(
      CardService.newCardSection()
        .addWidget(CardService.newTextParagraph().setText('<b>' + title + '</b>'))
        .addWidget(CardService.newTextParagraph().setText(text))
        .addWidget(
          CardService.newTextButton()
            .setText('⟳ Probar de nuevo')
            .setOnClickAction(action_('onTab', { tab: 'hoy', q: '' })),
        ),
    )
    .build();
}

// ---------------------------------------------------------------------------
// Botones
// ---------------------------------------------------------------------------

function onTab(e) {
  var p = e.commonEventObject.parameters || {};
  return show_(homeCard_(p.tab || 'hoy', p.q || ''));
}

function onSearch(e) {
  var p = e.commonEventObject.parameters || {};
  return show_(homeCard_(p.tab || 'hoy', text_(e, 'q')));
}

function onNew(e) {
  var p = e.commonEventObject.parameters || {};
  return push_(formCard_(null, p.tab, p.q));
}

function onEdit(e) {
  var p = e.commonEventObject.parameters || {};
  var it = find_(p.rec);
  if (!it) return show_(homeCard_(p.tab, p.q), 'Ese ya no está. Se habrá borrado.');
  return push_(formCard_(it, p.tab, p.q));
}

function onBack(e) {
  return CardService.newActionResponseBuilder()
    .setNavigation(CardService.newNavigation().popCard())
    .build();
}

function onToggle(e) {
  var p = e.commonEventObject.parameters || {};
  var done = !p.hecho;
  return write_(
    { tipo: done ? 'hecho' : 'pendiente', rec: p.rec },
    p,
    done ? 'Marcado como hecho ✓' : 'Vuelve a estar pendiente',
  );
}

function onSave(e) {
  var p = e.commonEventObject.parameters || {};
  var title = text_(e, 'titulo').trim();
  if (!title) return notify_('Escribí qué hay que recordar.');
  var inputs = e.commonEventObject.formInputs || {};
  var date = inputs.fecha && inputs.fecha.dateInput;
  var time = inputs.hora && inputs.hora.timeInput;
  if (!date) return notify_('Elegí la fecha.');
  var op = {
    tipo: p.rec ? 'modificar' : 'crear',
    rec: p.rec || 'pc-' + Utilities.getUuid(),
    titulo: title,
    fecha: Utilities.formatDate(new Date(Number(date.msSinceEpoch)), 'UTC', 'yyyy-MM-dd'),
    hora: time ? pad_(time.hours) + ':' + pad_(time.minutes) : '09:00',
    repetir: text_(e, 'repetir') || 'none',
  };
  return write_(op, p, p.rec ? 'Cambios guardados ✓' : 'Recordatorio creado ✓');
}

function onAskDelete(e) {
  var p = e.commonEventObject.parameters || {};
  var it = find_(p.rec);
  var card = CardService.newCardBuilder()
    .setHeader(CardService.newCardHeader().setTitle('¿Borrar este recordatorio?'))
    .addSection(
      CardService.newCardSection()
        .addWidget(
          CardService.newTextParagraph().setText(
            '<b>' + escape_(it ? it.titulo : '') + '</b><br>Se borra también del teléfono.',
          ),
        )
        .addWidget(
          CardService.newButtonSet()
            .addButton(
              CardService.newTextButton()
                .setText('Sí, borrar')
                .setTextButtonStyle(CardService.TextButtonStyle.FILLED)
                .setOnClickAction(action_('onDelete', p)),
            )
            .addButton(
              CardService.newTextButton()
                .setText('No')
                .setOnClickAction(action_('onBack', {})),
            ),
        ),
    )
    .build();
  return push_(card);
}

function onDelete(e) {
  var p = e.commonEventObject.parameters || {};
  return write_({ tipo: 'borrar', rec: p.rec }, p, 'Borrado 🗑');
}

/** Anota el cambio y vuelve a la lista. */
function write_(op, p, message) {
  try {
    addChange_(op);
  } catch (err) {
    return notify_('No pude guardar: ' + err);
  }
  return CardService.newActionResponseBuilder()
    .setNavigation(
      CardService.newNavigation()
        .popToRoot()
        .updateCard(homeCard_(p.tab || 'hoy', p.q || '')),
    )
    .setNotification(
      CardService.newNotification().setText(
        message + ' · llega al teléfono en un ratito.',
      ),
    )
    .build();
}

// ---------------------------------------------------------------------------
// Archivos en Drive
// ---------------------------------------------------------------------------

/** Busca la lista del teléfono y su archivo de cambios. */
function files_() {
  var it = DriveApp.searchFiles(
    "title contains 'Recordame-gmail' and trashed = false",
  );
  var main = null;
  var changes = [];
  while (it.hasNext()) {
    var f = it.next();
    var j = readJson_(f);
    if (!j) continue;
    if (j.formato === MAIN_FORMAT) {
      if (!main || String(j.actualizado) > String(main.data.actualizado)) {
        main = { file: f, data: j };
      }
    } else if (j.formato === CHANGES_FORMAT) {
      changes.push({ file: f, data: j });
    }
  }
  if (!main) return null;
  var mine = changes
    .filter(function (c) {
      return c.data.par === main.data.par;
    })
    .sort(function (a, b) {
      return b.file.getLastUpdated() - a.file.getLastUpdated();
    });
  return { main: main, changes: mine[0] || null };
}

function readJson_(file) {
  try {
    var text = file.getBlob().getDataAsString('UTF-8').trim();
    var end = text.lastIndexOf('}');
    if (end >= 0) text = text.substring(0, end + 1);
    return JSON.parse(text);
  } catch (err) {
    return null;
  }
}

/** Cambios hechos acá que el teléfono todavía no aplicó. */
function pending_(f) {
  if (!f.changes) return [];
  var applied = {};
  (f.main.data.aplicados || []).forEach(function (id) {
    applied[id] = true;
  });
  return (f.changes.data.cambios || []).filter(function (op) {
    return !applied[op.id];
  });
}

function addChange_(op) {
  var lock = LockService.getUserLock();
  lock.waitLock(20000);
  try {
    var f = files_();
    if (!f) throw 'no encuentro la lista del teléfono en Drive';
    if (!f.changes) {
      throw 'falta el archivo de cambios: en el teléfono tocá "Elegir dónde se guarda de nuevo"';
    }
    op.id = 'op-' + Utilities.getUuid();
    op.el = new Date().toISOString();
    var list = pending_(f);
    list.push(op);
    f.changes.file.setContent(
      JSON.stringify(
        { formato: CHANGES_FORMAT, par: f.main.data.par, cambios: list },
        null,
        1,
      ),
    );
  } finally {
    lock.releaseLock();
  }
}

/** La lista del teléfono más lo hecho acá que todavía está en camino. */
function load_() {
  var f = files_();
  if (!f) return null;
  var refs = f.main.data.refs || {};
  var byKey = {};
  var order = [];
  (f.main.data.recordatorios || []).forEach(function (r) {
    var it = Object.assign({}, r, { key: String(r.id) });
    byKey[it.key] = it;
    order.push(it.key);
  });
  function keyOf(rec) {
    rec = String(rec);
    return refs[rec] != null ? String(refs[rec]) : rec;
  }
  pending_(f).forEach(function (op) {
    var key = keyOf(op.rec);
    var it = byKey[key];
    if (op.tipo === 'crear') {
      if (it) return;
      byKey[key] = {
        key: key,
        titulo: op.titulo,
        fecha: op.fecha,
        hora: op.hora,
        repetir: op.repetir,
        repite: op.repetir && op.repetir !== 'none' ? repeatText_(op.repetir) : null,
        proxima: op.fecha + 'T' + op.hora,
        hecho: false,
        enCamino: true,
      };
      order.push(key);
      return;
    }
    if (!it) return;
    it.enCamino = true;
    if (op.tipo === 'modificar') {
      it.titulo = op.titulo;
      it.fecha = op.fecha;
      it.hora = op.hora;
      if (op.repetir !== 'igual') {
        it.repetir = op.repetir;
        it.repite = op.repetir !== 'none' ? repeatText_(op.repetir) : null;
      }
      it.proxima = op.fecha + 'T' + op.hora;
    } else if (op.tipo === 'hecho') {
      it.hecho = true;
      it.hechoEl = nowLocal_();
    } else if (op.tipo === 'pendiente') {
      it.hecho = false;
      it.hechoEl = null;
    } else if (op.tipo === 'borrar') {
      delete byKey[key];
    }
  });
  return {
    updated: String(f.main.data.actualizado || '').slice(0, 16),
    items: order
      .filter(function (k) {
        return byKey[k];
      })
      .map(function (k) {
        return byKey[k];
      }),
  };
}

function find_(key) {
  var state = load_();
  if (!state) return null;
  for (var i = 0; i < state.items.length; i++) {
    if (state.items[i].key === String(key)) return state.items[i];
  }
  return null;
}

// ---------------------------------------------------------------------------
// Ayudantes
// ---------------------------------------------------------------------------

function group_(items, now) {
  var today = now.slice(0, 10);
  var g = { vencidos: [], hoy: [], proximos: [], hechos: [] };
  items.forEach(function (it) {
    if (it.hecho) return g.hechos.push(it);
    var p = String(it.proxima || it.fecha + 'T' + it.hora);
    var repeats = it.repetir && it.repetir !== 'none';
    if (p < now && !(repeats && p.slice(0, 10) === today)) {
      if (repeats) return g.proximos.push(it);
      return g.vencidos.push(it);
    }
    if (p.slice(0, 10) === today) return g.hoy.push(it);
    g.proximos.push(it);
  });
  function byNext(a, b) {
    return String(a.proxima).localeCompare(String(b.proxima));
  }
  g.vencidos.sort(byNext).reverse();
  g.hoy.sort(byNext);
  g.proximos.sort(byNext);
  g.hechos.sort(function (a, b) {
    return String(b.hechoEl || '').localeCompare(String(a.hechoEl || ''));
  });
  return g;
}

/** Buscar sin tildes, mayúsculas ni orden de palabras. */
function filter_(items, query) {
  var words = plain_(query || '')
    .split(/\s+/)
    .filter(String);
  if (!words.length) return items;
  return items.filter(function (it) {
    var t = plain_(it.titulo);
    return words.every(function (w) {
      return t.indexOf(w) >= 0;
    });
  });
}

function plain_(s) {
  return String(s || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

function emptyText_(tab) {
  return {
    vencidos: 'No tenés nada vencido 👌',
    hoy: 'Nada para hoy.',
    proximos: 'No hay nada más adelante.',
    hechos: 'Todavía no hay hechos.',
  }[tab];
}

function repeatText_(kind) {
  for (var i = 0; i < REPEATS.length; i++) {
    if (REPEATS[i][0] === kind) return REPEATS[i][1].replace(/ \(.*\)/, '');
  }
  return null;
}

/** "Hoy 18:30", "Mañana 09:00", "mié 10/12 18:30". */
function whenText_(iso, now) {
  if (!iso) return '';
  iso = String(iso);
  var day = iso.slice(0, 10);
  var time = iso.slice(11, 16);
  var today = now.slice(0, 10);
  var d = new Date(day + 'T12:00:00Z');
  var t = new Date(today + 'T12:00:00Z');
  var diff = Math.round((d - t) / 86400000);
  var label =
    diff === 0
      ? 'Hoy'
      : diff === 1
        ? 'Mañana'
        : diff === -1
          ? 'Ayer'
          : DAYS[d.getUTCDay()] +
            ' ' +
            d.getUTCDate() +
            '/' +
            (d.getUTCMonth() + 1) +
            (d.getUTCFullYear() !== t.getUTCFullYear() ? '/' + d.getUTCFullYear() : '');
  return time ? label + ' ' + time : label;
}

function nowLocal_() {
  return Utilities.formatDate(
    new Date(),
    Session.getScriptTimeZone(),
    "yyyy-MM-dd'T'HH:mm",
  );
}

function nextHour_(now) {
  var h = Number(now.slice(11, 13)) + 1;
  return pad_(h > 23 ? 9 : h) + ':00';
}

function pad_(n) {
  return ('0' + n).slice(-2);
}

function escape_(s) {
  return String(s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function text_(e, name) {
  var input = (e.commonEventObject.formInputs || {})[name];
  return input && input.stringInputs ? input.stringInputs.value[0] || '' : '';
}

function action_(fn, params) {
  return CardService.newAction().setFunctionName(fn).setParameters(params || {});
}

function show_(card, message) {
  var b = CardService.newActionResponseBuilder().setNavigation(
    CardService.newNavigation().updateCard(card),
  );
  if (message) b.setNotification(CardService.newNotification().setText(message));
  return b.build();
}

function push_(card) {
  return CardService.newActionResponseBuilder()
    .setNavigation(CardService.newNavigation().pushCard(card))
    .build();
}

function notify_(text) {
  return CardService.newActionResponseBuilder()
    .setNotification(CardService.newNotification().setText(text))
    .build();
}
