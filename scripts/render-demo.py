#!/usr/bin/env python3
"""Dibuja el estudio y el enjambre a partir de la traza JSON del propio programa.

La geometría de los cursores sale de DemoGuion (Swift). Esto solo la pinta
para poder verla sin un Mac. El aspecto imita el estudio oscuro del reel.
"""
import json
import os
import sys

ANCHO, ALTO = 1280, 720


def color(hexadecimal, alfa=255):
    h = hexadecimal.lstrip("#")
    if len(h) != 6:
        return (180, 186, 194, alfa)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alfa)


class Lienzo:
    def __init__(self):
        self.px = bytearray(ANCHO * ALTO * 3)

    def punto(self, x, y, rgb):
        if 0 <= x < ANCHO and 0 <= y < ALTO:
            i = (y * ANCHO + x) * 3
            self.px[i:i + 3] = bytes(rgb[:3])

    def rect(self, x, y, w, h, rgb):
        x0, y0 = max(0, int(x)), max(0, int(y))
        x1, y1 = min(ANCHO, int(x + w)), min(ALTO, int(y + h))
        if x1 <= x0 or y1 <= y0:
            return
        tramo = bytes(rgb[:3]) * (x1 - x0)
        for yy in range(y0, y1):
            i = (yy * ANCHO + x0) * 3
            self.px[i:i + len(tramo)] = tramo

    def flecha(self, x, y, angulo, escala, rgb):
        import math
        forma = [(0, 0), (-4, -12), (-1.4, -9), (-5.2, -16), (-3, -17), (0.4, -10), (4, -9.2)]
        coseno, seno = math.cos(-angulo), math.sin(-angulo)
        puntos = []
        for px, py in forma:
            rx = (px * coseno - py * seno) * escala + x
            ry = (px * seno + py * coseno) * escala + y
            puntos.append((rx, ry))
        self.poligono(puntos, rgb)

    def poligono(self, puntos, rgb):
        if len(puntos) < 3:
            return
        ys = [p[1] for p in puntos]
        y0, y1 = int(min(ys)), int(max(ys))
        for y in range(y0, y1 + 1):
            cortes = []
            for i, a in enumerate(puntos):
                b = puntos[(i + 1) % len(puntos)]
                if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                    if b[1] != a[1]:
                        t = (y - a[1]) / (b[1] - a[1])
                        cortes.append(a[0] + t * (b[0] - a[0]))
            cortes.sort()
            for i in range(0, len(cortes) - 1, 2):
                self.rect(cortes[i], y, cortes[i + 1] - cortes[i], 1, rgb)

    def guardar(self, ruta):
        with open(ruta, "wb") as salida:
            salida.write(f"P6\n{ANCHO} {ALTO}\n255\n".encode())
            salida.write(self.px)


def pintar(frame, ruta):
    lienzo = Lienzo()
    lienzo.rect(0, 0, ANCHO, ALTO, (14, 16, 20))
    lienzo.rect(0, 0, ANCHO, 46, (22, 24, 30))
    lienzo.rect(0, ALTO - 190, ANCHO, 190, (16, 18, 24))
    lienzo.rect(0, 46, 210, ALTO - 236, (18, 20, 26))
    lienzo.rect(ANCHO - 260, 46, 260, ALTO - 236, (20, 22, 28))
    lienzo.rect(240, 80, ANCHO - 540, ALTO - 310, (24, 26, 32))
    for bloque in frame.get("bloques", []):
        indice = hash(bloque["id"]) % 8
        y = ALTO - 168 + (indice % 6) * 24
        origen = 130 + int(bloque["i"] * 500)
        ancho = max(12, int(bloque["d"] * 700))
        lienzo.rect(origen, y, ancho, 16, (40, 48, 58))
        lienzo.rect(origen, y, int(ancho * bloque["p"]), 16, (46, 196, 168))
    for cursor in frame.get("cursores", []):
        x = int(cursor["x"] * ANCHO)
        y = int(cursor["y"] * (ALTO - 40)) + 20
        escala = 0.9 if cursor.get("f") else 1.15
        lienzo.flecha(x, y, cursor.get("a", -0.7), escala * cursor.get("e", 0.5) * 1.4, color(cursor.get("c", "#F4F6F8")))
    lienzo.guardar(ruta)


def main():
    traza = sys.argv[1]
    carpeta = sys.argv[2]
    os.makedirs(carpeta, exist_ok=True)
    with open(traza, encoding="utf-8") as entrada:
        frames = [json.loads(linea) for linea in entrada if linea.strip()]
    for indice, frame in enumerate(frames):
        pintar(frame, os.path.join(carpeta, f"f_{indice:04d}.ppm"))
        if indice % 10 == 0:
            print(f"fotograma {indice}/{len(frames)}", flush=True)
    print(f"{len(frames)} fotogramas")


if __name__ == "__main__":
    main()
