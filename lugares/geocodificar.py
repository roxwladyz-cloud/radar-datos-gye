"""
Robot de lugares de Radar Urbano (version 3).

Busca UNA VEZ las coordenadas de cada lugar de lugares/lugares_fuente.json en
OpenStreetMap (Nominatim, maximo 1 consulta por segundo, como piden sus reglas) y
genera datos/lugares.json, que la app usa para sugerir lugares mientras se escribe.

- Si un lugar ya tiene lat/lon en la fuente (corregido a mano), no se busca.
- Si un lugar ya estaba en datos/lugares.json con el mismo texto de busqueda, se reutiliza.
- Los que no se encuentran quedan en datos/lugares_revisar.json para corregirlos a mano.
"""
import json
import os
import time
import unicodedata

import requests

FUENTE = os.path.join("lugares", "lugares_fuente.json")
SALIDA = os.path.join("datos", "lugares.json")
REVISAR = os.path.join("datos", "lugares_revisar.json")
URL = "https://nominatim.openstreetmap.org/search"
CABECERAS = {"User-Agent": "RadarUrbano/3.0 (github.com/roxwladyz-cloud/radar-datos-gye)"}
CAJA = "-80.45,-1.55,-79.55,-2.75"  # Gran Guayaquil (oeste, norte, este, sur)
NOMBRE_CANTON = {"GUAYAQUIL": "Guayaquil", "DURAN": "Durán", "SAMBORONDON": "Samborondón", "DAULE": "Daule"}


def normalizar(texto):
    texto = unicodedata.normalize("NFKD", str(texto))
    texto = "".join(c for c in texto if not unicodedata.combining(c))
    return " ".join(texto.lower().split())


def buscar(texto, canton):
    params = {"q": f"{texto}, {NOMBRE_CANTON[canton]}, Guayas, Ecuador", "format": "jsonv2",
              "limit": 1, "countrycodes": "ec", "viewbox": CAJA, "bounded": 1, "addressdetails": 1}
    r = requests.get(URL, params=params, headers=CABECERAS, timeout=30)
    r.raise_for_status()
    datos = r.json()
    time.sleep(1.2)
    if not datos:
        return None
    d = datos[0]
    a = d.get("address", {})
    return {"lat": round(float(d["lat"]), 5), "lon": round(float(d["lon"]), 5),
            "osm": d.get("display_name", "")[:160],
            "zona_osm": a.get("county") or a.get("city") or a.get("town") or ""}


def main():
    fuente = json.load(open(FUENTE, encoding="utf-8"))["lugares"]
    try:
        previos = {(x["n"], x.get("_q", "")): x for x in json.load(open(SALIDA, encoding="utf-8"))["lugares"]}
    except (OSError, ValueError, KeyError):
        previos = {}
    lugares, revisar = [], []
    for l in fuente:
        q = l.get("q", l["n"])
        item = {"n": l["n"], "a": sorted({normalizar(x) for x in l.get("a", [])}), "c": l["c"], "_q": q}
        if "lat" in l and "lon" in l:
            item.update(lat=l["lat"], lon=l["lon"], origen="manual")
        elif (l["n"], q) in previos and previos[(l["n"], q)].get("origen") != "manual":
            p = previos[(l["n"], q)]
            item.update(lat=p["lat"], lon=p["lon"], origen=p.get("origen", "osm"), osm=p.get("osm", ""))
        else:
            try:
                res = buscar(q, l["c"])
            except Exception as e:  # sin conexion, limite, etc.
                res = None
                print("Error con", q, e)
            if not res:
                revisar.append({"n": l["n"], "q": q, "c": l["c"], "motivo": "no encontrado"})
                print("NO ENCONTRADO:", l["n"])
                continue
            item.update(lat=res["lat"], lon=res["lon"], origen="osm", osm=res["osm"])
            if res["zona_osm"] and normalizar(res["zona_osm"]) != normalizar(NOMBRE_CANTON[l["c"]]):
                revisar.append({"n": l["n"], "q": q, "c": l["c"], "motivo": f"OSM dice {res['zona_osm']}",
                                "lat": res["lat"], "lon": res["lon"], "osm": res["osm"]})
            print("OK:", l["n"], res["lat"], res["lon"], "|", res["osm"][:70])
        lugares.append(item)
    os.makedirs("datos", exist_ok=True)
    with open(SALIDA, "w", encoding="utf-8") as f:
        json.dump({"nota": "Lugares para sugerencias de Radar Urbano. Coordenadas: OpenStreetMap (ODbL).",
                   "lugares": lugares}, f, ensure_ascii=False, indent=0)
    with open(REVISAR, "w", encoding="utf-8") as f:
        json.dump(revisar, f, ensure_ascii=False, indent=1)
    print(f"Listo: {len(lugares)} lugares, {len(revisar)} para revisar")


if __name__ == "__main__":
    main()
