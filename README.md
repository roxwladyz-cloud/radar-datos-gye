# Radar Urbano – Datos

Robot que cada semana revisa el portal de Datos Abiertos del Ecuador, descarga el Excel más reciente de **Homicidios Intencionales** (Ministerio del Interior), filtra Guayaquil y publica:

- `datos/homicidios_guayaquil.json` – archivo liviano que lee la app Radar Urbano.
- `datos/estado.json` – fecha de la última revisión y si salió bien.

Si el portal falla o el Excel cambia de formato, el robot **no borra** los datos anteriores.

Fuente: Ministerio del Interior – Dirección de Estadística y Economía de la Seguridad, publicado en datosabiertos.gob.ec.
