// Generado por tool/generar_sonidos.py: no editar a mano.

/// Un sonido propio de las prioridades (`res/raw/<id>.wav`).
class PrioritySound {
  const PrioritySound(this.id, this.name, this.millis);

  final String id;
  final String name;

  /// Lo que dura una vez (para "cuántas veces suena seguido").
  final int millis;
}

/// Sonidos nuevos para la prioridad media.
const mediaSounds = [
  PrioritySound('m_campanita_doble', 'Campanita doble', 1350),
  PrioritySound('m_gotas', 'Gotas', 690),
  PrioritySound('m_xilofon', 'Xilofón', 960),
  PrioritySound('m_ding_dong', 'Ding-dong', 1750),
  PrioritySound('m_pajarito', 'Pajarito', 660),
  PrioritySound('m_marimba', 'Marimba', 1080),
];

/// Musiquitas de la prioridad alta.
const altaSounds = [
  PrioritySound('a_sirena', 'Sirena', 1350),
  PrioritySound('a_despertador', 'Despertador', 960),
  PrioritySound('a_bocina', 'Bocina', 800),
  PrioritySound('a_alarma_digital', 'Alarma digital', 970),
  PrioritySound('a_melodia', 'Melodía rápida', 780),
  PrioritySound('a_trompeta', 'Trompeta', 860),
  PrioritySound('a_policia', 'Sirena de policía', 1200),
  PrioritySound('a_ambulancia', 'Sirena de ambulancia', 1600),
  PrioritySound('a_incendio', 'Alarma de incendio', 1000),
  PrioritySound('a_escuela', 'Campana de escuela', 1300),
  PrioritySound('a_alerta_roja', 'Alerta roja', 800),
  PrioritySound('a_barco', 'Bocina de barco', 1200),
  PrioritySound('a_radar', 'Radar', 1110),
  PrioritySound('a_fanfarria', 'Fanfarria', 1380),
  PrioritySound('a_gallo', 'Gallo', 670),
  PrioritySound('a_pitido', 'Pitido urgente', 830),
];
