"""
Robot mensual de Radar Urbano.

1. Busca en datosabiertos.gob.ec el Excel mas reciente de Homicidios Intencionales
   (Ministerio del Interior).
2. Se queda solo con los casos del canton Guayaquil.
3. Publica datos/homicidios_guayaquil.json, un archivo liviano que lee la app.

Si algo sale mal (portal caido, columnas cambiadas, datos sospechosos),
NO toca el archivo anterior: la app sigue funcionando con los ultimos datos buenos.

Uso:
    python robot.py                  -> descarga del portal
    python robot.py archivo.xlsx     -> procesa un Excel local (para pruebas)
"""

import io
import json
import os
import sys
import unicodedata
from datetime import datetime, timezone

import pandas as pd
import requests

PORTALES = [
    "https://datosabiertos.gob.ec",
    "https://www.datosabiertos.gob.ec",
    "https://datosabiertos.presidencia.gob.ec",
]
DATASET = "homicidios-intencionales"
CANTON = "GUAYAQUIL"
SALIDA = os.path.join("datos", "homicidios_guayaquil.json")
ESTADO = os.path.join("datos", "estado.json")
MINIMO_CASOS = 100  # menos que esto en Guayaquil = archivo sospechoso
COLUMNAS = ["subcircuito", "codigo_subcircuito", "distrito", "canton",
            "coordenada_y", "coordenada_x", "fecha_infraccion"]
CABECERAS = {"User-Agent": "RadarUrbanoRobot/1.0 (github.com/roxwladyz-cloud)"}


def normalizar(texto):
    """Quita tildes, pasa a mayusculas y limpia espacios: 'Peñas ' -> 'PENAS'."""
    texto = unicodedata.normalize("NFKD", str(texto))
    texto = "".join(c for c in texto if not unicodedata.combining(c))
    return " ".join(texto.upper().split())


def buscar_url_excel():
    """Pregunta al portal (API CKAN) cual es el Excel mas reciente."""
    errores = []
    for base in PORTALES:
        try:
            r = requests.get(f"{base}/api/3/action/package_show",
                             params={"id": DATASET}, headers=CABECERAS, timeout=60)
            r.raise_for_status()
            recursos = r.json()["result"]["resources"]
            excels = [x for x in recursos
                      if str(x.get("url", "")).lower().endswith((".xlsx", ".xls"))
                      or str(x.get("format", "")).lower() in ("xlsx", "xls")]
            if not excels:
                errores.append(f"{base}: sin archivos Excel")
                continue
            excels.sort(key=lambda x: x.get("last_modified") or x.get("created") or "",
                        reverse=True)
            return excels[0]["url"], excels[0].get("name", "")
        except Exception as e:  # probamos el siguiente portal
            errores.append(f"{base}: {e}")
    raise RuntimeError("No se pudo consultar el portal:\n" + "\n".join(errores))


def leer_excel(contenido):
    """Encuentra la hoja de datos y la fila de encabezados aunque cambien de lugar."""
    hojas = pd.read_excel(io.BytesIO(contenido), sheet_name=None, header=None)
    for nombre, hoja in hojas.items():
        for i in range(min(15, len(hoja))):
            fila = [str(v).strip().lower() for v in hoja.iloc[i].tolist()]
            if "subcircuito" in fila and "canton" in fila:
                datos = hoja.iloc[i + 1:].copy()
                datos.columns = fila
                return datos, nombre
    raise ValueError("Ninguna hoja tiene las columnas 'subcircuito' y 'canton'.")


def numero(valor):
    """Convierte '-2,11707' o -2.11707 en float. Devuelve None si no se puede."""
    try:
        return float(str(valor).strip().replace(",", "."))
    except ValueError:
        return None


def procesar(contenido, nombre_archivo):
    df, hoja = leer_excel(contenido)
    faltan = [c for c in COLUMNAS if c not in df.columns]
    if faltan:
        raise ValueError(f"El Ministerio cambio el formato. Faltan columnas: {faltan}")

    df = df[df["canton"].map(normalizar) == CANTON].copy()
    df["lat"] = df["coordenada_y"].map(numero)
    df["lon"] = df["coordenada_x"].map(numero)
    df["fecha"] = pd.to_datetime(df["fecha_infraccion"], errors="coerce", dayfirst=True)
    df = df.dropna(subset=["fecha"])
    # Coordenadas fuera de la zona de Guayaquil se descartan para el mapa
    dentro = df["lat"].between(-2.6, -1.8) & df["lon"].between(-80.3, -79.6)
    df["mes"] = df["fecha"].dt.strftime("%Y-%m")

    if len(df) < MINIMO_CASOS:
        raise ValueError(f"Solo {len(df)} casos en Guayaquil: archivo sospechoso, no se publica.")

    eventos = [[round(r.lat, 4), round(r.lon, 4), r.mes, str(r.codigo_subcircuito).strip()]
               for r in df[dentro].itertuples()]

    subcircuitos = {}
    for codigo, g in df.groupby(df["codigo_subcircuito"].astype(str).str.strip()):
        con_coord = g[g["lat"].between(-2.6, -1.8) & g["lon"].between(-80.3, -79.6)]
        subcircuitos[codigo] = {
            "nombre": normalizar(g["subcircuito"].iloc[0]),
            "distrito": normalizar(g["distrito"].iloc[0]),
            "total": int(len(g)),
            "por_mes": {k: int(v) for k, v in g.groupby("mes").size().sort_index().items()},
            "lat": round(float(con_coord["lat"].mean()), 4) if len(con_coord) else None,
            "lon": round(float(con_coord["lon"].mean()), 4) if len(con_coord) else None,
        }

    meses = sorted(df["mes"].unique())
    return {
        "fuente": "Ministerio del Interior - Homicidios Intencionales (datosabiertos.gob.ec)",
        "archivo_origen": nombre_archivo,
        "hoja": hoja,
        "canton": CANTON,
        "primer_mes": meses[0],
        "ultimo_mes": meses[-1],
        "total_casos": int(len(df)),
        "por_mes_ciudad": {k: int(v) for k, v in df.groupby("mes").size().sort_index().items()},
        "subcircuitos": subcircuitos,
        "eventos_formato": ["lat", "lon", "mes", "codigo_subcircuito"],
        "eventos": eventos,
    }


def guardar_estado(ok, mensaje):
    os.makedirs("datos", exist_ok=True)
    with open(ESTADO, "w", encoding="utf-8") as f:
        json.dump({"revisado": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                   "ok": ok, "mensaje": mensaje}, f, ensure_ascii=False, indent=2)


def main():
    try:
        if len(sys.argv) > 1:
            nombre = os.path.basename(sys.argv[1])
            with open(sys.argv[1], "rb") as f:
                contenido = f.read()
        else:
            url, nombre = buscar_url_excel()
            print("Descargando:", url)
            r = requests.get(url, headers=CABECERAS, timeout=180)
            r.raise_for_status()
            contenido = r.content
            nombre = nombre or url.rsplit("/", 1)[-1]

        resultado = procesar(contenido, nombre)
        resultado["generado"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
        os.makedirs("datos", exist_ok=True)
        with open(SALIDA, "w", encoding="utf-8") as f:
            json.dump(resultado, f, ensure_ascii=False, separators=(",", ":"))
        msg = (f"OK: {resultado['total_casos']} casos, "
               f"{resultado['primer_mes']} a {resultado['ultimo_mes']}, "
               f"{len(resultado['subcircuitos'])} subcircuitos ({nombre})")
        print(msg)
        guardar_estado(True, msg)
    except Exception as e:
        print("ERROR:", e)
        guardar_estado(False, f"Se mantienen los datos anteriores. Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
